import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/app_repository.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/calendar_rules.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/domain/day_mode.dart';
import 'package:routine_reminder/domain/plan.dart';

/// #8 多计划表：先把行为写成测试，再实现。
///
/// 三条不可动摇的语义（交接文档第 4 节已批准）：
/// 1. 列表顺序 = 同日冲突优先级（first match wins）；
/// 2. 重复规则四选一：每天 / 按星期 / 周期 / 指定日期；
/// 3. 特殊日期由每张表自己维护，且优先于常规重复；单日例外再压过它。
void main() {
  Plan make(
    String id,
    String name,
    RepeatRule repeat, {
    DayMode? legacyMode,
    List<DayBlock> blocks = const [],
  }) => Plan(
    id: id,
    name: name,
    blocks: blocks,
    reminders: const [],
    repeat: repeat,
    legacyMode: legacyMode,
  );

  AppData dataOf(List<Plan> plans, {Map<String, String>? dayOverrides}) =>
      AppData(
        plans: plans,
        dayOverrides: dayOverrides ?? const {},
        rules: CalendarRules(),
        daySnapshots: const {},
        ui: const UiPrefs(),
        records: const {},
      );

  // 2026-11-02 周一；11-07 周六；11-08 周日。
  final monday = DateTime(2026, 11, 2);
  final saturday = DateTime(2026, 11, 7);
  final sunday = DateTime(2026, 11, 8);

  group('重复规则四选一', () {
    test('每天：任何日期都遵从', () {
      final r = const RepeatRule(kind: RepeatKind.daily);
      expect(r.matchesRegular(monday), isTrue);
      expect(r.matchesRegular(saturday), isTrue);
      expect(r.matchesRegular(sunday), isTrue);
    });

    test('按星期：只在选中的星期遵从', () {
      final r = const RepeatRule(
        kind: RepeatKind.weekly,
        weekdays: {1, 2, 3, 4, 5},
      );
      expect(r.matchesRegular(monday), isTrue);
      expect(r.matchesRegular(saturday), isFalse);
      expect(r.matchesRegular(sunday), isFalse);
    });

    test('指定日期：只在列出的日期遵从，常规层一律不命中', () {
      final r = const RepeatRule(kind: RepeatKind.dates, dates: {'2026-11-07'});
      expect(r.matchesSpecial(saturday), isTrue);
      expect(r.matchesSpecial(monday), isFalse);
      expect(r.matchesRegular(saturday), isFalse);
      expect(r.matchesRegular(monday), isFalse);
    });

    test('周期 · 大小周：隔周交替，锚点是绝对日期', () {
      final cycle = CycleRule(
        type: CycleType.bigSmallWeek,
        anchorDate: monday,
        anchorIsBig: true,
      );
      final big = RepeatRule(
        kind: RepeatKind.cycle,
        weekdays: const {1, 2, 3, 4, 5, 6},
        cycle: cycle,
        cycleBigWeek: true,
      );
      final small = RepeatRule(
        kind: RepeatKind.cycle,
        weekdays: const {6, 7},
        cycle: cycle,
        cycleBigWeek: false,
      );
      // 大周周六：大周表命中，小周表不命中。
      expect(big.matchesRegular(saturday), isTrue);
      expect(small.matchesRegular(saturday), isFalse);
      // 隔一周变反过来。
      final nextSaturday = saturday.add(const Duration(days: 7));
      expect(big.matchesRegular(nextSaturday), isFalse);
      expect(small.matchesRegular(nextSaturday), isTrue);
      // 周日不受大小周影响，不能因为"小周表"就消失。
      expect(small.matchesRegular(sunday), isTrue);
      // 周一至周五也不受大小周影响。
      expect(big.matchesRegular(monday), isTrue);
    });

    test('周期 · 单休：靠 weekdays 表达，周六归工作日表', () {
      final work = const RepeatRule(
        kind: RepeatKind.weekly,
        weekdays: {1, 2, 3, 4, 5, 6},
      );
      final rest = const RepeatRule(kind: RepeatKind.weekly, weekdays: {7});
      expect(work.matchesRegular(saturday), isTrue);
      expect(rest.matchesRegular(saturday), isFalse);
      expect(rest.matchesRegular(sunday), isTrue);
    });

    test('RepeatRule JSON 往返稳定（集合排序后落盘）', () {
      final r = RepeatRule(
        kind: RepeatKind.cycle,
        weekdays: const {6, 1, 3},
        cycle: CycleRule(
          type: CycleType.bigSmallWeek,
          anchorDate: monday,
          anchorIsBig: false,
        ),
        cycleBigWeek: false,
        dates: const {'2026-11-07', '2026-11-02'},
      );
      final json = r.toJson();
      expect(RepeatRule.fromJson(json).toJson(), json);
      expect(json['weekdays'], [1, 3, 6]);
      expect(json['dates'], ['2026-11-02', '2026-11-07']);
    });
  });

  group('同日解析优先级', () {
    final a = make('a', 'A 表', const RepeatRule(kind: RepeatKind.daily));
    final b = make('b', 'B 表', const RepeatRule(kind: RepeatKind.daily));

    test('列表顺序决定同日冲突（first match wins）', () {
      expect(dataOf([a, b]).forDate(monday).planId, 'a');
      expect(dataOf([b, a]).forDate(monday).planId, 'b');
    });

    test('单日例外压过一切，按 planId 覆盖', () {
      final data = dataOf([a, b], dayOverrides: {'2026-11-02': 'b'});
      final r = data.forDate(monday);
      expect(r.planId, 'b');
      expect(r.source, '单日例外');
      // 没被覆盖的那天照常走列表顺序。
      expect(data.forDate(saturday).planId, 'a');
    });

    test('特殊日期层压过常规重复层', () {
      final normal = make('n', '常态', const RepeatRule(kind: RepeatKind.daily));
      final special = make(
        's',
        '特殊日',
        const RepeatRule(kind: RepeatKind.dates, dates: {'2026-11-07'}),
      );
      final data = dataOf([normal, special]);
      expect(data.forDate(monday).planId, 'n');
      final r = data.forDate(saturday);
      expect(r.planId, 's');
      expect(r.source, '特殊日期');
    });

    test('单日例外再压过特殊日期', () {
      final normal = make('n', '常态', const RepeatRule(kind: RepeatKind.daily));
      final special = make(
        's',
        '特殊日',
        const RepeatRule(kind: RepeatKind.dates, dates: {'2026-11-07'}),
      );
      final data = dataOf([normal, special], dayOverrides: {'2026-11-07': 'n'});
      expect(data.forDate(saturday).planId, 'n');
      expect(data.forDate(saturday).source, '单日例外');
    });

    test('没有表命中时兜底第一张，且来源写明', () {
      final only = make(
        'x',
        '只在某些天',
        const RepeatRule(kind: RepeatKind.dates, dates: {'2026-11-09'}),
      );
      final r = dataOf([only]).forDate(monday);
      expect(r.planId, 'x');
      expect(r.source, '默认计划表');
    });

    test('forDate 带出该表自己的块与提醒，不串表', () {
      final block = const DayBlock(
        start: 480,
        end: 540,
        name: 'A 专属',
        category: Category.work,
      );
      final withBlocks = make(
        'a',
        'A 表',
        const RepeatRule(kind: RepeatKind.daily),
        blocks: [block],
      );
      final data = dataOf([withBlocks, b]);
      expect(data.forDate(monday).blocks.single.name, 'A 专属');
      expect(data.forDate(monday).label, 'A 表（每天）');
    });
  });

  group('AppData 计划表操作', () {
    test('withPlanBlocks 只改指定表，顺序与其余表不变', () {
      final a = make(
        'a',
        'A 表',
        const RepeatRule(kind: RepeatKind.daily),
        legacyMode: DayMode.workday,
      );
      final b = make(
        'b',
        'B 表',
        const RepeatRule(kind: RepeatKind.daily),
        legacyMode: DayMode.holiday,
      );
      final data = dataOf([a, b]);
      final changed = [SeedData.workday.first];
      final next = data.withPlanBlocks('b', changed);
      expect(next.plans[0].blocks, isEmpty);
      expect(next.plans[1].blocks.single.name, SeedData.workday.first.name);
      expect(next.plans.map((p) => p.id).toList(), ['a', 'b']);
      expect(data.plans[1].blocks, isEmpty); // 原对象不可变
    });

    test('withSchedule 兼容旧入口：按 legacyMode 找到对应表', () {
      final a = make(
        'a',
        '工作日',
        const RepeatRule(kind: RepeatKind.daily),
        legacyMode: DayMode.workday,
      );
      final b = make(
        'b',
        '节假日',
        const RepeatRule(kind: RepeatKind.daily),
        legacyMode: DayMode.holiday,
      );
      final next = dataOf([a, b])
          .withSchedule(DayMode.holiday, [SeedData.holiday.first]);
      expect(next.plans[1].blocks.single.name, SeedData.holiday.first.name);
      expect(next.plans[0].blocks, isEmpty);
    });

    test('withDayOverride 写入 / 传 null 删除，不动 plans', () {
      final a = make('a', 'A', const RepeatRule(kind: RepeatKind.daily));
      final data = dataOf([a]);
      final added = data.withDayOverride('2026-11-02', 'a');
      expect(added.dayOverrides['2026-11-02'], 'a');
      expect(added.withDayOverride('2026-11-02', null).dayOverrides, isEmpty);
      expect(added.plans, same(data.plans));
    });

    test('withRules 把周期规则同步到两张 legacy 表（旧弹窗仍生效）', () {
      final data = AppData.fromJson(_v1Json());
      final cycle = CycleRule(
        type: CycleType.bigSmallWeek,
        anchorDate: monday,
        anchorIsBig: true,
      );
      // 例外放在周一，免得遮住下面要验的大周周六。
      final next = data.withRules(
        CalendarRules(cycle: cycle, overrides: {'2026-11-02': DayMode.holiday}),
      );
      expect(next.rules.cycle.type, CycleType.bigSmallWeek);
      expect(next.dayOverrides['2026-11-02'], PlanDefaults.holidayId);
      expect(next.forDate(monday).planId, PlanDefaults.holidayId);
      final work = next.plans.firstWhere((p) => p.id == PlanDefaults.workdayId);
      expect(work.repeat.kind, RepeatKind.cycle);
      expect(work.repeat.cycleBigWeek, isTrue);
      expect(work.repeat.weekdays, contains(DateTime.saturday));
      // 大周周六走工作日表，小周周六走节假日表 —— 与旧规则栈一致。
      expect(next.forDate(saturday).planName, '工作日');
      expect(
        next.forDate(saturday.add(const Duration(days: 7))).planName,
        '节假日',
      );
    });

    test('withRules 只动 legacy 表，用户新建的表不受影响', () {
      final base = AppData.fromJson(_v1Json());
      final custom = make(
        'custom',
        '自定义',
        const RepeatRule(kind: RepeatKind.daily),
      );
      final data = base.withPlans([...base.plans, custom]);
      final next = data.withRules(CalendarRules());
      expect(next.plans.last.id, 'custom');
      expect(next.plans.last.repeat.kind, RepeatKind.daily);
    });

    test('restoredDefaults 重置为两张内置表，保留历史与偏好', () {
      final base = AppData.fromJson(_v1Json());
      final dirty = base
          .withUi(base.ui.copyWith(theme: 'light'))
          .withPlanBlocks(PlanDefaults.workdayId, const []);
      final restored = dirty.restoredDefaults();
      expect(restored.plans.length, 2);
      expect(restored.plans.first.blocks.length, SeedData.workday.length);
      expect(restored.ui.theme, 'light');
      expect(restored.daySnapshots, same(base.daySnapshots));
    });
  });

  group('v1 → v2 迁移', () {
    test('旧格式生成工作日 / 节假日两张表，块与提醒原样带走', () {
      final data = AppData.fromJson(_v1Json());
      expect(data.schemaVersion, 2);
      expect(data.plans.length, 2);
      expect(data.plans[0].id, PlanDefaults.workdayId);
      expect(data.plans[0].name, '工作日');
      expect(data.plans[0].legacyMode, DayMode.workday);
      expect(data.plans[1].id, PlanDefaults.holidayId);
      expect(data.plans[1].legacyMode, DayMode.holiday);
      expect(data.plans[0].blocks.length, 14);
      expect(data.plans[1].blocks.length, 15);
      expect(data.plans[0].reminders.length, 6);
      expect(data.plans[1].reminders.length, 4);
      // 兼容 getter 仍能按旧 DayMode 取到同一批块。
      expect(data.blocksForMode(DayMode.workday).length, 14);
      expect(data.remindersForMode(DayMode.holiday).length, 4);
    });

    test('weekdayDefault 映射成两张表的 weekdays', () {
      final data = AppData.fromJson(_v1Json());
      expect(data.plans[0].repeat.kind, RepeatKind.weekly);
      expect(data.plans[0].repeat.weekdays, {1, 2, 3, 4, 5});
      expect(data.plans[1].repeat.weekdays, {6, 7});
      expect(data.forDate(monday).planName, '工作日');
      expect(data.forDate(saturday).planName, '节假日');
    });

    test('旧 specialDates 归到对应表的特殊日期，且不共享', () {
      final data = AppData.fromJson(
        _v1Json(specialDates: {'2026-11-02': DayMode.holiday}),
      );
      expect(data.plans[1].repeat.dates, contains('2026-11-02'));
      expect(data.plans[0].repeat.dates, isNot(contains('2026-11-02')));
      // 周一原本是工作日表，但特殊日期把它拨给了节假日表。
      final r = data.forDate(monday);
      expect(r.planId, PlanDefaults.holidayId);
      expect(r.source, '特殊日期');
    });

    test('旧 overrides 变成按 planId 的单日例外', () {
      final data = AppData.fromJson(
        _v1Json(overrides: {'2026-11-07': DayMode.workday}),
      );
      expect(data.dayOverrides['2026-11-07'], PlanDefaults.workdayId);
      expect(data.forDate(saturday).planId, PlanDefaults.workdayId);
      expect(data.forDate(saturday).source, '单日例外');
    });

    test('大小周迁移：两张表共用 cycle，靠 cycleBigWeek 分工', () {
      final cycle = CycleRule(
        type: CycleType.bigSmallWeek,
        anchorDate: monday,
        anchorIsBig: true,
      );
      final data = AppData.fromJson(_v1Json(cycle: cycle));
      final work = data.plans.first;
      final rest = data.plans.last;
      expect(work.repeat.kind, RepeatKind.cycle);
      expect(rest.repeat.kind, RepeatKind.cycle);
      expect(work.repeat.cycleBigWeek, isTrue);
      expect(rest.repeat.cycleBigWeek, isFalse);
      expect(work.repeat.weekdays, contains(DateTime.saturday));
      expect(rest.repeat.weekdays, contains(DateTime.saturday));

      expect(data.forDate(saturday).planName, '工作日');
      expect(
        data.forDate(saturday.add(const Duration(days: 7))).planName,
        '节假日',
      );
      expect(data.forDate(sunday).planName, '节假日');
    });

    test('单休迁移：周六归工作日表，周日归节假日表', () {
      final data = AppData.fromJson(
        _v1Json(cycle: const CycleRule(type: CycleType.singleDayOff)),
      );
      expect(data.plans[0].repeat.kind, RepeatKind.weekly);
      expect(data.plans[0].repeat.weekdays, {1, 2, 3, 4, 5, 6});
      expect(data.plans[1].repeat.weekdays, {7});
      expect(data.forDate(saturday).planName, '工作日');
      expect(data.forDate(sunday).planName, '节假日');
    });

    test('历史快照按 planId 记，不重跑规则', () {
      final data = AppData.fromJson(
        _v1Json(
          daySnapshots: {
            '2026-11-06': {'mode': 'workday', 'source': '单日例外'},
          },
        ),
      );
      final snap = data.daySnapshots['2026-11-06']!;
      expect(snap.planId, PlanDefaults.workdayId);
      expect(snap.mode, DayMode.workday);
      expect(snap.source, '单日例外');
    });

    test('迁移结果落盘为 v2，JSON 往返幂等', () {
      final data = AppData.fromJson(_v1Json());
      final json = data.toJson();
      expect(json['schemaVersion'], 2);
      expect(json['plans'], isA<List>());
      expect(json['dayOverrides'], isA<Map>());
      expect(json.containsKey('schedules'), isFalse);
      expect(AppData.fromJson(json).toJson(), json);
    });

    test('空 / 损坏的 plans 不会把数据读成空壳', () {
      final broken = Map<String, dynamic>.from(_v1Json())
        ..['plans'] = <dynamic>[];
      final data = AppData.fromJson(broken);
      expect(data.plans, isNotEmpty);
    });
  });

  group('Repository 迁移落盘', () {
    test('读 v1 → 备份 .bak → 回写 v2，且备份不被二次覆盖', () async {
      final dir = await Directory.systemTemp.createTemp('rr_plans_test');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final original = jsonEncode(_v1Json());
      final file = File('${dir.path}${Platform.pathSeparator}data.json');
      await file.writeAsString(original);

      final repo = AppRepository(dataDirOverride: dir);
      final data = await repo.load();
      expect(data.plans.length, 2);
      expect(data.schemaVersion, 2);

      final bak = File('${dir.path}${Platform.pathSeparator}data.json.bak');
      expect(await bak.exists(), isTrue);
      // 备份必须逐字节是迁移前的原始内容。
      expect(await bak.readAsString(), original);

      final rewritten = jsonDecode(await file.readAsString()) as Map;
      expect(rewritten['schemaVersion'], 2);
      expect(rewritten['plans'], isA<List>());

      // 再读一次：已迁移，不该重写备份、也不该再改 data.json。
      repo.resetCache();
      final again = await repo.load();
      expect(again.toJson(), data.toJson());
      expect(await bak.readAsString(), original);
    });

    test('本来就是 v2 的文件不产生 .bak', () async {
      final dir = await Directory.systemTemp.createTemp('rr_plans_test_v2');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}data.json');
      await file.writeAsString(jsonEncode(SeedData.build().toJson()));
      final repo = AppRepository(dataDirOverride: dir);
      await repo.load();
      final bak = File('${dir.path}${Platform.pathSeparator}data.json.bak');
      expect(await bak.exists(), isFalse);
    });
  });
}

