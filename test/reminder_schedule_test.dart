import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/reminder_schedule.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/plan.dart';

/// 到点提醒的排程口径。这里只验「排哪些、排到哪天、按哪张表」，
/// 不碰系统通道 —— 真正的下发由 `platform/reminders.dart` 负责，
/// 测试里那条路径是 Noop。
void main() {
  // 2026-11-08 是周日 → 默认命中「节假日」表。
  final now = DateTime(2026, 11, 8, 9, 15);

  test('只排未来时段，且按时间升序', () {
    final slots = buildReminderSlots(SeedData.build(), now);
    expect(slots, isNotEmpty);
    for (final slot in slots) {
      expect(
        slot.at.isAfter(now),
        isTrue,
        reason: '${slot.title} 的开始时间 ${slot.at} 已经过去了',
      );
    }
    for (var i = 1; i < slots.length; i++) {
      expect(slots[i].at.isBefore(slots[i - 1].at), isFalse);
    }
  });

  test('按天用对应日期的表：周日走节假日，周一走工作日', () {
    final data = SeedData.build();
    final sunday = buildReminderSlots(data, now, days: 1);
    final monday = buildReminderSlots(
      data,
      DateTime(2026, 11, 9, 0, 1),
      days: 1,
    );

    Set<String> titlesOf(List<dynamic> slots) =>
        slots.map((s) => s.title as String).toSet();

    final holidayTitles = data
        .planById(PlanDefaults.holidayId)!
        .blocks
        .map((b) => b.name)
        .toSet();
    final workdayTitles = data
        .planById(PlanDefaults.workdayId)!
        .blocks
        .map((b) => b.name)
        .toSet();

    expect(titlesOf(sunday).difference(holidayTitles), isEmpty);
    expect(titlesOf(monday).difference(workdayTitles), isEmpty);
  });

  test('窗口是 7 天：第 8 天不进清单', () {
    // 从 00:01 起算，7 天窗口覆盖 11-08..11-14；11-15 的段不能出现。
    final start = DateTime(2026, 11, 8, 0, 1);
    final slots = buildReminderSlots(SeedData.build(), start, days: 7);
    final lastDay = DateTime(2026, 11, 15);
    expect(slots.every((s) => s.at.isBefore(lastDay)), isTrue);
    // 且确实排到了第 7 天（11-14）的东西。
    expect(
      slots.any((s) => s.at.year == 2026 && s.at.month == 11 && s.at.day == 14),
      isTrue,
    );
  });

  test('单日改判后，那天的提醒跟着换成被指派的表', () {
    final data = SeedData.build().assignDay(
      '2026-11-09',
      PlanDefaults.holidayId,
      at: '2026-11-08T09:00:00',
    );
    final slots = buildReminderSlots(data, DateTime(2026, 11, 9, 0, 1), days: 1);
    final holidayTitles = data
        .planById(PlanDefaults.holidayId)!
        .blocks
        .map((b) => b.name)
        .toSet();
    expect(slots.map((s) => s.title).toSet().difference(holidayTitles), isEmpty);
  });

  test('正文带上起止与分类，标题就是段名', () {
    final slots = buildReminderSlots(SeedData.build(), now, days: 1);
    final first = slots.first;
    expect(first.title, isNotEmpty);
    expect(first.body, contains('–'));
    expect(first.body, contains('·'));
  });

  test('数量受 limit 约束，防止极端数据把系统闹钟排满', () {
    final slots = buildReminderSlots(SeedData.build(), now, days: 30, limit: 5);
    expect(slots.length, 5);
  });
}
