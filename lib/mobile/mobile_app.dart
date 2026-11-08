import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/plan_store.dart';
import '../data/reminder_schedule.dart';
import '../data/transfer.dart';
import '../design/tokens.dart';
import '../domain/time_math.dart';
import '../platform/file_transfer.dart';
import '../platform/reminders.dart';
import 'mobile_dashboard.dart';
import 'mobile_editor.dart';
import 'mobile_layers.dart';
import 'mobile_summary.dart';

enum MobileTab { dashboard, edit, summary }

/// Android 入口外壳。
///
/// Windows 版的外壳（app.dart）绑着窗口管理、托盘、悬浮窗第二进程与注册表
/// 自启，这些在 Android 上都不存在，所以移动端另起一棵树，而不是给桌面壳
/// 打补丁。数据、判定、配色、圆环绘制全部复用同一套代码：
/// `PlanStore` → `AppData.forDate` → `Palette` → `DualRing`。
class MobileApp extends StatefulWidget {
  const MobileApp({
    super.key,
    required this.store,
    this.initialData,
    this.loadError,
  });

  final PlanStore store;
  final AppData? initialData;
  final Object? loadError;

  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  AppData? _data;
  Object? _error;
  late DateTime _now;
  Timer? _ticker;
  Timer? _saveDebounce;
  Timer? _toastTimer;

  /// 排程 / 重排提醒是「清空 + 逐条登记」，比存盘贵得多。打字时每次
  /// commit 都排一遍会卡输入，所以单独一道更长的防抖。
  Timer? _reminderDebounce;
  ReminderAccess _access = ReminderAccess.granted;

  MobileTab _tab = MobileTab.dashboard;
  MobileLayer _layer = MobileLayer.none;
  String? _editPlanId;
  String _dataPathText = '读取中…';
  String? _toastText;
  bool _busy = false;

