import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/day_block.dart';
import '../../domain/schedule_editor.dart';
import '../../domain/time_math.dart';
import 'ring_geometry.dart';

/// 环上拖拽的三种意图。边界手柄优先于整块平移。
enum _DragMode { end, start, move }

/// 双环：内圈 00–12，外圈 12–24。
///
/// 这是整个产品的签名元素，所有其他界面都是它的注脚。
/// 逐块画弧而不是整圆加遮罩 —— 否则跨零点那段（23:00–07:00）会整段消失。
///
/// **环上不写任何文字**，所以鼠标悬停是唯一的"这块是什么"入口：
/// 指到哪一块，其余压暗、那一块保持全亮，并跟出一个说明条。
class DualRing extends StatefulWidget {
  const DualRing({
    super.key,
    required this.blocks,
    required this.nowMinute,
    this.diameter = 380,
    this.showCenter = false,
    this.centerTitle = '',
    this.centerSub = '',
    this.centerSubInteractive = false,
    this.editing = false,
    this.onBlocksChanged,
    this.selectedIndex,
    this.onSelect,
  });

  final List<DayBlock> blocks;

  /// 当前分钟数（0–1439）。白色指针和"当前块"的高亮都靠它。
  final int nowMinute;

  final double diameter;

  /// 是否在圆心画「已安排 / 空档」。悬浮窗单圈不用它。
  final bool showCenter;
  final String centerTitle;
  final String centerSub;

  /// 「空档 xx」这行是否可悬停。当天没有空档时（显示「已排满」）传 false，
  /// 免得鼠标落在圆心上什么都不会发生，却还是把手型光标亮起来。
  final bool centerSubInteractive;

  /// L2 才打开。L1 的环只读 —— 看板上出现拖拽手柄会破坏「三秒读完」。
  final bool editing;

  /// 拖拽/编辑后的新块列表。null = 只读（与 `editing` 成对出现）。
  final ValueChanged<List<DayBlock>>? onBlocksChanged;

  /// 被选中的块下标，画白色描边，与清单、时间轴联动。
  final int? selectedIndex;
  final ValueChanged<int?>? onSelect;

  @override
  State<DualRing> createState() => _DualRingState();
}

class _DualRingState extends State<DualRing> {
  /// 鼠标指着的那一块。null = 没指着环，或者指着空档（看 `_onRing`）。
  DayBlock? _hovered;

  /// 鼠标是否真的落在环上（含空档）。用来区分"空档"和"没碰到"。
  bool _onRing = false;

  /// 鼠标是否悬在圆心「空档 xx」上。悬停时把环上所有未安排弧一起提亮，
  /// 让用户不用逐段找就能看出哪几段是空的（深色主题下尤其有用）。
  bool _centerHover = false;

  /// 提示条跟着鼠标走，但位置在 widget 内夹紧，不让它飘出环外。
  Offset? _anchor;

  /// 悬停位置对应的分钟数，空档时用来算区间。
  int _hoverMinute = 0;

  // ---------- 环上拖拽 ----------
  //
  // 关键：**拖拽全程用按下那一帧的 blocks 快照算**，不用 widget.blocks。
  // 否则每拖 1px 上层就 setState 一次，下一帧的"原始位置"已经被上一次
  // 改过了，delta 会累积成越拖越快的漂移 —— 而且不会报错。
  List<DayBlock>? _dragBase;
  int _dragIndex = -1;
  DayBlock? _dragBlock;
  _DragMode? _dragMode;
  double _dragStartRingMinute = 0;
  String? _dragBadge;

  /// 真正按下的位置。
  ///
  /// `onPanStart` 要等指针走够触摸阈值（18px）才回调，那时给的 localPosition
  /// 已经是拖拽**中途**的点。拿它做命中检测会把「拖结束手柄」误判成「整块平移」，
  /// 而且 delta 少了开头一截，拖 30 分钟只动 7 分钟。所以必须自己记按下点。
  Offset? _pointerDown;

