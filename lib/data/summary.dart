import '../domain/actual_records.dart';
import '../domain/category.dart';
import '../domain/day_block.dart';
import '../domain/day_mode.dart';
import '../domain/stats.dart';
import '../domain/time_math.dart';
import 'app_data.dart';

/// 汇总周期。三种周期用三种**不同**的图形，见需求「L3 汇总」。
enum SummaryPeriod {
  day('今天', '日'),
  week('本周', '周'),
  month('本月', '月');

  const SummaryPeriod(this.label, this.suffix);

  final String label;
  final String suffix;
}

/// 一天的汇总。所有数字都从「计划块 + 实际分类覆盖」算出来，
/// 不接受外部传入，避免图和表各算各的。
class DaySummary {
  DaySummary({
    required this.date,
    required this.hasData,
    required this.isFuture,
    required this.mode,
    required this.source,
    required this.planName,
    required this.plan,
    required this.actual,
    required this.records,
  }) : planMinutes = DayTotals.of(plan).byCategory,
       actualMinutes = DayTotals.of(actual).byCategory;

  final DateTime date;
  final bool hasData;
  final bool isFuture;
  final DayMode mode;
  final String source;

  /// 这天实际按哪张表度过。多计划表之后不能再用「工作日 / 节假日」
  /// 两个枚举概括 —— 用户新建的第三张表也得有名字。
  final String planName;
  final List<DayBlock> plan;
  final List<DayBlock> actual;

  final Map<String, dynamic> records;

  final Map<Category, int> planMinutes;
  final Map<Category, int> actualMinutes;

  String get dateKey => TimeMath.dateKey(date);

  int deviation(Category c) => (actualMinutes[c] ?? 0) - (planMinutes[c] ?? 0);

  /// 日历热图的亮度来源：当天「学习 + 锻炼」的实际分钟数。
  int get focusMinutes =>
      (actualMinutes[Category.study] ?? 0) +
      (actualMinutes[Category.exercise] ?? 0);

  /// 这一天的纠偏段数。0 表示两环完全一致（这是正确行为，不是渲染 bug）。
  int get overrideCount => plan
      .where((b) => ActualRecords.overrideOf(records, dateKey, b.start) != null)
      .length;

  int get unplannedMinutes => TimeMath.unplannedMinutes(plan);
}

/// 汇总数据的唯一计算入口。纯 Dart，不碰 Flutter，可单独跑单元测试。
abstract final class SummaryModel {
  /// 该周期覆盖的所有日期。周从周一开始，月从 1 号到月末。
  static List<DateTime> datesOf(SummaryPeriod period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      SummaryPeriod.day => [today],
      SummaryPeriod.week => [
        for (var i = 0; i < 7; i++)
          today
              .subtract(Duration(days: today.weekday - 1))
              .add(Duration(days: i)),
      ],
      SummaryPeriod.month => [
        for (var d = 1; d <= DateTime(now.year, now.month + 1, 0).day; d++)
          DateTime(now.year, now.month, d),
      ],
    };
  }

  static List<DaySummary> range(
    AppData data,
    SummaryPeriod period,
    DateTime now,
  ) => [for (final d in datesOf(period, now)) forDay(data, d, now)];

  static DaySummary forDay(AppData data, DateTime date, DateTime now) {
    final key = TimeMath.dateKey(date);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final isFuture = day.isAfter(today);

    // 数据从安装当天开始累积。今天即使快照还没写进来也算有数据，
    // 否则刚装好的那一下会显示一个刺眼的「无数据」。
    final snapshot = data.daySnapshots[key];
    final hasData = isFuture ? false : (day == today || snapshot != null);

    // 判定统一到 forDate —— 旧实现读 rules.resolve + blocksForMode(mode)，
    // 只能认两张 legacy 表，用户新建的第三张在汇总里会被当成工作日表。
    // 历史日优先按当天快照认表（快照由 assignDay 在改判时同步刷新），
    // 快照指向的表若已被删除，才回退到当前规则重新解析。
    final resolved = data.forDate(date);
    final snapId = snapshot?.planId;
    final snapPlan = snapId == null ? null : data.planById(snapId);
    final mode = snapshot?.mode ?? resolved.mode;
    final source = snapshot?.source ?? resolved.source;
    final planName = snapPlan?.name ?? resolved.planName;
    final plan = snapPlan?.blocks ?? resolved.blocks;
    final actual = ActualRecords.actualBlocks(plan, data.records, key);

    return DaySummary(
      date: day,
      hasData: hasData,
      isFuture: isFuture,
      mode: mode,
      source: source,
      planName: planName,
      plan: plan,
      actual: actual,
      records: data.records,
    );
  }

  /// 历史日用的是**当前这套表**的计划值，不是当时的历史快照。
  ///
  /// V1 只存「那天用哪套表」不存「那天那套表长什么样」—— 存全量快照会让
  /// 数据文件每天膨胀一份。代价是：你今天改了作息表，上个月的「计划」列会
  /// 跟着变。写在导出文件里，免得读的人以为数据会自己回填。
  static const String historicalCaveat =
      '历史日期的「计划」按当前这套表计算（未存历史快照），改动作息表会追溯影响历史列。';
}

