import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/plan_store.dart';
import '../data/transfer.dart';
import '../design/tokens.dart';
import '../domain/time_math.dart';
import '../platform/file_transfer.dart';
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

class _MobileAppState extends State<MobileApp> {
  AppData? _data;
  Object? _error;
  late DateTime _now;
  Timer? _ticker;
  Timer? _saveDebounce;
  Timer? _toastTimer;

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
    _now = DateTime.now();
    _data = widget.initialData;
    _error = widget.loadError;
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      final next = DateTime.now();
      final crossedDay = TimeMath.dateKey(next) != TimeMath.dateKey(_now);
      setState(() => _now = next);
      if (crossedDay) _ensureTodaySnapshot();
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTodaySnapshot(),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveDebounce?.cancel();
    _toastTimer?.cancel();
    super.dispose();
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
      return;
    }
    _saveDebounce = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_flush(next)),
    );
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
                    onClose: _closeLayer,
                    onTheme: _setTheme,
                    onExport: _exportBackup,
                    onImport: _importBackup,
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
