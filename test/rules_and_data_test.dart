import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/calendar_rules.dart';
import 'package:routine_reminder/domain/day_mode.dart';
import 'package:routine_reminder/domain/stats.dart';
import 'package:routine_reminder/data/app_data.dart';

void main() {
  group('规则栈优先级', () {
    test('没有任何规则时按星期几走', () {
      final rules = CalendarRules();
      // 2026-11-02 是周一
      expect(rules.resolve(DateTime(2026, 11, 2)).mode, DayMode.workday);
      expect(rules.resolve(DateTime(2026, 11, 2)).source, '按星期几');
      // 2026-11-07 是周六
      expect(rules.resolve(DateTime(2026, 11, 7)).mode, DayMode.holiday);
    });

    test('单日例外压过一切', () {
      final rules = CalendarRules(overrides: {'2026-11-07': DayMode.workday});
      final r = rules.resolve(DateTime(2026, 11, 7));
      expect(r.mode, DayMode.workday);
      expect(r.source, '单日例外');
    });

    test('法定节假日（调休上班）压过周期规则', () {
      final rules = CalendarRules(
        specialDates: {'2026-11-07': DayMode.workday},
        cycle: CycleRule(
          type: CycleType.bigSmallWeek,
          anchorDate: DateTime(2026, 11, 2),
          anchorIsBig: false,
        ),
      );
      // 小周的周六本来是休息，但调休上班日压过它
      expect(rules.resolve(DateTime(2026, 11, 7)).mode, DayMode.workday);
    });
  });

  group('大小周', () {
    final rules = CalendarRules(
      cycle: CycleRule(
        type: CycleType.bigSmallWeek,
        anchorDate: DateTime(2026, 11, 2), // 周一，这是大周
        anchorIsBig: true,
      ),
    );

    test('大周的周六上班，下一周周六休息（隔周交替）', () {
      expect(rules.resolve(DateTime(2026, 11, 7)).mode, DayMode.workday);
      expect(rules.resolve(DateTime(2026, 11, 14)).mode, DayMode.holiday);
      expect(rules.resolve(DateTime(2026, 11, 21)).mode, DayMode.workday);
    });

    test('周日两种情况都休息', () {
      expect(rules.resolve(DateTime(2026, 11, 8)).mode, DayMode.holiday);
      expect(rules.resolve(DateTime(2026, 11, 15)).mode, DayMode.holiday);
    });

    test('陷阱二：小周的周六必须明确返回节假日，不能落到星期几默认', () {
      final rules = CalendarRules(
        weekdayDefault: {
          DateTime.monday: DayMode.workday,
          DateTime.tuesday: DayMode.workday,
          DateTime.wednesday: DayMode.workday,
          DateTime.thursday: DayMode.workday,
          DateTime.friday: DayMode.workday,
          DateTime.saturday: DayMode.workday, // 用户把周六改成了上班
          DateTime.sunday: DayMode.holiday,
        },
        cycle: CycleRule(
          type: CycleType.bigSmallWeek,
          anchorDate: DateTime(2026, 11, 2),
          anchorIsBig: true,
        ),
      );
      // 2026-11-14 是小周的周六，即使默认周六上班，也该是休息
      expect(rules.resolve(DateTime(2026, 11, 14)).mode, DayMode.holiday);
    });

    test('单休：周六上班，周日休息', () {
      final rules = CalendarRules(
        cycle: CycleRule(
          type: CycleType.singleDayOff,
          anchorDate: DateTime(2026, 11, 2),
          anchorIsBig: true,
        ),
      );
      expect(rules.resolve(DateTime(2026, 11, 7)).mode, DayMode.workday);
      expect(rules.resolve(DateTime(2026, 11, 8)).mode, DayMode.holiday);
    });
  });

  group('日期键', () {
    test('补零格式固定', () {
      expect(CalendarRules.dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('内置数据', () {
    test('两套表的块数分别是 14 和 15', () {
      final data = SeedData.build();
      expect(data.blocksForMode(DayMode.workday).length, 14);
      expect(data.blocksForMode(DayMode.holiday).length, 15);
    });

    test('默认数据排满，已安排 24 小时', () {
      final data = SeedData.build();
      for (final mode in DayMode.values) {
        final totals = DayTotals.of(data.blocksForMode(mode));
        expect(totals.unplanned, 0, reason: '$mode 不应该有空档');
        expect(totals.scheduled, 1440);
      }
    });

    test('学习与锻炼累计能从块里算出来', () {
      final data = SeedData.build();
      final totals = DayTotals.of(data.blocksForMode(DayMode.workday));
      // 看书 30 + 通勤看书 30 + 08:00–08:30 看书已在第一条
      expect(totals.minutesOf(SeedData.workday[2].category), 60);
      expect(totals.minutesOf(SeedData.workday[9].category), 60);
    });

    test('JSON 往返不掉字段', () {
      final data = SeedData.build();
      final json = data.toJson();
      final again = AppData.fromJson(json);
      expect(again.toJson(), json);
    });

    test('跨零点块序列化回 07:00，不是 31:00', () {
      final json = SeedData.build().toJson();
      final workday = json['plans'][0]['blocks'] as List;
      final sleep = workday.last as Map<String, dynamic>;
      expect(sleep['start'], '23:00');
      expect(sleep['end'], '07:00');
    });
  });
}