  /// 指针落在某一圈上的「圈内分钟数」(0–720)。
  /// 两圈共用 0°=12 点，所以这里不区分内外圈，只要连续量做差。
  double _ringMinute(Offset local) {
    final scale = widget.diameter / RingGeometry.canvasSize;
    final dx = local.dx / scale - RingGeometry.center;
    final dy = local.dy / scale - RingGeometry.center;
    var deg = math.atan2(dy, dx) * 180 / math.pi + 90;
    if (deg < 0) deg += 360;
    return deg / 360 * 720;
  }

  double _angularDistance(double a, double b) {
    final d = (a - b).abs();
    return math.min(d, 720 - d);
  }

  void _startDrag(Offset fallback) {
    final local = _pointerDown ?? fallback;
    final hit = RingGeometry.hitTest(local, widget.diameter, widget.blocks);
    final block = hit?.block;
    if (!widget.editing ||
        hit == null ||
        block == null ||
        widget.onBlocksChanged == null) {
      return;
    }
    final index = widget.blocks.indexWhere((b) => b.start == block.start);
    if (index < 0) return;

    final side = hit.minute < 720 ? RingSide.inner : RingSide.outer;
    final pxPerMinute = 2 * math.pi * RingGeometry.rMid(side) / 720;
    final m = _ringMinute(local);

    // 结束边界显示在环上的分钟数：1860（次日 07:00）取模后是 420，落内圈。
    final endMod = block.end % TimeMath.minutesPerDay;
    final startMod = block.start % 720;
    final endOnSide = (endMod < 720 ? RingSide.inner : RingSide.outer) == side;
    final startOnSide =
        (block.start < 720 ? RingSide.inner : RingSide.outer) == side;

    final endPx = _angularDistance(m, endMod % 720) * pxPerMinute;
    final startPx = _angularDistance(m, startMod.toDouble()) * pxPerMinute;

    final mode = (endOnSide && endPx < 11)
        ? _DragMode.end
        : (startOnSide && startPx < 11)
        ? _DragMode.start
        : _DragMode.move;

    setState(() {
      _dragBase = List.of(widget.blocks);
      _dragIndex = index;
      _dragBlock = block;
      _dragMode = mode;
      _dragStartRingMinute = m;
      _dragBadge = _badgeOf(block);
    });
    widget.onSelect?.call(index);
  }

  void _updateDrag(Offset local) {
    final base = _dragBase;
    final block = _dragBlock;
    final mode = _dragMode;
    if (base == null ||
        block == null ||
        mode == null ||
        _dragIndex >= base.length) {
      return;
    }

    // 跨 12 点接缝时圈内分钟数会从 719 跳到 0，把差值折回 ±360。
    var delta = _ringMinute(local) - _dragStartRingMinute;
    if (delta > 360) delta -= 720;
    if (delta < -360) delta += 720;

    final DayBlock next = switch (mode) {
      _DragMode.end => ScheduleEditor.withEnd(
        base,
        _dragIndex,
        (block.end + delta).round(),
      ),
      _DragMode.start => ScheduleEditor.withStart(
        base,
        _dragIndex,
        (block.start + delta).round(),
      ),
      _DragMode.move => ScheduleEditor.movedTo(
        base,
        _dragIndex,
        (block.start + delta).round(),
      ),
    };
    final out = ScheduleEditor.replaceAt(base, _dragIndex, next);
    widget.onBlocksChanged!(out);
    final preview = _badgeOf(next);
    if (preview != _dragBadge) setState(() => _dragBadge = preview);
  }

  void _endDrag() {
    if (_dragMode == null) return;
    setState(() {
      _dragBase = null;
      _dragIndex = -1;
      _dragBlock = null;
      _dragMode = null;
      _dragBadge = null;
    });
  }

