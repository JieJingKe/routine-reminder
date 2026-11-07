import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/summary.dart';
import '../../design/tokens.dart';
import '../../domain/category.dart';
import '../../domain/day_block.dart';
import '../../domain/time_math.dart';

/// 偏差列沿用分类色，不引入红绿成败色。
/// UI 稿 v2 里「多出来」用学习色、「少了」用锻炼色，只是区分方向，不判好坏。
Color deviationColor(int diff) =>
    diff > 0 ? Palette.study : (diff < 0 ? Palette.exercise : Palette.faint);

/// 今天：计划 / 实际双环。
///
/// 和 L1 的双环**不是同一张图**：L1 的内外圈分别管 00–12 和 12–24；
/// 这里的两个圈都是完整 24 小时，外圈画计划、内圈画实际。
///
/// 两圈共用同一套角度，所以色段边界在半径方向天然对齐。完全不纠偏的日子
/// 内外圈看起来就是一整条环 —— **这是正确行为，不是渲染 bug**：
/// 重合本身就是「今天一分钟都没纠」这条信息。界面上另外写一行字点明它，
/// 免得用户以为图没画出来。
class CompareRing extends StatelessWidget {
  const CompareRing({super.key, required this.day, this.diameter = 320});

  final DaySummary day;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(diameter, diameter),
            painter: _ComparePainter(
              plan: day.plan,
              actual: day.actual,
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              isLight: Palette.isLight,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '计划 / 实际',
                style: TypeScale.labelSmall.copyWith(color: Palette.faint),
              ),
              const SizedBox(height: 4),
              Text(
                day.overrideCount == 0 ? '一致' : '纠偏 ${day.overrideCount} 段',
                style: TypeScale.section.copyWith(
                  color: day.overrideCount == 0 ? Palette.muted : Palette.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparePainter extends CustomPainter {
  const _ComparePainter({
    required this.plan,
    required this.actual,
    this.fontFamily,
    this.isLight = false,
  });

  final List<DayBlock> plan;
  final List<DayBlock> actual;
  final String? fontFamily;

  /// 颜色走全局令牌，必须带进 shouldRepaint，否则切主题不重画。
  final bool isLight;

  static const double _c = 170;
  static const double _planMid = 130;
  static const double _actualMid = 92;
  static const double _band = 34;

  static double _angle(double minute) =>
      minute / 1440 * 2 * math.pi - math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 340);

    for (final (blocks, mid) in [(plan, _planMid), (actual, _actualMid)]) {
      _base(canvas, mid);
      _segments(canvas, blocks, mid);
      _seams(canvas, blocks, mid);
    }
    _ticks(canvas);
    canvas.restore();
  }

  void _base(Canvas canvas, double mid) {
    canvas.drawCircle(
      const Offset(_c, _c),
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _band
        ..color = Palette.unplanned,
    );
  }

  void _segments(Canvas canvas, List<DayBlock> blocks, double mid) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _band
      ..strokeCap = StrokeCap.butt;
    for (final b in blocks) {
      for (final r in b.occupiedRanges) {
        final from = math.max(0, r.start).toDouble();
        final to = math.min(TimeMath.minutesPerDay, r.end).toDouble();
        if (to <= from) continue;
        // 扣 0.6px 的缝，换算成角度要除以半径。
        final sweep = ((to - from) / 1440 * 2 * math.pi * mid - 0.6) / mid;
        paint.color = Palette.of(b.category);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(_c, _c), radius: mid),
          _angle(from),
          math.max(sweep, 0.001),
          false,
          paint,
        );
      }
    }
  }

  void _seams(Canvas canvas, List<DayBlock> blocks, double mid) {
    final pieces = <({int from, int to, int cat})>[];
    for (final b in blocks) {
      for (final r in b.occupiedRanges) {
        pieces.add((
          from: r.start,
          to: math.min(r.end, 1440),
          cat: b.category.index,
        ));
      }
    }
    pieces.sort((a, b) => a.from.compareTo(b.from));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Palette.seam;
    for (var i = 0; i < pieces.length - 1; i++) {
      if (pieces[i].cat == pieces[i + 1].cat) continue;
      final t = pieces[i].to;
      final a = _angle(t.toDouble());
      canvas.drawLine(
        Offset(
          _c + (mid - _band / 2) * math.cos(a),
          _c + (mid - _band / 2) * math.sin(a),
        ),
        Offset(
          _c + (mid + _band / 2) * math.cos(a),
          _c + (mid + _band / 2) * math.sin(a),
        ),
        paint,
      );
    }
  }

  void _ticks(Canvas canvas) {
    for (final h in const [0, 6, 12, 18]) {
      final a = _angle(h * 60);
      final tp = TextPainter(
        text: TextSpan(
          text: h.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 11,
            color: Palette.faint,
            height: 1,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = Offset(_c + 162 * math.cos(a), _c + 162 * math.sin(a));
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ComparePainter old) =>
      old.plan.length != plan.length ||
      old.actual.length != actual.length ||
      old.fontFamily != fontFamily ||
      old.isLight != isLight ||
      !_same(old.plan, plan) ||
      !_same(old.actual, actual);

  bool _same(List<DayBlock> a, List<DayBlock> b) {
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

/// 本周：7 根堆叠柱，每根固定 24h。
///
/// 这张图真正的用途不是看「计划 vs 实际」，而是看**工作日 / 节假日两种形态
/// 有没有真的切换过来**：周一到周五应该是一种节奏，周六日另一种。
/// 如果周六日的柱形和工作日一模一样，说明节假日表没生效，
/// 比任何偏差数字都更值得注意（界面上另写一行提示）。
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.days});

  final List<DaySummary> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Column(
                children: [
                  Text(
                    _weekday(d.date),
                    style: TypeScale.label.copyWith(color: Palette.muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${d.date.month}/${d.date.day}',
                    style: TypeScale.labelSmall.copyWith(
                      fontFeatures: TypeScale.tabular,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Bar(day: d),
                  const SizedBox(height: 8),
                  Text(
                    !d.hasData ? (d.isFuture ? '未到' : '无数据') : d.planName,
                    style: TypeScale.labelSmall.copyWith(
                      color: d.hasData ? Palette.faint : Palette.ghost,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day});

  final DaySummary day;

  static const double height = 288;

  @override
  Widget build(BuildContext context) {
    if (day.isFuture) {
      return _placeholder(filled: true, text: '未到');
    }
    if (!day.hasData) {
      return _placeholder(filled: false, text: '无数据');
    }

    final segs = <({int minutes, Color color})>[];
    for (final c in Category.values) {
      final m = day.actualMinutes[c] ?? 0;
      if (m > 0) segs.add((minutes: m, color: Palette.of(c)));
    }
    final used = segs.fold(0, (s, e) => s + e.minutes);
    final gap = math.max(0, TimeMath.minutesPerDay - used);
    if (gap > 0) segs.add((minutes: gap, color: Palette.unplanned));

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // 6 / 12 / 18 点三条参考线，让「哪一段被挤掉了」有参照。
          for (final f in const [0.25, 0.5, 0.75])
            Positioned(
              top: height * f,
              left: 0,
              right: 0,
              child: Container(height: 1, color: Palette.rule),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in segs)
                  Expanded(
                    flex: math.max(1, s.minutes),
                    child: ColoredBox(color: s.color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder({required bool filled, required String text}) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? Palette.control.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(8),
        border: filled ? null : Border.all(color: Palette.control, width: 1.2),
      ),
      child: Text(
        text,
        style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
      ),
    );
  }
}

/// 本月：日历热图。格子亮度 = 当天「学习 + 锻炼」的实际分钟数。
/// 看的是连续性，不是占比 —— 所以不画饼、不画环、不写达标线。
class MonthHeatmap extends StatelessWidget {
  const MonthHeatmap({super.key, required this.days, this.onDayTap});

  final List<DaySummary> days;

  /// 点某一天 = 指派那天用哪张表。空实现时保持纯展示（golden 测试用）。
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final blanks = days.first.date.weekday - 1;
    final maxFocus = days
        .where((d) => d.hasData)
        .map((d) => d.focusMinutes)
        .fold(0, math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            // 6 行（含首周空格）必须在 720 高窗口里全放下，否则最后一行
            // 只露半截，图例也被挤到滚动区外。新外壳多了 18px 留白，
            // 所以比旧版的 1.9 再扁一点。
            childAspectRatio: 2.1,
          ),
          itemCount: blanks + days.length,
          itemBuilder: (context, i) {
            if (i < blanks) return const SizedBox.shrink();
            return _Cell(
              day: days[i - blanks],
              maxFocus: maxFocus,
              onTap: onDayTap == null
                  ? null
                  : () => onDayTap!(days[i - blanks].date),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '学习 + 锻炼 · 少',
              style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
            ),
            const SizedBox(width: 8),
            for (var i = 0; i < 5; i++)
              Container(
                width: 16,
                height: 10,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: _heat(i / 4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 5),
            Text(
              '多',
              style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
            ),
          ],
        ),
      ],
    );
  }

  /// 两套主题的温度方向相反：深色越亮=越多，浅色越深=越多。
  /// 白底上把颜色提亮只会融进背景，等于没有格子。
  static Color _heat(double t) => Palette.heatFill(t);
}

class _Cell extends StatefulWidget {
  const _Cell({required this.day, required this.maxFocus, this.onTap});

  final DaySummary day;
  final int maxFocus;
  final VoidCallback? onTap;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final d = day.date.day;
    final Widget box;
    var t = 0.0;

    if (day.isFuture) {
      box = _box(Palette.control.withValues(alpha: 0.14), null);
    } else if (!day.hasData) {
      box = _box(null, Palette.control);
    } else {
      t = widget.maxFocus == 0
          ? 0.0
          : (day.focusMinutes / widget.maxFocus).clamp(0.0, 1.0);
      box = _box(MonthHeatmap._heat(t), null);
    }

    final canTap = widget.onTap != null;
    final tip = day.hasData
        ? '${TimeMath.dateKey(day.date)} · ${day.planName} · '
              '学习+锻炼 ${day.focusMinutes} 分钟'
        : '${TimeMath.dateKey(day.date)} · ${day.isFuture ? '未到' : '无数据'}';
    return Tooltip(
      message: canTap ? '$tip\n点击可指派这天的计划表' : tip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              box,
              Text(
                '$d',
                style: TypeScale.labelSmall.copyWith(
                  color: day.hasData ? Palette.heatText(t) : Palette.ghost,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
              if (_hover && canTap)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Palette.accent, width: 1.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _box(Color? fill, Color? border) => Container(
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      border: border == null ? null : Border.all(color: border, width: 1.2),
    ),
  );
}

String _weekday(DateTime d) => switch (d.weekday) {
  1 => '周一',
  2 => '周二',
  3 => '周三',
  4 => '周四',
  5 => '周五',
  6 => '周六',
  _ => '周日',
};
