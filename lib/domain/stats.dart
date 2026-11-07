import 'category.dart';
import 'day_block.dart';
import 'time_math.dart';

/// 一天的汇总。所有数字都从块算出来，不接受外部传入，
/// 避免"环上画着一套、卡片上写着另一套"。
class DayTotals {
  const DayTotals({
    required this.scheduled,
    required this.unplanned,
    required this.byCategory,
  });

  factory DayTotals.of(List<DayBlock> blocks) {
    final byCat = <Category, int>{for (final c in Category.values) c: 0};
    for (final b in blocks) {
      byCat[b.category] = (byCat[b.category] ?? 0) + b.duration;
    }
    return DayTotals(
      scheduled: TimeMath.scheduledMinutes(blocks),
      unplanned: TimeMath.unplannedMinutes(blocks),
      byCategory: byCat,
    );
  }

  final int scheduled;
  final int unplanned;
  final Map<Category, int> byCategory;

  int minutesOf(Category c) => byCategory[c] ?? 0;
}

/// 一段时间的累计。只做加法，不设分母，不产生百分比。
///
/// 「不设达标线」是产品原则：一旦出现"目标 90 分钟 / 完成 60%"，这个应用
/// 就从"让我看见"变成"给我打分"，而现在没有"完成"这个概念。
class PeriodTotals {
  const PeriodTotals({required this.byCategory, required this.dayCount});

  factory PeriodTotals.of(Iterable<List<DayBlock>> days) {
    final byCat = <Category, int>{for (final c in Category.values) c: 0};
    var count = 0;
    for (final day in days) {
      count++;
      for (final b in day) {
        byCat[b.category] = (byCat[b.category] ?? 0) + b.duration;
      }
    }
    return PeriodTotals(byCategory: byCat, dayCount: count);
  }

  final Map<Category, int> byCategory;

  /// 参与累计的天数。第一周只有几天时，文案要说明是几天，否则数字会骗人。
  final int dayCount;

  int minutesOf(Category c) => byCategory[c] ?? 0;
}