  String _badgeOf(DayBlock b) =>
      '${TimeMath.formatHm(b.start)} – ${TimeMath.formatHm(b.end)}'
      '${b.crossesMidnight ? ' 次日' : ''} · '
      '${TimeMath.formatDurationCn(b.duration)}';

  void _tapSelect(Offset local) {
    if (!widget.editing || widget.onSelect == null) return;
    final hit = RingGeometry.hitTest(local, widget.diameter, widget.blocks);
    final block = hit?.block;
    if (block == null) return;
    final index = widget.blocks.indexWhere((b) => b.start == block.start);
    if (index < 0) return;
    widget.onSelect!(widget.selectedIndex == index ? null : index);
  }

  void _handleHover(PointerHoverEvent event) {
    final hit = RingGeometry.hitTest(
      event.localPosition,
      widget.diameter,
      widget.blocks,
    );

    if (hit == null) {
      _clearHover();
      return;
    }

    final anchor = event.localPosition;
    final sameTarget = _onRing && hit.block?.start == _hovered?.start;
    final moved = _anchor == null || (anchor - _anchor!).distance > 2;
    // 鼠标每移动 1px 就重建整棵树太浪费：目标没换、位置没走出 2px 就不刷。
    if (sameTarget && !moved) return;

    setState(() {
      _hovered = hit.block;
      _onRing = true;
      _anchor = anchor;
      _hoverMinute = hit.minute;
    });
  }

  void _clearHover() {
    if (_anchor == null) return;
    setState(() {
      _hovered = null;
      _onRing = false;
      _anchor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final selectedStart =
        (widget.selectedIndex != null &&
            widget.selectedIndex! >= 0 &&
            widget.selectedIndex! < widget.blocks.length)
        ? widget.blocks[widget.selectedIndex!].start
        : null;

    Widget ring = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(d, d),
          painter: DualRingPainter(
            blocks: widget.blocks,
            nowMinute: widget.nowMinute,
            hoveredStart: _hovered?.start,
            selectedStart: selectedStart,
            editing: widget.editing,
            // 环上的刻度数字跟着应用字体走。画家不能自己 new 一个
            // TextStyle —— 那样会绕开主题，在测试环境里直接退化成方框。
            fontFamily: DefaultTextStyle.of(context).style.fontFamily,
            // 主题切换时 blocks/now 都没变，不带这个标记画家会拒绝重画，
            // 于是深色配色会一直留在浅色窗口里。
            isLight: Palette.isLight,
            // 悬停圆心「空档 xx」时，把环上所有未安排弧一起提亮。
            highlightGaps: _centerHover,
          ),
        ),
        if (widget.showCenter)
          _CenterReadout(
            title: widget.centerTitle,
            sub: widget.centerSub,
            scale: d / RingGeometry.canvasSize,
            interactive: widget.centerSubInteractive,
            highlighted: _centerHover,
            onHoverChanged: (v) {
              if (_centerHover == v) return;
              setState(() => _centerHover = v);
            },
          ),
        if (_dragBadge != null)
          Positioned(
            top: 2,
            child: IgnorePointer(child: _DragBadge(text: _dragBadge!)),
          ),
        if (_onRing && _anchor != null && _dragMode == null)
          _tooltip(blocks: widget.blocks),
      ],
    );

    if (widget.editing) {
      ring = Listener(
        onPointerDown: (e) => _pointerDown = e.localPosition,
        onPointerUp: (_) => _pointerDown = null,
        onPointerCancel: (_) => _pointerDown = null,
        child: GestureDetector(
          // CustomPaint 默认不参与命中测试，deferToChild 会让整块区域收不到拖拽。
          // 环是 d×d 的方形，opaque 正好把这一整块变成可拖区。
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _startDrag(d.localPosition),
          onPanUpdate: (d) => _updateDrag(d.localPosition),
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _endDrag,
          onTapUp: (d) => _tapSelect(d.localPosition),
          child: ring,
        ),
      );
    }

