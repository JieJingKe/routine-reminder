import 'dart:async';

import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';

/// 统一的「停留才算 hover」判定层。
///
/// v0.9.2：Jason 反馈「鼠标经过最小化 / 关闭等按钮时还是会有深色显示」。
/// 旧实现有两处毛病：
/// 1. `MouseRegion` 挂在 `GestureDetector(deferToChild)` 外面，命中区域其实
///    只有里面那个 15px 图标 / 文字的范围，比 26px 的按钮视觉边界小一圈，
///    所以「扫过按钮边缘」和「停在按钮上」得到的反馈是错位的；
/// 2. `AnimatedContainer(Motion.fast)` 让底色带 120ms 渐入渐出，鼠标横扫
///    三个窗口按钮会留下一串渐隐的深色残影，读起来就是「经过时闪一下」。
///
/// 这里把两件事一次修掉：
/// - 外层 `GestureDetector(opaque)` 让命中区域严格等于 builder 的尺寸，
///   按钮多大、hover 区域就多大，不会外溢到相邻按钮或拖动带上；
/// - 进入后延迟 [delay] 才置 hover，快速掠过完全不触发；离开立即恢复。
///   调用方把 `AnimatedContainer` 的 duration 设为 `Duration.zero`，
///   变色是瞬时的，没有任何渐变残影。
///
/// Tooltip 放最外层：它自带的 MouseRegion 若夹在 hover 探测层之间，
/// 600ms 后浮层出现会把按钮的 hover 状态打回去。
class HoverIntent extends StatefulWidget {
  const HoverIntent({
    super.key,
    required this.builder,
    this.onTap,
    this.tooltip,
    this.semanticLabel,
    this.cursor = SystemMouseCursors.click,
    this.delay = defaultDelay,
  });

  /// 停留多久才算「想用这个按钮」。110ms：横扫按钮组不会触发，
  /// 真正停上去几乎无感。
  static const Duration defaultDelay = Duration(milliseconds: 110);

  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final String? tooltip;
  final String? semanticLabel;
  final MouseCursor cursor;
  final Duration delay;

  @override
  State<HoverIntent> createState() => _HoverIntentState();
}

class _HoverIntentState extends State<HoverIntent> {
  bool _hovering = false;
  Timer? _delay;

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  void _enter(PointerEnterEvent _) {
    _delay?.cancel();
    _delay = Timer(widget.delay, () {
      if (mounted) setState(() => _hovering = true);
    });
  }

  void _exit(PointerExitEvent _) {
    _delay?.cancel();
    if (_hovering) setState(() => _hovering = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget core = MouseRegion(
      cursor: widget.cursor,
      onEnter: _enter,
      onExit: _exit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovering),
      ),
    );
    if (widget.semanticLabel != null) {
      core = Semantics(button: true, label: widget.semanticLabel, child: core);
    }
    if (widget.tooltip != null) {
      core = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: core,
      );
    }
    return core;
  }
}
