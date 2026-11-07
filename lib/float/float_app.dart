import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart'
    show GWL_EXSTYLE, GetWindowLongPtr, SetWindowLongPtr, WS_EX_TRANSPARENT;
import 'package:window_manager/window_manager.dart';

import '../design/tokens.dart';
import '../domain/day_block.dart';
import '../domain/time_math.dart';
import 'float_client.dart';
import 'float_geometry.dart';
import 'float_protocol.dart';
import 'float_text.dart';

class FloatApp extends StatefulWidget {
  const FloatApp({super.key, required this.port, required this.token});

  final int port;
  final String token;

  @override
  State<FloatApp> createState() => _FloatAppState();
}

class _FloatAppState extends State<FloatApp> with WindowListener {
  late final FloatClient _client = FloatClient(
    port: widget.port,
    token: widget.token,
    onSnapshot: _onSnapshot,
    onClosed: () => exit(0),
  );

  FloatSnapshot? _snapshot;
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _passThroughWatch;
  Timer? _moveDebounce;
  bool _polling = false;
  bool _pollErrorReported = false;

  /// 穿透状态。默认穿透，鼠标扫到圆上才恢复交互。
  bool _ignoring = true;

  bool _menuOpen = false;
  bool _dragging = false;
  Offset? _windowPosition;

  @override
  void initState() {
    super.initState();
    Palette.setTheme(
      PlatformDispatcher.instance.platformBrightness == Brightness.light
          ? AppTheme.light
          : AppTheme.dark,
    );
    windowManager.addListener(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_client.connect());
    unawaited(_setClickThrough(true));
    _passThroughWatch = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => unawaited(_tickPassThrough()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _passThroughWatch?.cancel();
    _moveDebounce?.cancel();
    windowManager.removeListener(this);
    _client.dispose();
    super.dispose();
  }

  /// 窗口左上角（逻辑像素）。读不到时退回上次的缓存，两边都没有就跳过这一跳。
  Future<Offset?> _currentOrigin() async {
    try {
      final position = await windowManager.getPosition();
      _windowPosition = position;
      return position;
    } on Object {
      return _windowPosition;
    }
  }

  void _onSnapshot(FloatSnapshot snapshot) {
    final nextTheme = AppTheme.fromKey(snapshot.theme);
    if (nextTheme != Palette.theme) Palette.setTheme(nextTheme);
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  /// 点击穿透只切 WS_EX_TRANSPARENT，不碰 WS_EX_LAYERED。
  /// window_manager.setIgnoreMouseEvents 会把 LAYERED 一起加/减，而分层窗口
  /// 的首帧在 DWM 里可能合成不出来 —— 表现是悬浮窗开机后"隐身"，鼠标扫过
  /// 触发一次样式变化才突然出现。只切 TRANSPARENT 实测照样穿透，画面正常。
  Future<void> _setClickThrough(bool ignore) async {
    final id = await windowManager.getId();
    final style = GetWindowLongPtr(id, GWL_EXSTYLE);
    SetWindowLongPtr(
      id,
      GWL_EXSTYLE,
      ignore ? style | WS_EX_TRANSPARENT : style & ~WS_EX_TRANSPARENT,
    );
  }

  /// 穿透状态下窗口收不到任何鼠标事件，唯一能知道"鼠标回来了"的办法
  /// 是自己读全局光标位置。120ms 一次，人感觉不到延迟，也不会明显吃 CPU。
  Future<void> _tickPassThrough() async {
    if (_polling || _dragging) return;
    _polling = true;
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      // 每跳都读一次真实位置：缓存在首帧很可能还没等到 setPosition
      // 生效，而它一旦错就会一直错（指针永远判定在外面）。
      final origin = await _currentOrigin();
      if (origin == null) return;
      final center =
          origin + const Offset(FloatGeometry.center, FloatGeometry.center);
      final inside = (cursor - center).distance <= FloatGeometry.center;

      if (_menuOpen && !inside) {
        setState(() => _menuOpen = false);
      }
      if (inside && _ignoring) {
        await _setClickThrough(false);
        _ignoring = false;
      } else if (!inside && !_ignoring && !_menuOpen) {
        await _setClickThrough(true);
        _ignoring = true;
      }
    } on Object catch (e) {
      // 光标位置拿不到时保持原状，不要因此把窗口锁死在穿透状态。
      // 只报一次：120ms 一次的错误会把日志刷爆。
      if (!_pollErrorReported) {
        _pollErrorReported = true;
        debugPrint('悬浮窗穿透检测失败：$e');
      }
    } finally {
      _polling = false;
    }
  }

  /// 拖到哪由系统接管（原生移动循环），这里只负责把落点记下来。
  /// 手写 pan + setPosition 会丢掉手势判定阈值之前的那几像素，
  /// 窗口起步总是慢半拍，而且每帧都要过一次 IPC。
  @override
  void onWindowMoved() {
    _dragging = false;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 300), _reportPosition);
  }

  Future<void> _reportPosition() async {
    try {
      final position = await windowManager.getPosition();
      _windowPosition = position;
      _client.reportPosition(position);
    } on Object {
      // 位置没读到就不上报，下次拖动会再试。
    }
  }

  void _startDrag() {
    if (_menuOpen) return;
    _dragging = true;
    unawaited(windowManager.startDragging());
  }

  void _openMenu() {
    if (_menuOpen) {
      setState(() => _menuOpen = false);
      return;
    }
    setState(() => _menuOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final minute = _now.hour * 60 + _now.minute;
    final center = snapshot == null
        ? const (title: '', sub: '')
        : floatCenterText(snapshot.blocks, minute);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Palette.themeData(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          cursor: _dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (_) => _openMenu(),
            onPanStart: (_) => _startDrag(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.app.withValues(alpha: 0.88),
                      border: Border.all(color: Palette.border),
                      boxShadow: Palette.windowShadow,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: FloatRingPainter(
                      blocks: snapshot?.blocks ?? const <DayBlock>[],
                      minute: minute,
                      isLight: Palette.isLight,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          center.title,
                          maxLines: 1,
                          style: TypeScale.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: Palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          center.sub,
                          maxLines: 1,
                          style: TypeScale.labelSmall.copyWith(
                            fontSize: 10,
                            color: Palette.muted,
                            fontFeatures: TypeScale.tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_menuOpen) _menu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _menuOpen = false),
        onSecondaryTapUp: (_) => setState(() => _menuOpen = false),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 126,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Palette.raised,
                borderRadius: BorderRadius.circular(Radii.smallCard),
                border: Border.all(color: Palette.border),
                boxShadow: Palette.windowShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuItem(
                    label: '打开主窗口',
                    onTap: () {
                      setState(() => _menuOpen = false);
                      _client.showMain();
                    },
                  ),
                  _MenuItem(
                    label: '隐藏悬浮窗',
                    onTap: () {
                      setState(() => _menuOpen = false);
                      _client.hideFloat();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TypeScale.label.copyWith(color: Palette.text),
          ),
        ),
      ),
    );
  }
}