    return SizedBox(
      width: d,
      height: d,
      child: MouseRegion(
        onHover: _handleHover,
        onExit: (_) => _clearHover(),
        child: ring,
      ),
    );
  }

  Widget _tooltip({required List<DayBlock> blocks}) {
    final anchor = _anchor!;
    final d = widget.diameter;

    // 固定宽高预算，好算夹紧位置。环直径 380，所以 220 宽有地方放。
    const w = 224.0;
    const h = 78.0;

    var x = anchor.dx + 18;
    var y = anchor.dy + 18;
    // 右边/下边不够就翻到鼠标左上方，而不是硬塞在边缘被切掉。
    if (x + w > d - 4) x = anchor.dx - w - 18;
    if (y + h > d - 4) y = anchor.dy - h - 18;
    x = x.clamp(4.0, math.max(4.0, d - w - 4));
    y = y.clamp(4.0, math.max(4.0, d - h - 4));

    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: _RingTooltip(
          width: w,
          minute: _hoverMinute,
          blocks: blocks,
          nowMinute: widget.nowMinute,
        ),
      ),
    );
  }
}

/// 拖拽时贴在环顶的时间提示。吸附后的数值，不是鼠标原始位置。
class _DragBadge extends StatelessWidget {
  const _DragBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: Palette.text.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TypeScale.label.copyWith(
          color: Palette.text,
          fontFeatures: TypeScale.tabular,
        ),
      ),
    );
  }
}

/// 悬停说明条。宽高固定，保证它在环上出现时不会因为文字长短跳来跳去。
class _RingTooltip extends StatelessWidget {
  const _RingTooltip({
    required this.width,
    required this.minute,
    required this.blocks,
    required this.nowMinute,
  });

  final double width;
  final int minute;
  final List<DayBlock> blocks;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    // 不用悬停时抓到的那个对象，而是按分钟重新查一遍：
    // 走时钟每 20 秒重建 blocks，抓的对象可能已经过期。
    final b = TimeMath.blockAt(blocks, minute);
    final isNow =
        b != null && TimeMath.blockAt(blocks, nowMinute)?.start == b.start;

    final color = b == null ? Palette.unplanned : Palette.of(b.category);
    final title = b?.name ?? '未安排';
    final meta = b == null ? _gapMeta() : _blockMeta(b);

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(Radii.well),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (isNow) ...[
                const SizedBox(width: 6),
                Text(
                  '现在',
                  style: TypeScale.labelSmall.copyWith(color: Palette.text),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TypeScale.labelSmall.copyWith(
              color: Palette.muted,
              fontFeatures: TypeScale.tabular,
            ),
          ),
        ],
      ),
    );
  }

  String _blockMeta(DayBlock b) {
    final span = '${TimeMath.formatHm(b.start)} – ${TimeMath.formatHm(b.end)}';
    final span2 = b.end > TimeMath.minutesPerDay ? '$span 次日' : span;
    // 名字和分类同名时不重复写一遍（"工作 · 工作"看着像 bug）
    final cat = b.name == b.category.label ? '' : ' · ${b.category.label}';
    return '$span2$cat · ${TimeMath.formatDurationCn(b.duration)}';
  }

  /// 空档要知道"空到什么时候"才有用 —— 光说"这段空着"等于没说。
  String _gapMeta() {
    for (final g in TimeMath.gaps(blocks)) {
      if (minute >= g.start && minute < g.end) {
        return '${TimeMath.formatHm(g.start)} – ${TimeMath.formatHm(g.end)} · '
            '空 ${TimeMath.formatDurationCn(g.end - g.start)}';
      }
    }
    return '这段时间空着';
  }
}

class _CenterReadout extends StatelessWidget {
  const _CenterReadout({
    required this.title,
    required this.sub,
    required this.scale,
    required this.interactive,
    required this.highlighted,
    required this.onHoverChanged,
  });