  ({AppData data, String origin})? _pendingImport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = DateTime.now();
    _data = widget.initialData;
    _error = widget.loadError;
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      final next = DateTime.now();
      final crossedDay = TimeMath.dateKey(next) != TimeMath.dateKey(_now);
      setState(() => _now = next);
      if (crossedDay) {
        _ensureTodaySnapshot();
        // 跨零点后「接下来 7 天」整体前移一天，提醒必须重排，
        // 否则第八天起就没有通知了。
        _syncReminders();
      }
    });
    unawaited(
      widget.store.dataFilePath().then((p) {
        if (mounted) setState(() => _dataPathText = p);
      }),
    );
    if (_data == null && _error == null) {
      // 调用方没在入口预读数据时（例如 widget 测试），自己拉一次。
      unawaited(_bootstrap());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTodaySnapshot();
        unawaited(_refreshAccess());
        _syncReminders(immediate: true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _saveDebounce?.cancel();
    _toastTimer?.cancel();
    _reminderDebounce?.cancel();
    super.dispose();
  }

  /// 回到前台时系统权限可能已被改过（用户刚去设置里放行/关掉），
  /// 同时补一次排程 —— 手机上的 App 常年不重启，只靠启动那一次不够。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshAccess());
    _syncReminders();
  }

  // ---------------------------------------------------------------- 数据

  Future<void> _bootstrap() async {
    try {
      final loaded = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _data = loaded;
        _error = null;
      });
      _ensureTodaySnapshot();
      unawaited(_refreshAccess());
      _syncReminders(immediate: true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _commit(AppData next, {bool saveNow = false}) {
    if (!mounted) return;
    setState(() {
      _data = next;
      _error = null;
    });
    _saveDebounce?.cancel();
    if (saveNow) {
      unawaited(_flush(next));
      _syncReminders();
      return;
    }
    _saveDebounce = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_flush(next)),
    );
    _syncReminders();
  }

  Future<void> _flush(AppData data) async {
    try {
      await widget.store.save(data);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _ensureTodaySnapshot() {
    final data = _data;
    if (data == null) return;
    final key = TimeMath.dateKey(_now);
    if (data.daySnapshots.containsKey(key)) return;
    final resolved = data.forDate(_now);
    _commit(
      data.withSnapshot(
        key,
        DaySnapshot(
          planId: resolved.planId,
          mode: resolved.mode,
          source: resolved.source,
        ),
      ),
      saveNow: true,
    );
  }

  void _assignDay(String dateKey, String? planId) {
    final data = _data;
    if (data == null) return;
    _commit(
      data.assignDay(dateKey, planId, at: DateTime.now().toIso8601String()),
      saveNow: true,
    );
    setState(() => _layer = MobileLayer.none);
  }

  void _setTheme(AppTheme next) {
    if (next == Palette.theme) return;
    Palette.setTheme(next);
    final data = _data;
    if (data != null) {
      _commit(data.withUi(data.ui.copyWith(theme: next.key)), saveNow: true);
    } else {
      setState(() {});
    }
  }

  /// 改计划表名字。只动 `name`，重复规则与作息一律不碰。
  void _renamePlan(String planId, String name) {
    final data = _data;
    if (data == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (data.planById(planId)?.name == trimmed) return;
    _commit(
      data.withPlans([
        for (final p in data.plans)
          p.id == planId ? p.copyWith(name: trimmed) : p,
      ]),
      saveNow: true,
    );
  }

  // ---------------------------------------------------------------- 到点提醒

  Future<void> _refreshAccess() async {
    try {
      final access = await Reminders.instance.check();
      if (mounted) setState(() => _access = access);
    } on Object {
      // 通道不可用（例如测试 / 桌面）不影响主流程，保持默认值即可。
    }
  }

  void _syncReminders({bool immediate = false}) {
    _reminderDebounce?.cancel();
    if (immediate) {
      unawaited(_applyReminders());
      return;
    }
    _reminderDebounce = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_applyReminders()),
    );
  }

  Future<void> _applyReminders() async {
    final data = _data;
    if (data == null) return;
    try {
      if (data.ui.remindersEnabled) {
        await Reminders.instance.sync(buildReminderSlots(data, DateTime.now()));
      } else {
        await Reminders.instance.cancelAll();
      }
    } on Object {
      // 没有权限 / 系统拒绝排程时静默失败：界面上的开关状态与权限提示
      // 已经把话说清楚了，这里再弹一次只会重复。
    }
  }

  Future<void> _setReminders(bool on) async {
    final data = _data;
    if (data == null) return;
    var access = _access;
    if (on) {
      try {
        access = await Reminders.instance.request();
      } on Object {
        access = _access;
      }
    }
    if (!mounted) return;
    setState(() => _access = access);
    _commit(
      data.withUi(data.ui.copyWith(remindersEnabled: on)),
      saveNow: true,
    );
    await _applyReminders();
    if (!on) {
      _showToast('已关闭到点提醒');
    } else if (!access.notifications) {
      _showToast('系统还没允许通知，去设置里放行后才会响');
    } else if (!access.exact) {
      _showToast('已开始提醒；精确闹钟未放行，可能晚几分钟');
    } else {
      _showToast('已按接下来 7 天排好提醒');
    }
  }

  Future<void> _requestReminderAccess() async {
    try {
      final access = await Reminders.instance.request();
      if (!mounted) return;
      setState(() => _access = access);
      _showToast(access.ready ? '通知与精确闹钟已放行' : '还有权限没放行，请到系统设置里手动允许');
      await _applyReminders();
    } on Object {
      _showToast('打不开系统授权页，请到「设置 → 应用 → 我的时间」手动允许');
    }
  }

  // ---------------------------------------------------------------- 导入导出

  Future<void> _exportBackup() async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    try {
      final text = PlanBackup.encode(
        data,
        sourcePlatform: Platform.isAndroid ? 'android' : 'windows',
        appVersion: '0.10.0',
      );
      final saved = await PlanFileTransfer.saveText(
        suggestedName: PlanBackup.fileName(_now),
        content: text,
      );
      _showToast(saved == null ? '已取消导出' : '备份已导出');
    } on Object catch (e) {
      _showToast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final text = await PlanFileTransfer.readText();
      if (text == null) return;
      final parsed = PlanBackup.decode(text);
      setState(() {
        _pendingImport = (data: parsed.data, origin: parsed.origin);
        _layer = MobileLayer.confirmImport;
      });
    } on PlanBackupException catch (e) {
      _showToast(e.message);
    } on Object catch (e) {
      _showToast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final pending = _pendingImport;
    if (pending == null) return;
    try {
      await widget.store.replace(pending.data);
      final reloaded = await widget.store.load(forceReload: true);
      if (!mounted) return;
      setState(() {
        _data = reloaded;
        _pendingImport = null;
        _layer = MobileLayer.none;
      });
      _ensureTodaySnapshot();
      _syncReminders(immediate: true);
      _showToast('已导入 ${pending.origin} 的计划表');
    } on Object catch (e) {
      _showToast('导入失败：$e');
      if (mounted) setState(() => _layer = MobileLayer.none);
    }
  }

  Future<void> _exportReport(String fileName, String content) async {
    try {
      final saved = await PlanFileTransfer.saveText(
        suggestedName: fileName,
        content: content,
      );
      _showToast(saved == null ? '已取消导出' : '报告已保存');
    } on Object catch (e) {
      _showToast('报告导出失败：$e');
    }
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastText = message);
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 安卓的返回手势等于「关掉当前浮层」，没有浮层时才交给系统退出应用。
      // 桌面版没有这个语义（Esc 已经在各浮层里各自处理）。
      canPop: _layer == MobileLayer.none,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _layer = _layer == MobileLayer.confirmImport
              ? MobileLayer.data
              : MobileLayer.none;
        });
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '我的时间',
        theme: Palette.themeData(),
        home: Scaffold(
          backgroundColor: Palette.ground,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _TopBar(
                      now: _now,
                      onTheme: () => _setTheme(Palette.theme.flipped),
                      onData: () => setState(() => _layer = MobileLayer.data),
                    ),
                    Expanded(child: _body()),
                    _BottomBar(
                      tab: _tab,
                      onChanged: (t) => setState(() {
                        _tab = t;
                        if (t != MobileTab.edit) _editPlanId = null;
                      }),
                    ),
                  ],
                ),
                if (_layer == MobileLayer.plans && _data != null)
                  MobilePlanSheet(
                    data: _data!,
                    now: _now,
                    onClose: _closeLayer,
                    onAssign: _assignDay,
                    onRenamePlan: _renamePlan,
                    onEditPlan: (id) => setState(() {
                      _editPlanId = id;
                      _tab = MobileTab.edit;
                      _layer = MobileLayer.none;
                    }),
                  ),
                if (_layer == MobileLayer.data)
                  MobileDataSheet(
                    dataPath: _dataPathText,
                    theme: Palette.theme,
                    busy: _busy,
                    remindersEnabled: _data?.ui.remindersEnabled ?? false,
                    access: _access,
                    onClose: _closeLayer,
                    onTheme: _setTheme,
                    onExport: _exportBackup,
                    onImport: _importBackup,
                    onReminders: (on) => unawaited(_setReminders(on)),
                    onRequestAccess: () => unawaited(_requestReminderAccess()),
                  ),
                if (_layer == MobileLayer.confirmImport &&
                    _pendingImport != null)
                  MobileConfirmSheet(
                    origin: _pendingImport!.origin,
                    onCancel: () => setState(() {
                      _pendingImport = null;
                      _layer = MobileLayer.none;
                    }),
                    onConfirm: () => unawaited(_confirmImport()),
                  ),
                if (_toastText != null)
                  Positioned(
                    bottom: 78,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.raised,
                            border: Border.all(color: Palette.border),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            _toastText!,
                            style: TypeScale.body,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closeLayer() => setState(() => _layer = MobileLayer.none);

  Widget _body() {
    final data = _data;
    if (data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error == null ? '正在读取计划表…' : '数据读取失败：$_error',
                style: TypeScale.body,
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final loaded = await widget.store.load(forceReload: true);
                      if (mounted) {
                        setState(() {
                          _data = loaded;
                          _error = null;
                        });
                      }
                    } on Object catch (e) {
                      if (mounted) setState(() => _error = e);
                    }
                  },
                  child: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return switch (_tab) {
      MobileTab.dashboard => MobileDashboard(
        data: data,
        now: _now,
        onOpenPlans: () => setState(() => _layer = MobileLayer.plans),
      ),
      MobileTab.edit => MobileEditor(
        key: ValueKey(_editPlanId ?? 'today'),
        data: data,
        now: _now,
        planIdOverride: _editPlanId,
        onChanged: _commit,
      ),
      MobileTab.summary => MobileSummary(
        data: data,
        now: _now,
        onExportReport: (name, content) =>
            unawaited(_exportReport(name, content)),
      ),
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.now,
    required this.onTheme,
    required this.onData,
  });

  final DateTime now;
  final VoidCallback onTheme;
  final VoidCallback onData;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的时间', style: TypeScale.title),
                Text(
                  TimeMath.formatHm(now.hour * 60 + now.minute),
                  style: TypeScale.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTheme,
            icon: const Icon(Icons.brightness_6_outlined, size: 21),
            color: Palette.muted,
            tooltip: '切换主题',
          ),
          IconButton(
            onPressed: onData,
            icon: const Icon(Icons.storage_outlined, size: 21),
            color: Palette.muted,
            tooltip: '数据',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.onChanged});

  final MobileTab tab;
  final ValueChanged<MobileTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border(top: BorderSide(color: Palette.border)),
      ),
      child: Row(
        children: [
          for (final item in const [
            (MobileTab.dashboard, Icons.donut_large_outlined, '看板'),
            (MobileTab.edit, Icons.edit_calendar_outlined, '编辑'),
            (MobileTab.summary, Icons.bar_chart_outlined, '汇总'),
          ])
            Expanded(
              child: InkWell(
                onTap: () => onChanged(item.$1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.$2,
                      size: 21,
                      color: item.$1 == tab ? Palette.accent : Palette.muted,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$3,
                      style: item.$1 == tab
                          ? TypeScale.label
                          : TypeScale.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
