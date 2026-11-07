import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/calendar_rules.dart';
import '../../domain/day_mode.dart';
import 'segmented.dart';

/// 周期规则面板（R2：大小周 / 单休）。
///
/// 关键纪律：锚点存的是**那一周周一的绝对日期**，不是「本周是大周」。
/// 存相对说法，下周打开时"本周"已经变了，会永远返回大周。
Future<CycleRule?> showCycleRulesDialog(
  BuildContext context,
  CycleRule current,
) {
  return showDialog<CycleRule>(
    context: context,
    builder: (_) => _CycleRulesDialog(current: current),
  );
}

class _CycleRulesDialog extends StatefulWidget {
  const _CycleRulesDialog({required this.current});

  final CycleRule current;

  @override
  State<_CycleRulesDialog> createState() => _CycleRulesDialogState();
}

class _CycleRulesDialogState extends State<_CycleRulesDialog> {
  late CycleRule _cycle = widget.current;

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _key(DateTime d) => CalendarRules.dateKey(d);

  void _setType(CycleType type) {
    setState(() {
      _cycle = CycleRule(
        type: type,
        anchorDate: type == CycleType.bigSmallWeek
            ? (_cycle.anchorDate ?? _mondayOf(DateTime.now()))
            : _cycle.anchorDate,
        anchorIsBig: _cycle.anchorIsBig,
      );
    });
  }

  /// 改「这一周是」= 把锚点重设成本周，再记下它是大周还是小周。
  void _setThisWeek(bool big) {
    setState(() {
      _cycle = CycleRule(
        type: CycleType.bigSmallWeek,
        anchorDate: _mondayOf(DateTime.now()),
        anchorIsBig: big,
      );
    });
  }

  bool _isBigWeek(DateTime d) => CalendarRules(cycle: _cycle).isBigWeek(d);

  String get _note {
    if (_cycle.type == CycleType.none) {
      return '未启用周期规则，今天按星期几判断。';
    }
    if (_cycle.type == CycleType.singleDayOff) {
      return '单休：周一至周六上班，周日休息。';
    }
    final sat = _mondayOf(DateTime.now()).add(const Duration(days: 5));
    final sat2 = sat.add(const Duration(days: 7));
    String label(DateTime d) => _isBigWeek(d) ? '工作日表' : '节假日表';
    return '本周六 → ${label(sat)}　下周六 → ${label(sat2)}\n'
        '锚点周 ${_cycle.anchorDate == null ? '—' : _key(_cycle.anchorDate!)}（周一）'
        '记为${_cycle.anchorIsBig ? '大周' : '小周'}，之后隔周交替。\n'
        '存的是绝对日期 —— 下周打开不会漂成「永远是大周」。';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: Palette.control),
      ),
      title: Text('周期规则', style: TypeScale.section),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('周期类型', style: TypeScale.labelSmall),
            const SizedBox(height: 6),
            Segmented<CycleType>(
              items: CycleType.values,
              value: _cycle.type,
              onChanged: _setType,
              compact: true,
              labelOf: (t) => switch (t) {
                CycleType.none => '不设置',
                CycleType.bigSmallWeek => '大小周',
                CycleType.singleDayOff => '单休',
              },
            ),
            if (_cycle.type == CycleType.bigSmallWeek) ...[
              const SizedBox(height: 16),
              Text('这一周（周一至周日）是', style: TypeScale.labelSmall),
              const SizedBox(height: 6),
              Segmented<bool>(
                items: const [true, false],
                value: _cycle.anchorIsBig,
                onChanged: _setThisWeek,
                compact: true,
                labelOf: (big) => big ? '大周 · 周六上班' : '小周 · 周六休息',
              ),
            ],
            const SizedBox(height: 14),
            Text(_note, style: TypeScale.labelSmall.copyWith(height: 1.7)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TypeScale.label),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(_cycle),
          child: Text('完成', style: TypeScale.label),
        ),
      ],
    );
  }
}

/// 给说明文字用：DayMode 的中文表名。
String modeLabel(DayMode mode) => mode.label;