  final String title;
  final String sub;
  final double scale;
  final bool interactive;
  final bool highlighted;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    // 中心留白半径 < 52（画布单位），所以这里压到 100×100 以内
    final box = 104 * scale;
    final readout = SizedBox(
      width: box,
      height: box,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // UI 稿 v2：中心是「24h / 已安排 / 已排满」，主数字在上。
          Text(
            title,
            style: TextStyle(
              fontSize: 25 * scale,
              height: 1.12,
              fontWeight: FontWeight.w600,
              color: Palette.text,
              fontFeatures: TypeScale.tabular,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '已安排',
            style: TypeScale.labelSmall.copyWith(
              fontSize: 11 * scale,
              color: Palette.faint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: TypeScale.labelSmall.copyWith(
              fontSize: 10 * scale,
              // 可交互时比 ghost 亮一档，暗示"这行能悬停"；
              // 悬停中再提到主文字色并加下划线，和环上高亮对上。
              color: highlighted
                  ? Palette.text
                  : (interactive ? Palette.muted : Palette.ghost),
              decoration: highlighted ? TextDecoration.underline : null,
            ),
          ),
        ],
      ),
    );

    if (!interactive) return readout;
    // opaque: true 让整个 104×104 都能接住鼠标，不必精确指到那行小字。
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: readout,
    );
  }
}

class DualRingPainter extends CustomPainter {
  DualRingPainter({
    required this.blocks,
    required this.nowMinute,
    this.fontFamily,
    this.hoveredStart,
    this.selectedStart,
    this.editing = false,
    this.isLight = false,
    this.highlightGaps = false,
  });

  /// 刻度数字用的字体族（来自主题）。null 时交给引擎默认。
  final String? fontFamily;

  final List<DayBlock> blocks;
  final int nowMinute;

  /// 鼠标指着的那一块的起点分钟数。null = 没有悬停。
  ///
  /// 按起点匹配而不是按对象身份匹配：走时钟每 20 秒会重建一次 blocks，
  /// 存对象引用会在下一次重建后失配，高亮莫名消失。
  final int? hoveredStart;

  /// 选中的块起点。与清单、时间轴共用同一个下标换算出来的起点。
  final int? selectedStart;

  /// 编辑态才画拖拽手柄。
  final bool editing;

  /// 主题标记。颜色走的是全局令牌而不是画家参数，所以必须把它带进
  /// shouldRepaint —— 否则切主题时画家会认为「什么都没变」而拒绝重画，
  /// 深色配色会一直留在浅色窗口里。
  final bool isLight;

  /// 悬停圆心「空档 xx」时，把环上所有未安排弧提亮并描边。
  /// 只改明度和纹理强度，不引入第八个分类色。
  final bool highlightGaps;

  /// 色块之间的缝 = 窗口底色，所以看起来是画布透出来，不是一道黑线。
  /// 不能写 const：主题切换后它要跟着变。
  Color get _seam => Palette.seam;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / RingGeometry.canvasSize;
    canvas.save();
    canvas.scale(scale);

    final gaps = TimeMath.gaps(blocks);

    _paintGapFills(canvas, gaps);
    _paintHatch(canvas, gaps);
    _paintBlocks(canvas);
    _paintSeams(canvas);
    _paintHighlight(canvas);
    _paintGapOutline(canvas, gaps);
    _paintEditHandles(canvas);
    _paintNoonSeam(canvas);
    _paintNowPointer(canvas);

