import 'app_data.dart';
import '../domain/reminder_slot.dart';
import '../domain/time_math.dart';

/// 把「接下来几天该提醒什么」算成一张扁平清单。
///
/// 判定一律走 [AppData.forDate] —— 单日改判、特殊日期、周期规则都在里面，
/// 这里再算一遍就会和看板两套结论。日期归属只影响「哪张表」，提醒的绝对
/// 时刻始终是「那天的那个钟点」，所以不需要关心 23:00 起点的排序口径。
///
/// 只排未来的：已经过去的段排上去也只会立刻弹一条，反而是骚扰。
List<ReminderSlot> buildReminderSlots(
  AppData data,
  DateTime now, {
  int days = 7,
  int limit = 240,
}) {
  final slots = <ReminderSlot>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final resolved = data.forDate(day);
    for (final block in resolved.blocks) {
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        block.start ~/ 60,
        block.start % 60,
      );
      if (!at.isAfter(now)) continue;
      slots.add(
        ReminderSlot(
          at: at,
          title: block.name,
          body:
              '${TimeMath.formatHm(block.start)} – '
              '${TimeMath.formatHm(block.end)} · ${block.category.label}',
        ),
      );
    }
  }
  slots.sort((a, b) => a.at.compareTo(b.at));
  return slots.length > limit ? slots.sublist(0, limit) : slots;
}
