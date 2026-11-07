import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/data/summary.dart';
import 'package:routine_reminder/domain/plan.dart';
import 'package:routine_reminder/domain/time_math.dart';

/// #9 的核心回归：用户「过了大半天才切换」时，看板、快照、汇总必须是
/// 同一张表。v0.8 里快照只在启动时写一次，切换后 L1 换表、L3 不换，
/// 正是这一组用例要钉死的矛盾。
void main() {
  final now = DateTime(2026, 11, 7, 15, 30); // 周六 → 节假日表
  final key = TimeMath.dateKey(now);
  const at = '2026-11-07T15:30:00.000';

  AppData booted() {
    final data = SeedData.build();
    final r = data.forDate(now);
    return data.withSnapshot(
      key,
      DaySnapshot(planId: r.planId, mode: r.mode, source: r.source),
    );
  }

  test('启动时快照记的是自动判定，没有改判审计', () {
    final d = booted();
    expect(d.forDate(now).planId, PlanDefaults.holidayId);
    expect(d.daySnapshots[key]!.planId, PlanDefaults.holidayId);
    expect(d.daySnapshots[key]!.isOverridden, isFalse);
    expect(SummaryModel.forDay(d, now, now).planName, '节假日');
  });

  test('大半天后改判：看板与汇总同表，快照刷新并留下审计', () {
    final assigned = booted().assignDay(key, PlanDefaults.workdayId, at: at);
    expect(assigned.dayOverrides[key], PlanDefaults.workdayId);
    expect(assigned.forDate(now).planId, PlanDefaults.workdayId);
    expect(assigned.forDate(now).source, '单日例外');

    final snap = assigned.daySnapshots[key]!;
    expect(snap.planId, PlanDefaults.workdayId);
    expect(snap.source, '手动改判');
    expect(snap.isOverridden, isTrue);
    expect(snap.autoPlanId, PlanDefaults.holidayId);
    expect(snap.overriddenAt, at);

    final day = SummaryModel.forDay(assigned, now, now);
    expect(day.planName, '工作日');
    expect(day.source, '手动改判');
    expect(
      day.plan.length,
      assigned.planById(PlanDefaults.workdayId)!.blocks.length,
    );
  });

  test('恢复自动判定会清掉改判审计，回到规则结果', () {
    final back = booted()
        .assignDay(key, PlanDefaults.workdayId, at: at)
        .assignDay(key, null);
    expect(back.dayOverrides.containsKey(key), isFalse);
    expect(back.daySnapshots[key]!.isOverridden, isFalse);
    expect(back.daySnapshots[key]!.planId, PlanDefaults.holidayId);
    expect(SummaryModel.forDay(back, now, now).planName, '节假日');
  });

  test('新建的第三张表在汇总里可见（旧 blocksForMode 会当成工作日表）', () {
    const extra = Plan(
      id: 'plan_exam',
      name: '备考日',
      repeat: RepeatRule(kind: RepeatKind.dates),
    );
    final d = booted()
        .withPlans([...booted().plans, extra])
        .assignDay(key, extra.id, at: at);
    expect(SummaryModel.forDay(d, now, now).planName, '备考日');
    expect(d.forDate(now).planName, '备考日');
  });

  test('删表时清掉指向它的单日指派，不静默退回第一张表', () {
    const extra = Plan(
      id: 'plan_exam',
      name: '备考日',
      repeat: RepeatRule(kind: RepeatKind.dates),
    );
    final withExtra = booted()
        .withPlans([...booted().plans, extra])
        .assignDay(key, extra.id, at: at);
    expect(withExtra.dayOverrides[key], extra.id);

    final removed = withExtra.withPlans([
      ...withExtra.plans.where((p) => p.id != extra.id),
    ]);
    expect(removed.dayOverrides.containsKey(key), isFalse);
    expect(removed.forDate(now).planId, PlanDefaults.holidayId);
  });

  test('改判审计能随 JSON 往返，且序列化幂等', () {
    final d = booted().assignDay(key, PlanDefaults.workdayId, at: at);
    final restored = AppData.fromJson(d.toJson());
    expect(restored.daySnapshots[key]!.autoPlanId, PlanDefaults.holidayId);
    expect(restored.daySnapshots[key]!.overriddenAt, at);
    expect(restored.toJson(), d.toJson());
  });

  test('日历指派历史某一天不影响今天', () {
    final yesterday = DateTime(2026, 11, 6);
    final d = booted().assignDay(
      TimeMath.dateKey(yesterday),
      PlanDefaults.workdayId,
      at: at,
    );
    expect(d.forDate(now).planId, PlanDefaults.holidayId);
    expect(d.forDate(yesterday).planId, PlanDefaults.workdayId);
    expect(SummaryModel.forDay(d, yesterday, now).planName, '工作日');
  });
}