    canvas.restore();
  }

  // ---------- 空档 ----------

  void _paintGapFills(Canvas canvas, List<MinuteRange> gaps) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      // control 在深色下比 track 亮、浅色下比 track 实，两套主题都是
      // 「提亮一档」而不是换一个颜色。
      ..color = highlightGaps ? Palette.control : Palette.unplanned;

    for (final g in gaps) {
      for (final p in _splitToRings(g.start, g.end)) {
        _drawArc(
          canvas,
          p.side,
          p.from,
          p.to,
          paint,
          RingGeometry.r1(p.side) - RingGeometry.r0(p.side),
        );
      }
    }
  }

  /// 空档的纹理是**径向细线**，不是斜纹，也不是斜向渐变。
  /// 用纹理而不是第八个颜色，是因为它表达的是"这里空着"，语义和"某个分类"不同。
  void _paintHatch(Canvas canvas, List<MinuteRange> gaps) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlightGaps ? 1.3 : 1
      ..strokeCap = StrokeCap.butt
      ..color = highlightGaps
          ? Palette.muted.withValues(alpha: 0.9)
          : Palette.unplannedHatch;

    for (final g in gaps) {
      for (final p in _splitToRings(g.start, g.end)) {
        final mid = RingGeometry.rMid(p.side);
        final arcPx = (p.to - p.from) / 720 * 2 * math.pi * mid;
        final n = math.max(2, (arcPx / 5.5).round());
        for (var i = 0; i <= n; i++) {
          final t = p.from + (p.to - p.from) * i / n;
          canvas.drawLine(
            RingGeometry.polar(RingGeometry.r0(p.side) + 1, t),
            RingGeometry.polar(RingGeometry.r1(p.side) - 1, t),
            paint,
          );
        }
      }
    }
  }

  /// 悬停圆心「空档 xx」时，给每一段空档弧描一圈中性亮边，
  /// 直接回答「空的是哪几段」。
  ///
  /// 用 `Palette.hl`（深色纯白 / 浅色深灰蓝）加透明度，不用分类色 ——
  /// 未安排依然不是第八个颜色，只是被"点亮"了。
  void _paintGapOutline(Canvas canvas, List<MinuteRange> gaps) {
    if (!highlightGaps) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.butt
      ..color = Palette.hl.withValues(alpha: Palette.isLight ? 0.62 : 0.78);
    const center = Offset(RingGeometry.center, RingGeometry.center);

    for (final g in gaps) {
      for (final p in _splitToRings(g.start, g.end)) {
        final r0 = RingGeometry.r0(p.side) + 0.8;
        final r1 = RingGeometry.r1(p.side) - 0.8;
        final arc = RingGeometry.arcOf(p.side, p.from, p.to);

        // 先铺一层很淡的中性柔光，把整段空档从深色底上「托」起来。
        // 只有细描边的话，深色主题下仍要眯着眼找；柔光让它一眼就跳出来。
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r1 - r0 + 3
          ..strokeCap = StrokeCap.butt
          ..color = Palette.hl.withValues(alpha: Palette.isLight ? 0.14 : 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: RingGeometry.rMid(p.side)),
          arc.start,
          arc.sweep,
          false,
          glow,
        );

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r0),
          arc.start,
          arc.sweep,
          false,
          paint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r1),
          arc.start,
          arc.sweep,
          false,
          paint,
        );
        for (final t in [p.from, p.to]) {
          canvas.drawLine(
            RingGeometry.polar(r0, t.toDouble()),
            RingGeometry.polar(r1, t.toDouble()),
            paint,
          );
        }
      }
    }
  }

  // ---------- 数据段 ----------

  void _paintBlocks(Canvas canvas) {
    final focus = hoveredStart ?? selectedStart;
    // 上一版把「非当前块」常年压到 0.75，整套七色因此发灰 —— 用户明确
    // 反馈过「太灰暗」。UI 稿 v2 里色块一律满色，只有编辑态明确指向
    // 某一块时，其余才退到 --dim。
    final dimOthers = editing && focus != null;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    for (final b in blocks) {
      final alpha = (!dimOthers || b.start == focus) ? 1.0 : Palette.dim;
      for (final piece in b.ringPieces()) {
        final width = RingGeometry.r1(piece.side) - RingGeometry.r0(piece.side);
        paint.color = Palette.of(b.category).withValues(alpha: alpha);
        _drawArc(canvas, piece.side, piece.from, piece.to, paint, width);
      }
    }
  }

  /// 类别分界处的一道 1.6px 硬缝。不给每块描边 —— 那会在块与块之间留深色沟。
  void _paintSeams(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.butt
      ..color = _seam;

    for (final side in RingSide.values) {
      final pieces = <({int from, int to, int cat})>[];
      for (final b in blocks) {
        for (final p in b.ringPieces()) {
          if (p.side != side) continue;
          pieces.add((from: p.from, to: p.to, cat: b.category.index));
        }
      }
      pieces.sort((a, b) => a.from.compareTo(b.from));
      for (var i = 0; i < pieces.length - 1; i++) {
        if (pieces[i].cat == pieces[i + 1].cat) continue;
        final t = pieces[i].to.toDouble();
        canvas.drawLine(
          RingGeometry.polar(RingGeometry.r0(side), t),
          RingGeometry.polar(RingGeometry.r1(side), t),
          paint,
        );
      }
    }
  }

  /// 高亮块：用**分类色自己的强调版**描边，外加一圈同色柔光。
  ///
  /// UI 稿 v2 明确不要黑白中性框 —— 那会把「这块亮着」读成「这块被套住了」。
  /// 目标优先级：鼠标悬停 > 清单选中 > 当前时刻所在块。
  /// 跨零点被拆成两半的块两半都描，和它占了两段弧的事实一致。
  void _paintHighlight(Canvas canvas) {
    final nowStart = TimeMath.blockAt(blocks, nowMinute)?.start;
    final target = hoveredStart ?? selectedStart ?? nowStart;
    if (target == null) return;

    DayBlock? hit;
    for (final b in blocks) {
      if (b.start == target) {
        hit = b;
        break;
      }
    }
    if (hit == null) return;

    final base = Palette.of(hit.category);
    final edge = Palette.hiStroke(base);

    for (final p in hit.ringPieces()) {
      final r0 = RingGeometry.r0(p.side);
      final r1 = RingGeometry.r1(p.side);

      // 柔光：沿弧铺一层模糊的同色带，浅色底靠它把块「托」起来。
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r1 - r0 + 2
        ..strokeCap = StrokeCap.butt
        ..color = Palette.hiShadow(base)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
      _strokeArcAt(canvas, p, (r0 + r1) / 2, glow);

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Palette.isLight ? 2.1 : 1.9
        ..strokeCap = StrokeCap.butt
        ..color = edge;
      _strokeArcAt(canvas, p, r0 + 1.2, stroke);
      _strokeArcAt(canvas, p, r1 - 1.2, stroke);
      for (final t in [p.from, p.to]) {
        canvas.drawLine(
          RingGeometry.polar(r0 + 1.2, t.toDouble()),
          RingGeometry.polar(r1 - 1.2, t.toDouble()),
          stroke,
        );
      }
    }
  }

  void _strokeArcAt(Canvas canvas, RingPiece p, double radius, Paint paint) {
    final arc = RingGeometry.arcOf(p.side, p.from, p.to);
    canvas.drawArc(
      Rect.fromCircle(
        center: const Offset(RingGeometry.center, RingGeometry.center),
        radius: radius,
      ),
      arc.start,
      arc.sweep,
      false,
      paint,
    );
  }

  /// 编辑态：鼠标指着的块，在开始/结束边界各画一个同色强调圆点，
  /// 提示"这两个点能拖"。圆点落在**对应那一圈**上 —— 跨零点块的
  /// 结束边界在凌晨的内圈，不在 23 点的外圈。
  void _paintEditHandles(Canvas canvas) {
    if (!editing || hoveredStart == null) return;
    DayBlock? target;
    for (final b in blocks) {
      if (b.start == hoveredStart) {
        target = b;
        break;
      }
    }
    if (target == null) return;

    final bounds = <({double minute, RingSide side})>[
      (
        minute: target.start.toDouble(),
        side: target.start < 720 ? RingSide.inner : RingSide.outer,
      ),
      (
        minute: (target.end % TimeMath.minutesPerDay).toDouble(),
        side: (target.end % TimeMath.minutesPerDay) < 720
            ? RingSide.inner
            : RingSide.outer,
      ),
    ];

    final dot = Palette.hiStroke(Palette.of(target.category));
    for (final b in bounds) {
      final p = RingGeometry.polar(RingGeometry.rMid(b.side), b.minute);
      canvas.drawCircle(p, 4.2, Paint()..color = dot);
      canvas.drawCircle(
        p,
        4.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Palette.seam,
      );
    }
  }

  // ---------- 12 点接缝 ----------

  /// 只在 12 点方向留两道缝和一个 `12:00` 标签。
  /// UI 稿 v2 不在环上标 03/06/09/15/18/21 —— 24 小时双环本身已是尺度，
  /// 再写一圈数字会把彩色弧切成碎片。
  void _paintNoonSeam(Canvas canvas) {
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt
      ..color = _seam;
    // 外圈、内圈各跨自己那一段，中间的空隙留白给 12:00 文字。
    canvas.drawLine(
      RingGeometry.polarDeg(RingGeometry.outerR0, 0),
      RingGeometry.polarDeg(RingGeometry.outerR1, 0),
      seam,
    );
    canvas.drawLine(
      RingGeometry.polarDeg(RingGeometry.innerR0, 0),
      RingGeometry.polarDeg(RingGeometry.innerR1, 0),
      seam,
    );

    _label(
      canvas,
      '12:00',
      Offset(
        RingGeometry.center,
        RingGeometry.center + RingGeometry.labelTextDy,
      ),
      Palette.faint,
    );
  }

  void _paintNowPointer(Canvas canvas) {
    final side = nowMinute < 720 ? RingSide.inner : RingSide.outer;
    final r0 = RingGeometry.r0(side);
    final r1 = RingGeometry.r1(side);
    final m = nowMinute.toDouble();

    // 指针只跨环宽，不探进中心文字区，也不加圆点。
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = Palette.hl;
    canvas.drawLine(
      RingGeometry.polar(r0, m),
      RingGeometry.polar(r1, m),
      paint,
    );
  }

  // ---------- 工具 ----------

  void _drawArc(
    Canvas canvas,
    RingSide side,
    int from,
    int to,
    Paint paint,
    double width,
  ) {
    final arc = RingGeometry.arcOf(side, from, to);
    paint.strokeWidth = width;
    final rect = Rect.fromCircle(
      center: const Offset(RingGeometry.center, RingGeometry.center),
      radius: RingGeometry.rMid(side),
    );
    canvas.drawArc(rect, arc.start, arc.sweep, false, paint);
  }

  List<({RingSide side, int from, int to})> _splitToRings(int a, int c) {
    final out = <({RingSide side, int from, int to})>[];
    if (a < 720) {
      final e = math.min(c, 720);
      if (e > a) out.add((side: RingSide.inner, from: a, to: e));
    }
    if (c > 720) {
      final s = math.max(a, 720);
      if (c > s) out.add((side: RingSide.outer, from: s, to: c));
    }
    return out;
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    Color color, {
    double dy = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 9,
          height: 1,
          color: color,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      center - Offset(tp.width / 2, tp.height / 2) + Offset(0, dy),
    );
  }

  @override
  bool shouldRepaint(covariant DualRingPainter oldDelegate) =>
      oldDelegate.nowMinute != nowMinute ||
      oldDelegate.hoveredStart != hoveredStart ||
      oldDelegate.selectedStart != selectedStart ||
      oldDelegate.editing != editing ||
      oldDelegate.isLight != isLight ||
      oldDelegate.highlightGaps != highlightGaps ||
      !_sameBlocks(oldDelegate.blocks, blocks);

  bool _sameBlocks(List<DayBlock> a, List<DayBlock> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].category != b[i].category) {
        return false;
      }
    }
    return true;
  }
}