/// 造一份 11-07 之前的旧格式 data.json。
Map<String, dynamic> _v1Json({
  Map<String, DayMode> overrides = const {},
  Map<String, DayMode> specialDates = const {},
  CycleRule? cycle,
  Map<int, DayMode>? weekdayDefault,
  Map<String, dynamic>? daySnapshots,
}) {
  final seed = SeedData.build();
  Map<String, dynamic> blocks(DayMode mode) => {
    mode.key: seed.blocksForMode(mode).map((b) => b.toJson()).toList(),
  };
  return {
    'schedules': {...blocks(DayMode.workday), ...blocks(DayMode.holiday)},
    'reminders': {
      DayMode.workday.key: seed
          .remindersForMode(DayMode.workday)
          .map((r) => r.toJson())
          .toList(),
      DayMode.holiday.key: seed
          .remindersForMode(DayMode.holiday)
          .map((r) => r.toJson())
          .toList(),
    },
    'rules': CalendarRules(
      overrides: overrides,
      specialDates: specialDates,
      cycle: cycle ?? const CycleRule(),
      weekdayDefault: weekdayDefault,
    ).toJson(),
    'daySnapshots': daySnapshots ?? <String, dynamic>{},
    'ui': const UiPrefs().toJson(),
    'records': <String, dynamic>{},
  };
}
