import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../data/app_data.dart';
import '../data/app_repository.dart';
import '../design/tokens.dart';
import '../domain/actual_records.dart';
import '../domain/category.dart';
import '../domain/plan.dart';
import '../domain/time_math.dart';
import '../float/float_protocol.dart';
import '../ui/l1/dashboard_screen.dart';
import '../ui/l2/edit_screen.dart';
import '../ui/l3/summary_screen.dart';
import '../ui/shell/app_window_bar.dart';
import '../ui/shell/plan_manager.dart';
import '../ui/shell/plan_popover.dart';
import '../ui/shell/settings_panel.dart';
import '../ui/widgets/app_card.dart';
import 'app_view.dart';
import 'autostart.dart';
import 'float_controller.dart';
import 'float_position.dart';

class RoutineApp extends StatefulWidget {
  const RoutineApp({
    super.key,
    required this.repository,
    this.initialData,
    this.loadError,
    this.startHidden = false,
  });

  final AppRepository repository;
  final AppData? initialData;
  final Object? loadError;

  /// `--autostart` 启动：只留托盘和悬浮窗，不弹主窗口。
  final bool startHidden;

  @override
  State<RoutineApp> createState() => _RoutineAppState();
}

class _RoutineAppState extends State<RoutineApp>
    with WindowListener, TrayListener {
  AppData? _data;
  Object? _error;
  DateTime _now = DateTime.now();
  Timer? _ticker;
  Timer? _saveDebounce;
  bool _trayReady = false;
  AppView _view = AppView.dashboard;
  bool _maximized = false;
  bool _settingsOpen = false;
  bool _planPickerOpen = false;
  bool _planManagerOpen = false;
  DateTime? _dayAssignDate;

  /// 从计划表编辑器点「编辑作息」时锁定目标表；从顶栏切视图则清空，
  /// 回到「编辑今天生效的表」。
  String? _editPlanId;

  FloatController? _float;
  bool _floatEnabled = false;
  bool _openAtLogin = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    _error = widget.loadError;
    _applyInitialTheme();

    windowManager.addListener(this);
    trayManager.addListener(this);
    _floatEnabled = _data?.ui.floatWindow.enabled ?? true;
    _openAtLogin = _data?.ui.openAtLogin ?? false;

    unawaited(_initTray().then((_) => _initAutostart()));
    unawaited(_bootFloat());
    _ensureTodaySnapshot();

    // 20 秒一跳。指针和"还剩 N 分钟"要自己走，不然得手动刷新才有变化。
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _float?.broadcast(_snapshot());
    });
  }

  /// 主题在首帧之前定好，否则浅色系统会先闪一下深色。
  /// 用户显式选过就照他选的；没选过才跟随系统亮度。
  void _applyInitialTheme() {
    final saved = _data?.ui.theme;
    final theme = saved != null
        ? AppTheme.fromKey(saved)
        : (PlatformDispatcher.instance.platformBrightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark);
    Palette.setTheme(theme);
    // 窗口已经不是透明分层窗口了，背景色必须和主题一起定：
    // 首帧按系统亮度给一个值，这里再按 data.json 里用户选过的主题校正。
    unawaited(windowManager.setBackgroundColor(Palette.ground));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveDebounce?.cancel();
    unawaited(_float?.dispose() ?? Future<void>.value());
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      final iconPath = await _ensureTrayIcon();
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('我的时间');
      _trayReady = true;
      await _setTrayMenu();
    } on Object catch (e) {
      // 托盘挂掉不致命，但会让"关闭后还能回来"失效，所以降级为"关闭即退出"。
      // 开机自启时主窗口本来就没显示，没有托盘就彻底找不回来了，必须兜底弹出。
      debugPrint('托盘初始化失败，关闭窗口将直接退出：$e');
      _trayReady = false;
      if (widget.startHidden) unawaited(_showMain());
    }
  }

  Future<void> _setTrayMenu() async {
    if (!_trayReady) return;
    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开看板'),
            MenuItem(
              key: 'theme',
              label: Palette.theme == AppTheme.light ? '切换到深色主题' : '切换到浅色主题',
            ),
            MenuItem(key: 'float', label: _floatEnabled ? '隐藏悬浮窗' : '显示悬浮窗'),
            MenuItem.checkbox(
              key: 'login',
              label: '开机自启',
              checked: _openAtLogin,
            ),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
    } on Object catch (e) {
      debugPrint('托盘菜单更新失败：$e');
    }
  }

  Future<String> _ensureTrayIcon() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}routine_tray.ico');
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/tray.ico');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return file.path;
  }

  /// 编辑态的唯一写入口。
  ///
  /// 拖拽时每一帧都会调它，所以 setState 立即做（保证 300ms 内联动），
  /// 写盘防抖 —— 否则一次拖拽能把磁盘写几十遍，还可能在半途留下 .tmp。
  void _commit(AppData next, {bool saveNow = false}) {
    if (!mounted) return;
    setState(() => _data = next);
    _float?.broadcast(_snapshot());
    _saveDebounce?.cancel();
    if (saveNow) {
      _flush(next);
      return;
    }
    _saveDebounce = Timer(
      const Duration(milliseconds: 280),
      () => _flush(next),
    );
  }

  Future<void> _flush(AppData data) async {
    try {
      await widget.repository.save(data);
    } on Object catch (e) {
      debugPrint('保存失败：$e');
      if (mounted) {
        setState(() => _error = AppDataException('改动没能写进磁盘', cause: e));
      }
    }
  }

  /// 每天第一次启动写一条快照。L3 的周/月视图靠它区分
  /// 「安装之前，无数据」和「有数据但真的是 0 分钟」。
  Future<void> _ensureTodaySnapshot() async {
    final data = _data;
    if (data == null) return;
    final key = TimeMath.dateKey(_now);
    if (data.daySnapshots.containsKey(key)) return;
    final resolved = data.forDate(_now);
    final next = data.withSnapshot(
      key,
      DaySnapshot(
        planId: resolved.planId,
        mode: resolved.mode,
        source: resolved.source,
      ),
    );
    _commit(next, saveNow: true);
  }

  // ---------------------------------------------------------------- 视图 / 主题 / 规则

  /// 切视图只换内容，不动窗口。
  ///
  /// 以前这里会 setSize(540↔720)：一个是会压过用户手动拉大的窗口，
  /// 另一个是透明分层窗口每次改尺寸都要整块重新合成，点击后明显卡一下。
  /// 现在窗口归用户管，三屏内容都按当前视口自适应。
  void _changeView(AppView view) {
    if (view == _view && _editPlanId == null) return;
    // 从顶栏进编辑 = 编辑今天生效的表；清掉从管理面板带过来的锁定。
    setState(() {
      _view = view;
      _editPlanId = null;
    });
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 设置面板里选中某一套主题。点当前已选的那一项不写盘、也不重建。
  void _setTheme(AppTheme next) {
    if (next == Palette.theme) return;
    // 先换令牌再重建，build 里读到的就全是新主题的值。
    Palette.setTheme(next);
    unawaited(windowManager.setBackgroundColor(Palette.ground));
    // 托盘那一项写的是「将要切到」的那一套，换完得刷新菜单文案。
    unawaited(_setTrayMenu());
    final data = _data;
    if (data != null) {
      _commit(data.withUi(data.ui.copyWith(theme: next.key)), saveNow: true);
    } else if (mounted) {
      setState(() {});
    }
  }

  /// 托盘菜单走这个：切到另一套。
  void _toggleTheme() => _setTheme(Palette.theme.flipped);

  void _toggleSettings() => setState(() {
    _planPickerOpen = false;
    _planManagerOpen = false;
    _dayAssignDate = null;
    _settingsOpen = !_settingsOpen;
  });

  void _closeSettings() => setState(() => _settingsOpen = false);

  // ------------------------------------------------------------ 计划表 / 单日指派

  /// 所有浮层互斥；关闭时一并收起设置面板。
  void _closeLayers() => setState(() {
    _settingsOpen = false;
    _planPickerOpen = false;
    _planManagerOpen = false;
    _dayAssignDate = null;
  });

  void _openPlanPicker() => setState(() {
    _settingsOpen = false;
    _planManagerOpen = false;
    _dayAssignDate = null;
    _planPickerOpen = !_planPickerOpen;
  });

  void _openPlanManager() => setState(() {
    _settingsOpen = false;
    _planPickerOpen = false;
    _dayAssignDate = null;
    _planManagerOpen = !_planManagerOpen;
  });

  void _openDayAssign(DateTime date) => setState(() {
    _settingsOpen = false;
    _planPickerOpen = false;
    _planManagerOpen = false;
    _dayAssignDate = date;
  });

  /// 顶栏切表 / 日历点选共用的唯一写入口。
  ///
  /// `assignDay` 会同时覆盖当天快照，所以「大半天后才切换」也不会出现
  /// 看板已经换表、汇总还按启动时那张表算的矛盾。整天按改判后的表算。
  void _assignDay(String dateKey, String? planId) {
    final data = _data;
    if (data == null) return;
    _commit(
      data.assignDay(dateKey, planId, at: DateTime.now().toIso8601String()),
      saveNow: true,
    );
    _closeLayers();
  }

  /// 管理面板整列表替换。当天若没被手动改判，顺手刷新快照 ——
  /// 否则用户刚改完重复规则，L1 已按新规则走、L3 还按启动时的旧快照。
  void _updatePlans(List<Plan> next) {
    final data = _data;
    if (data == null) return;
    var updated = data.withPlans(next);
    final key = TimeMath.dateKey(_now);
    final snap = updated.daySnapshots[key];
    if (snap != null && !snap.isOverridden) {
      final r = updated.forDate(_now);
      updated = updated.withSnapshot(
        key,
        DaySnapshot(planId: r.planId, mode: r.mode, source: r.source),
      );
    }
    _commit(updated, saveNow: true);
  }

  /// 从计划表编辑器点「编辑这张表的作息」：切到 L2 并锁定目标表。
  void _editBlocksOf(String planId) => setState(() {
    _settingsOpen = false;
    _planPickerOpen = false;
    _planManagerOpen = false;
    _dayAssignDate = null;
    _view = AppView.edit;
    _editPlanId = planId;
  });

  // --------------------------------------------------------------- 悬浮窗 / 自启

  FloatSnapshot _snapshot() {
    final data = _data;
    return FloatSnapshot(
      blocks: data?.forDate(_now).blocks ?? const [],
      theme: Palette.theme.key,
    );
  }

  Future<void> _bootFloat() async {
    final data = _data;
    if (data == null || !FloatController.canRun) return;

    final controller = FloatController(
      onShowMain: _showMain,
      onHideFloat: _hideFloatFromFloat,
      onMoved: _onFloatMoved,
    );
    _float = controller;
    await controller.start();
    if (!_floatEnabled) return;
    await controller.show(await _resolveFloatPosition(), _snapshot());
  }

  Future<Offset> _resolveFloatPosition() async {
    final prefs = _data?.ui.floatWindow;
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      return resolveFloatPosition(
        x: prefs?.x,
        y: prefs?.y,
        displays: displays,
        primary: primary,
      );
    } on Object {
      return resolveFloatPosition(
        x: prefs?.x,
        y: prefs?.y,
        displays: const [],
        primary: null,
      );
    }
  }

  Future<void> _toggleFloat() async {
    final next = !_floatEnabled;
    setState(() => _floatEnabled = next);
    _setFloatPrefs(enabled: next);
    await _setTrayMenu();

    final controller = _float;
    if (controller == null) return;
    if (next) {
      await controller.show(await _resolveFloatPosition(), _snapshot());
    } else {
      await controller.hide();
    }
  }

  Future<void> _hideFloatFromFloat() async {
    if (!_floatEnabled) return;
    setState(() => _floatEnabled = false);
    _setFloatPrefs(enabled: false);
    await _setTrayMenu();
    await _float?.hide();
  }

  void _onFloatMoved(Offset position) {
    _setFloatPrefs(x: position.dx, y: position.dy);
  }

  void _setFloatPrefs({bool? enabled, double? x, double? y}) {
    final data = _data;
    if (data == null) return;
    _commit(
      data.withUi(
        data.ui.copyWith(
          floatWindow: data.ui.floatWindow.copyWith(
            enabled: enabled,
            x: x,
            y: y,
          ),
        ),
      ),
      saveNow: enabled != null,
    );
  }

  Future<void> _showMain() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 启动时只读状态，不写注册表。
  /// 用户可能在任务管理器里关过自启 —— 那也是一次明确的拒绝，
  /// 每次启动再替他打开就成了跟他对着干。以实际状态为准，反过来改存档。
  Future<void> _initAutostart() async {
    final actual = await isAutostartEnabled();
    final saved = _data?.ui.openAtLogin ?? false;
    if (!mounted) return;
    if (_openAtLogin != actual) setState(() => _openAtLogin = actual);
    if (saved != actual) {
      final data = _data;
      if (data != null) {
        _commit(
          data.withUi(data.ui.copyWith(openAtLogin: actual)),
          saveNow: true,
        );
      }
    }
    await _setTrayMenu();
  }

  Future<void> _toggleAutostart() async {
    final next = !_openAtLogin;
    if (!await setAutostart(next)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '没能写入开机自启设置',
            style: TypeScale.label.copyWith(color: Palette.text),
          ),
          behavior: SnackBarBehavior.floating,
          width: 280,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _openAtLogin = next);
    final data = _data;
    if (data != null) {
      _commit(data.withUi(data.ui.copyWith(openAtLogin: next)), saveNow: true);
    }
    await _setTrayMenu();
  }

  Future<void> _quitApp() async {
    _saveDebounce?.cancel();
    final data = _data;
    if (data != null) await _flush(data);
    await _float?.dispose();
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowClose() async {
    _saveDebounce?.cancel();
    final data = _data;
    if (data != null) await _flush(data);

    if (_trayReady) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await _showMain();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showMain();
      case 'theme':
        _toggleTheme();
      case 'float':
        await _toggleFloat();
      case 'login':
        await _toggleAutostart();
      case 'quit':
        await _quitApp();
    }
  }

  Future<void> _reload() async {
    try {
      final data = await widget.repository.load(forceReload: true);
      setState(() {
        _data = data;
        _error = null;
      });
    } on Object catch (e) {
      setState(() => _error = e);
    }
  }

  /// 「我实际在做…」：只改**当前这一段**的实际分类，计划表不动。
  void _overrideCurrent(Category category) {
    final data = _data;
    if (data == null) return;
    final b = TimeMath.blockAt(
      data.forDate(_now).blocks,
      _now.hour * 60 + _now.minute,
    );
    if (b == null) return;
    _commit(
      data.withRecords(
        ActualRecords.withOverride(
          data.records,
          TimeMath.dateKey(_now),
          b.start,
          category,
        ),
      ),
      saveNow: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的时间',
      debugShowCheckedModeBanner: false,
      theme: Palette.themeData(),
      home: Scaffold(
        backgroundColor: Palette.ground,
        body: Stack(
          children: [
            // 整窗内容铺满整个矩形。窗口已改成不透明背景，这层渐变既当
            // 视觉地面也当四角底色，最大化/还原不再走透明分层窗口重合成。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: Palette.backgroundGlow),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.pad),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Palette.app,
                      borderRadius: BorderRadius.circular(Radii.window),
                      border: Border.all(color: Palette.border),
                      boxShadow: Palette.windowShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.window),
                      child: Column(
                        children: [
                          AppWindowBar(
                            dateLabel: _dateLabel,
                            planLabel: _planLabel,
                            view: _view,
                            onViewChanged: _changeView,
                            planPickerOpen: _planPickerOpen,
                            onPlanPicker: _openPlanPicker,
                            planManagerOpen: _planManagerOpen,
                            onPlanManager: _openPlanManager,
                            settingsOpen: _settingsOpen,
                            onSettings: _toggleSettings,
                            maximized: _maximized,
                            onToggleMaximize: _toggleMaximize,
                            onClose: () => onWindowClose(),
                            onMinimize: () => windowManager.minimize(),
                          ),
                          Expanded(child: _body()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 卡片之外的 18px 灰紫地面也能拖窗口。四条边带只盖这一圈，
            // 不碰卡片内部的点击和 L2 环形拖拽手柄。
            ..._edgeDragBands(),
            // 设置浮层放最上层。打开时透明遮罩会盖住这一圈拖动带，
            // 窗口不跟着鼠标走，免得点面板时把窗口拖跑；收起即恢复。
            if (_settingsOpen)
              SettingsLayer(
                theme: Palette.theme,
                onThemeChanged: _setTheme,
                floatEnabled: _floatEnabled,
                onFloatChanged: () => unawaited(_toggleFloat()),
                openAtLogin: _openAtLogin,
                onAutostartChanged: () => unawaited(_toggleAutostart()),
                onManagePlans: _openPlanManager,
                onClose: _closeSettings,
              ),
            if (_planPickerOpen)
              PopoverLayer(
                width: 300,
                onClose: _closeLayers,
                child: PlanPickerPanel(
                  plans: _data?.plans ?? const <Plan>[],
                  currentPlanId: _data?.forDate(_now).planId ?? '',
                  currentSource: _data?.forDate(_now).source ?? '—',
                  autoPlanName: _autoPlanName(TimeMath.dateKey(_now)),
                  overriddenAt:
                      _data?.daySnapshots[TimeMath.dateKey(_now)]?.overriddenAt,
                  onSelect: (id) => _assignDay(TimeMath.dateKey(_now), id),
                  onClose: _closeLayers,
                ),
              ),
            if (_planManagerOpen && _data != null)
              PlanManagerLayer(
                data: _data!,
                now: _now,
                onPlansChanged: _updatePlans,
                onEditBlocks: _editBlocksOf,
                onClose: _closeLayers,
              ),
            if (_dayAssignDate != null && _data != null)
              PopoverLayer(
                width: 300,
                top: 120,
                onClose: _closeLayers,
                child: DayAssignPanel(
                  date: _dayAssignDate!,
                  plans: _data!.plans,
                  assignedPlanId:
                      _data!.dayOverrides[TimeMath.dateKey(_dayAssignDate!)],
                  autoPlanName: _autoPlanNameFor(_dayAssignDate!),
                  onSelect: (id) =>
                      _assignDay(TimeMath.dateKey(_dayAssignDate!), id),
                  onClose: _closeLayers,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 外围 18px 的四条拖动带，拼成一个环，四角不重叠。
  /// 只覆盖卡片外的地面，卡片内的按钮、分段控件和 L2 环上手柄照常工作。
  List<Widget> _edgeDragBands() {
    Widget band() => WindowDragArea(onToggleMaximize: _toggleMaximize);
    const p = Spacing.pad;
    return [
      Positioned(top: 0, left: 0, right: 0, height: p, child: band()),
      Positioned(bottom: 0, left: 0, right: 0, height: p, child: band()),
      Positioned(top: p, bottom: p, left: 0, width: p, child: band()),
      Positioned(top: p, bottom: p, right: 0, width: p, child: band()),
    ];
  }

  String get _dateLabel {
    const names = ['日', '一', '二', '三', '四', '五', '六'];
    return '${_now.month}月${_now.day}日 周${names[_now.weekday % 7]}';
  }

  /// 顶栏「今天：X（来源）」。判定一律走 forDate，不再读旧规则镜像。
  String get _planLabel {
    final data = _data;
    if (data == null) return '—';
    return data.forDate(_now).label;
  }

  /// 改判浮层里「按规则本应是哪张表」。
  String? _autoPlanName(String key) {
    final data = _data;
    if (data == null) return null;
    final id = data.daySnapshots[key]?.autoPlanId;
    if (id == null) return null;
    for (final p in data.plans) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  /// 日历指派浮层里，临时去掉该天例外后算出的表名。
  String _autoPlanNameFor(DateTime date) {
    final data = _data;
    if (data == null) return '—';
    return data
        .withDayOverride(TimeMath.dateKey(date), null)
        .forDate(date)
        .planName;
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Center(
        child: AppCard(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('数据打不开', style: TypeScale.title),
              const SizedBox(height: 8),
              Text(_readable(error), style: TypeScale.bodyMuted),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _reload, child: const Text('重试')),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_view) {
      AppView.dashboard => DashboardScreen(
        data: data,
        now: _now,
        onOverride: _overrideCurrent,
      ),
      AppView.edit => EditScreen(
        data: data,
        now: _now,
        planIdOverride: _editPlanId,
        onChanged: _commit,
        onOverride: _overrideCurrent,
        onRestoreDefault: () {
          final current = _data;
          if (current != null) {
            _commit(current.restoredDefaults(), saveNow: true);
          }
        },
      ),
      AppView.summary => SummaryScreen(
        data: data,
        now: _now,
        onDayTap: _openDayAssign,
      ),
    };
  }

  String _readable(Object error) {
    if (error is AppDataException) return error.message;
    return '读取本地数据失败：$error';
  }
}