/// 导出文件名。`作息分析-2026-11-05-日.md` / `作息分析-2026-11.md`。
String reportFileName(DateTime now, SummaryPeriod period) => switch (period) {
  SummaryPeriod.day ||
  SummaryPeriod.week => '作息分析-${TimeMath.dateKey(now)}-${period.suffix}.md',
  SummaryPeriod.month =>
    '作息分析-${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}.md',
};

/// 导出 MD 的内容生成器。纯函数：测试里直接比字符串，不用碰文件系统。
///
/// 目的不是存档，是**给 AI 看出偏差模式**，所以第 4、5 项才是重点。
String buildMarkdown({
  required AppData data,
  required DateTime now,
  required SummaryPeriod period,
}) {
  final days = SummaryModel.range(data, period, now);
  final dates = SummaryModel.datesOf(period, now);
  final today = SummaryModel.forDay(data, now, now);
  final buf = StringBuffer();

  String stamp(DateTime d) =>
      '${TimeMath.dateKey(d)} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  String hm(int m) => TimeMath.formatDurationCn(m);

  // ---- 1. 元信息 ----
  buf.writeln('# 作息分析 · ${period.label}');
  buf.writeln();
  buf.writeln('## 1. 元信息');
  buf.writeln();
  buf.writeln('- 导出时间：${stamp(now)}');
  buf.writeln(
    '- 统计周期：${period.label}（${TimeMath.dateKey(dates.first)}'
    ' 至 ${TimeMath.dateKey(dates.last)}，共 ${dates.length} 天）',
  );
  buf.writeln('- 今天生效的表：${today.planName}（${today.source}）');
  final withData = days.where((d) => d.hasData).length;
  buf.writeln(
    '- 有数据 $withData 天，无数据 ${days.length - withData} 天'
    '（安装之前与未来日期不生成、不补录）',
  );
  buf.writeln('- ${SummaryModel.historicalCaveat}');
  buf.writeln();

  // ---- 2. 当前计划表 ----
  buf.writeln('## 2. 当前计划表（${today.planName}）');
  buf.writeln();
  buf.writeln('| 开始 | 结束 | 名称 | 分类 | 提醒 |');
  buf.writeln('|---|---|---|---|---|');
  for (final b in TimeMath.sorted(today.plan)) {
    buf.writeln(
      '| ${TimeMath.formatHm(b.start)} | ${TimeMath.formatHm(b.end)}'
      '${b.crossesMidnight ? '（次日）' : ''} | ${b.name} | ${b.category.label} |'
      ' ${b.remind ? '开' : '关'} |',
    );
  }
  buf.writeln();

  // ---- 3. 计划时间分配（分母固定 24 小时）----
  buf.writeln('## 3. 计划时间分配（分母固定 24 小时 = 1440 分钟）');
  buf.writeln();
  buf.writeln('| 分类 | 分钟 | 时长 | 占全天 |');
  buf.writeln('|---|---:|---|---:|');
  for (final c in Category.values) {
    final m = today.planMinutes[c] ?? 0;
    buf.writeln(
      '| ${c.label} | $m | ${hm(m)} |'
      ' ${(m / TimeMath.minutesPerDay * 100).toStringAsFixed(1)}% |',
    );
  }
  final unplanned = today.unplannedMinutes;
  buf.writeln(
    '| 未安排 | $unplanned | ${hm(unplanned)} |'
    ' ${(unplanned / TimeMath.minutesPerDay * 100).toStringAsFixed(1)}% |',
  );
  buf.writeln(
    '| **合计** | **${TimeMath.minutesPerDay}** | **24 小时** | **100.0%** |',
  );
  buf.writeln();

  // ---- 4. 计划 vs 实际 / 每日明细 ----
  buf.writeln('## 4. 计划 vs 实际 · 每日明细');
  buf.writeln();
  buf.writeln('偏差 = 实际 − 计划。正数表示这一类实际花得更多。');
  buf.writeln();
  for (final d in days) {
    final label = '${TimeMath.dateKey(d.date)}（${_weekday(d.date)}）';
    if (!d.hasData) {
      buf.writeln('### $label · 无数据');
      buf.writeln();
      buf.writeln(d.isFuture ? '未来日期，尚无记录。' : '安装之前，无记录。');
      buf.writeln();
      continue;
    }
    buf.writeln('### $label · ${d.planName}（${d.source}）');
    buf.writeln();
    buf.writeln('| 分类 | 计划 | 实际 | 偏差 |');
    buf.writeln('|---|---:|---:|---:|');
    for (final c in Category.values) {
      final p = d.planMinutes[c] ?? 0;
      final a = d.actualMinutes[c] ?? 0;
      final diff = a - p;
      buf.writeln(
        '| ${c.label} | $p | $a |'
        ' ${diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff')} |',
      );
    }
    buf.writeln();
    buf.writeln('- 学习 + 锻炼（实际）：${hm(d.focusMinutes)}');
    buf.writeln(
      '- 纠偏段数：${d.overrideCount}'
      '${d.overrideCount == 0 ? '（未纠偏，计划与实际完全一致）' : ''}',
    );
    buf.writeln();
  }

  // ---- 5. 给 AI 的提示 ----
  buf.writeln('## 5. 给 AI 的分析提示');
  buf.writeln();
  buf.writeln(
    '> 请重点看偏差集中在哪些分类、学习与锻炼的连续性和日均水平，'
    '不要只看总时长。',
  );
  buf.writeln();
  return buf.toString();
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