class FloatRingPainter extends CustomPainter {
  FloatRingPainter({
    required this.blocks,
    required this.minute,
    required this.isLight,
  });

  final List<DayBlock> blocks;
  final int minute;

  /// 主题标记。颜色走全局令牌，画家必须把它带进 shouldRepaint，
  /// 否则切主题时画家会认为什么都没变而拒绝重画。
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = const Offset(FloatGeometry.center, FloatGeometry.center);
    final rect = Rect.fromCircle(center: center, radius: FloatGeometry.mid);

    canvas.drawCircle(
      center,
      FloatGeometry.mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = FloatGeometry.ringWidth
        ..color = Palette.track,
    );

    final currentStart = TimeMath.blockAt(blocks, minute)?.start;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = FloatGeometry.ringWidth
      ..strokeCap = StrokeCap.butt;

    for (final block in blocks) {
      final alpha = block.start == currentStart ? 1.0 : 0.92;
      paint.color = Palette.of(block.category).withValues(alpha: alpha);
      for (final piece in FloatGeometry.pieces(block.start, block.end)) {
        final startAngle = FloatGeometry.angleOf(piece.from);
        final sweep = (piece.to - piece.from) / 1440 * 2 * math.pi;
        canvas.drawArc(rect, startAngle, sweep, false, paint);
      }
    }

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Palette.faint;
    for (final m in const [0, 360, 720, 1080]) {
      final angle = FloatGeometry.angleOf(m);
      canvas.drawLine(
        FloatGeometry.polar(FloatGeometry.outer + 2, angle),
        FloatGeometry.polar(FloatGeometry.outer + 6, angle),
        tick,
      );
    }

    final angle = FloatGeometry.angleOf(minute);
    canvas.drawLine(
      FloatGeometry.polar(FloatGeometry.inner, angle),
      FloatGeometry.polar(FloatGeometry.outer + 3, angle),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = FloatGeometry.pointerWidth
        ..strokeCap = StrokeCap.round
        ..color = Palette.hl,
    );
  }

  @override
  bool shouldRepaint(FloatRingPainter old) =>
      old.minute != minute ||
      old.isLight != isLight ||
      !identical(old.blocks, blocks);
}
