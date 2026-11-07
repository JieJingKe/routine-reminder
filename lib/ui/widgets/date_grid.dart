import 'package:flutter/material.dart';

import 'hover_intent.dart';

import '../../design/tokens.dart';
import '../../domain/time_math.dart';

/// 月历网格。周一起始，只负责「显示 + 点选」，不持有状态。
///
/// 两处复用：单表编辑器里圈特殊日期（多选），以及 L3 日历点选那天用
/// 哪张表（外部弹层里单选）。抽出来是为了不让两处各写一套日期排版。
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    this.selected = const <String>{},
    this.onToggle,
    this.onPick,
    this.today,
    this.highlight,
  });

  /// 落在哪个月由任意一个日期决定。
  final DateTime month;

  /// 已选中的 `YYYY-MM-DD`。选中格用强调色实心。
  final Set<String> selected;

  /// 多选模式：点一天切换选中态。
  final ValueChanged<String>? onToggle;

  /// 单选模式：点一天直接返回。与 [onToggle] 二选一。
  final ValueChanged<String>? onPick;

  final DateTime? today;

  /// 额外描边的日期（例如「被手动指派的那天」），与选中态互不覆盖。
  final String? highlight;

  static String keyOf(DateTime d) => TimeMath.dateKey(d);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final blanks = first.weekday - 1;
    final todayKey = today == null ? null : keyOf(today!);

    final cells = <Widget>[];
    for (var i = 0; i < blanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= days; d++) {
      final date = DateTime(month.year, month.month, d);
      final key = keyOf(date);
      cells.add(
        _DayCell(
          day: d,
          selected: selected.contains(key),
          isToday: key == todayKey,
          highlighted: key == highlight,
          onTap: () {
            onToggle?.call(key);
            onPick?.call(key);
          },
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: 6),
        for (var i = 0; i < cells.length; i += 7)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (final c in cells.sublist(i, i + 7))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: c,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.highlighted,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool isToday;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      builder: (context, hover) {
        final fill = widget.selected
            ? Palette.accent
            : (hover ? Palette.hover : Colors.transparent);
        final border = widget.selected
            ? null
            : Border.all(
                color: widget.highlighted
                    ? Palette.accent
                    : (widget.isToday ? Palette.control : Palette.rule),
                width: widget.highlighted || widget.isToday ? 1.4 : 1,
              );
        return Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            border: border,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Text(
            '${widget.day}',
            style: TypeScale.labelSmall.copyWith(
              color: widget.selected ? Colors.white : Palette.text,
              fontFeatures: TypeScale.tabular,
              fontWeight: widget.isToday ? FontWeight.w600 : null,
            ),
          ),
        );
      },
    );
  }
}
