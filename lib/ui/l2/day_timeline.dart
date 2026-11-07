import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/day_block.dart';
import '../../domain/schedule_editor.dart';
import '../../domain/time_math.dart';
import '../widgets/app_card.dart';

/// 编辑态里改块的统一回调。`saveNow` 在松手时置 true，拖拽过程中走防抖。
typedef BlocksChanged = void Function(List<DayBlock> next, {bool saveNow});

/// 一个块在 24 小时横条上占的一段。
///
/// 跨零点的块会占两段（左端 00:00 起、右端 23:00 起）。**两段的接缝在
/// 整条的最左/最右边缘，不能拖** —— 需求写得很明确：只许改外侧两个端点。
class _Piece {
  const _Piece({
    required this.blockIndex,
    required this.start,
    required this.end,
    required this.leftEdge,
    required this.rightEdge,
  });

  final int blockIndex;
  final int start;
  final int end;

  /// none = 接缝（不可拖），start/end = 这个边界对应块的哪个端点。
  final _Edge leftEdge;
  final _Edge rightEdge;
}

enum _Edge { none, start, end }

enum _DragMode { none, start, end, move }

class _Hit {
  const _Hit(this.piece, this.mode);

  final _Piece piece;
  final _DragMode mode;
}

/// 24 小时时间轴。和环形图共用**同一份 blocks**，没有第二份状态。
class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.blocks,
    required this.nowMinute,
    required this.selectedIndex,
    required this.onSelect,
    required this.onBlocksChanged,
    required this.onCreateRequest,
    this.onCategoryRequest,
    this.onDeleteRequest,
  });

  final List<DayBlock> blocks;
  final int nowMinute;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final BlocksChanged onBlocksChanged;

  /// 点在空档上：由上层弹分类快选，选完再调 createAt。
  final ValueChanged<int> onCreateRequest;

  /// 双击色块换分类 / 右键删除，都交回上层统一改数据。
  final ValueChanged<int>? onCategoryRequest;
  final ValueChanged<int>? onDeleteRequest;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  static const double _barHeight = 46;
  static const double _edgeSlop = 8;

  _DragMode _mode = _DragMode.none;
  int _dragIndex = -1;

  /// 拖拽浮层：吸附后的结束时刻 + 当前时长。
  ({int minute, int duration, double x})? _bubble;
  int _downMinute = 0;
  int _downStart = 0;

  List<_Piece> get _pieces {
    final out = <_Piece>[];
    for (var i = 0; i < widget.blocks.length; i++) {
      final b = widget.blocks[i];
      if (b.crossesMidnight) {
        out.add(
          _Piece(
            blockIndex: i,
            start: 0,
            end: b.end - TimeMath.minutesPerDay,
            leftEdge: _Edge.none,
            rightEdge: _Edge.end,
          ),
        );
        out.add(
          _Piece(
            blockIndex: i,
            start: b.start,
            end: TimeMath.minutesPerDay,
            leftEdge: _Edge.start,
            rightEdge: _Edge.none,
          ),
        );
      } else {
        out.add(
          _Piece(
            blockIndex: i,
            start: b.start,
            end: b.end,
            leftEdge: _Edge.start,
            rightEdge: _Edge.end,
          ),
        );
      }
    }
    return out;
  }

  double _minuteAt(double x, double width) =>
      (x / width * TimeMath.minutesPerDay).clamp(0, TimeMath.minutesPerDay - 1);

  _Hit? _hit(double x, double width, List<_Piece> pieces) {
    for (final p in pieces) {
      final x0 = p.start / TimeMath.minutesPerDay * width;
      final x1 = p.end / TimeMath.minutesPerDay * width;
      if (x < x0 - _edgeSlop || x > x1 + _edgeSlop) continue;

      final nearLeft = (x - x0).abs() <= _edgeSlop;
      final nearRight = (x - x1).abs() <= _edgeSlop;
      if (nearLeft && p.leftEdge != _Edge.none) {
        return _Hit(
          p,
          p.leftEdge == _Edge.start ? _DragMode.start : _DragMode.end,
        );
      }
      if (nearRight && p.rightEdge != _Edge.none) {
        return _Hit(
          p,
          p.rightEdge == _Edge.end ? _DragMode.end : _DragMode.start,
        );
      }
      if (x >= x0 && x <= x1) return _Hit(p, _DragMode.move);
    }
    return null;
  }

  void _startDrag(Offset local, double width) {
    final hit = _hit(local.dx, width, _pieces);
    if (hit == null) return;
    widget.onSelect(hit.piece.blockIndex);
    _mode = hit.mode;
    _dragIndex = hit.piece.blockIndex;
    _downMinute = _minuteAt(local.dx, width).round();
    _downStart = widget.blocks[_dragIndex].start;
  }

  void _updateDrag(Offset local, double width) {
    if (_mode == _DragMode.none || _dragIndex < 0) return;
    final blocks = widget.blocks;
    if (_dragIndex >= blocks.length) return;
    final t = blocks[_dragIndex];
    final minute = _minuteAt(local.dx, width).round();

    DayBlock next;
    switch (_mode) {
      case _DragMode.end:
        // 跨零点块的结束显示在左半段（00:00 起），存储上要加回一天。
        final wanted = t.crossesMidnight
            ? minute + TimeMath.minutesPerDay
            : minute;
        next = ScheduleEditor.withEnd(blocks, _dragIndex, wanted);
      case _DragMode.start:
        next = ScheduleEditor.withStart(blocks, _dragIndex, minute);
      case _DragMode.move:
        next = ScheduleEditor.movedTo(
          blocks,
          _dragIndex,
          _downStart + (minute - _downMinute),
        );
      case _DragMode.none:
        return;
    }

    if (next.start != t.start || next.end != t.end) {
      widget.onBlocksChanged(
        ScheduleEditor.replaceAt(blocks, _dragIndex, next),
      );
    }
    setState(() {
      _bubble = (
        minute: _mode == _DragMode.start ? next.start : next.end,
        duration: next.duration,
        x: local.dx,
      );
    });
  }

  void _endDrag() {
    if (_mode == _DragMode.none) return;
    // 松手时立刻落盘，不等防抖（需求：拖拽结束后自动保存）。
    widget.onBlocksChanged(widget.blocks, saveNow: true);
    setState(() {
      _mode = _DragMode.none;
      _dragIndex = -1;
      _bubble = null;
    });
  }

  void _tap(Offset local, double width) {
    final hit = _hit(local.dx, width, _pieces);
    if (hit != null) {
      widget.onSelect(
        widget.selectedIndex == hit.piece.blockIndex
            ? null
            : hit.piece.blockIndex,
      );
      return;
    }
    // 空档：开始时间由上层按"该段空隙起点"算，这里只交出点击时刻。
    widget.onCreateRequest(_minuteAt(local.dx, width).round());
  }

  void _doubleTap(Offset local, double width) {
    final hit = _hit(local.dx, width, _pieces);
    if (hit != null) widget.onCategoryRequest?.call(hit.piece.blockIndex);
  }

  void _secondaryTap(Offset local, double width) {
    final hit = _hit(local.dx, width, _pieces);
    if (hit != null) widget.onDeleteRequest?.call(hit.piece.blockIndex);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('24 小时', style: TypeScale.section),
              const SizedBox(width: 12),
              if (widget.selectedIndex != null &&
                  widget.selectedIndex! < widget.blocks.length)
                Text(
                  '选中：${widget.blocks[widget.selectedIndex!].name}',
                  style: TypeScale.labelSmall,
                )
              else
                Text('点空白新建 · 拖边界改时长 · 拖整块平移', style: TypeScale.labelSmall),
              const Spacer(),
              Text('双击色块换分类 · 右键删除', style: TypeScale.labelSmall),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: _barHeight + 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _tap(d.localPosition, w),
                        onDoubleTapDown: (d) => _doubleTap(d.localPosition, w),
                        onSecondaryTapUp: (d) =>
                            _secondaryTap(d.localPosition, w),
                        onPanStart: (d) => _startDrag(d.localPosition, w),
                        onPanUpdate: (d) => _updateDrag(d.localPosition, w),
                        onPanEnd: (_) => _endDrag(),
                        onPanCancel: _endDrag,
                        child: CustomPaint(
                          painter: _TimelinePainter(
                            blocks: widget.blocks,
                            pieces: _pieces,
                            nowMinute: widget.nowMinute,
                            selectedIndex: widget.selectedIndex,
                            dragMode: _mode,
                            // 画家不能自己 new 一个不带字体族的 TextStyle，
                            // 否则刻度数字在测试环境里会退化成实心方块。
                            fontFamily: DefaultTextStyle.of(context)
                                .style
                                .fontFamily,
                            isLight: Palette.isLight,
                          ),
                        ),
                      ),
                    ),
                    if (_bubble != null) _dragBubble(w),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _dragBubble(double width) {
    final b = _bubble!;
    final text = _mode == _DragMode.start
        ? '${TimeMath.formatHm(b.minute)} 开始 · ${TimeMath.formatDuration(b.duration)}'
        : '${TimeMath.formatHm(b.minute)} 结束 · ${TimeMath.formatDuration(b.duration)}';
    const bubbleW = 142.0;
    final x = (b.x - bubbleW / 2).clamp(0.0, width - bubbleW);
    return Positioned(
      left: x,
      top: -30,
      child: IgnorePointer(
        child: Container(
          width: bubbleW,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Palette.hl,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TypeScale.labelSmall.copyWith(
              color: Palette.app,
              fontWeight: FontWeight.w600,
              fontFeatures: TypeScale.tabular,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.blocks,
    required this.pieces,
    required this.nowMinute,
    required this.selectedIndex,
    required this.dragMode,
    this.fontFamily,
    this.isLight = false,
  });

  final List<DayBlock> blocks;
  final List<_Piece> pieces;
  final int nowMinute;
  final int? selectedIndex;
  final _DragMode dragMode;
  final String? fontFamily;

  /// 颜色走全局令牌，必须带进 shouldRepaint，否则切主题不重画。
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = _DayTimelineState._barHeight;
    double px(int m) => m / TimeMath.minutesPerDay * w;

    // 底：空档色 + 竖向细纹，和环上的空档是同一套语言。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Palette.unplanned,
    );
    final hatch = Paint()
      ..color = Palette.unplannedHatch.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (final g in TimeMath.gaps(blocks)) {
      final x0 = px(g.start);
      final x1 = px(g.end);
      for (var x = x0 + 5; x < x1; x += 6) {
        canvas.drawLine(Offset(x, 2), Offset(x, h - 2), hatch);
      }
    }

    // 色块。跨零点的两半同色，视觉上仍是同一块。
    for (final p in pieces) {
      final b = blocks[p.blockIndex];
      final x0 = px(p.start);
      final x1 = px(p.end);
      final alpha = p.blockIndex == selectedIndex ? 1.0 : 0.86;
      canvas.drawRect(
        Rect.fromLTWH(x0, 0, math.max(x1 - x0 - 1, 1), h),
        Paint()..color = Palette.of(b.category).withValues(alpha: alpha),
      );

      // 名称只在放得下的时候写，不硬塞。
      if (x1 - x0 > 52) {
        final tp = TextPainter(
          text: TextSpan(
            text: b.name,
            style: TextStyle(
              fontSize: 11,
              // 浅色主题的分类块是柔和的浅色，白字会糊掉；深色主题才用白字。
              color: Palette.blkText,
              height: 1,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: x1 - x0 - 10);
        tp.paint(
          canvas,
          Offset(x0 + (x1 - x0 - tp.width) / 2, (h - tp.height) / 2),
        );
      }
    }

    // 选中描边：取该块分类色的强调版，不用黑白中性框。
    if (selectedIndex != null && selectedIndex! < blocks.length) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Palette.hiStroke(Palette.of(blocks[selectedIndex!].category));
      for (final p in pieces.where((e) => e.blockIndex == selectedIndex)) {
        canvas.drawRect(
          Rect.fromLTWH(
            px(p.start) + 1,
            1,
            math.max(px(p.end) - px(p.start) - 2, 1),
            h - 2,
          ),
          paint,
        );
      }
    }

    // 三小时刻度。
    final tick = Paint()
      ..color = Palette.faint.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      fontSize: 10,
      color: Palette.faint,
      height: 1,
      fontFamily: fontFamily,
    );
    for (var hh = 0; hh <= 24; hh += 3) {
      final x = px(hh * 60).clamp(0.0, w);
      canvas.drawLine(Offset(x, h + 2), Offset(x, h + 6), tick);
      final text = '${hh.toString().padLeft(2, '0')}:00';
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((x - tp.width / 2).clamp(0.0, w - tp.width), h + 9),
      );
    }

    // 当前时刻。
    final nx = px(nowMinute);
    canvas.drawLine(
      Offset(nx, -4),
      Offset(nx, h + 4),
      Paint()
        ..color = Palette.hl
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.nowMinute != nowMinute ||
      old.selectedIndex != selectedIndex ||
      old.dragMode != dragMode ||
      old.fontFamily != fontFamily ||
      old.isLight != isLight ||
      !_sameBlocks(old.blocks, blocks);

  bool _sameBlocks(List<DayBlock> a, List<DayBlock> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].category != b[i].category ||
          a[i].name != b[i].name) {
        return false;
      }
    }
    return true;
  }
}
