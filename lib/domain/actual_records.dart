import 'category.dart';
import 'day_block.dart';
import 'time_math.dart';

/// 执行记录（纠偏）。
///
/// 数据结构刻意做得很小：
/// ```
/// records = {
///   "2026-11-05": { "overrides": { "1140": "leisure" } }
/// }
/// ```
/// key 是**作息块的起点分钟数**，value 是那一刻实际在做的分类。
/// 需求规定纠偏「只改当前所在这一段时间块」，所以不需要记时间段，
/// 也不需要处理块的拆分 —— 计划块的边界不动，只换分类。
///
/// 没有记录的日子，"实际"就等于"计划"。L3 的双环会完全重合，
/// **这是正确行为，不是渲染 bug**：重合本身就是"今天一分钟都没纠"的信息。
abstract final class ActualRecords {
  static const String _overridesKey = 'overrides';

  static Map<String, dynamic> _day(
    Map<String, dynamic> records,
    String dateKey,
  ) =>
      (records[dateKey] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};

  static Category? overrideOf(
    Map<String, dynamic> records,
    String dateKey,
    int blockStart,
  ) {
    final raw = _day(records, dateKey)[_overridesKey];
    if (raw is! Map) return null;
    return Category.tryFromKey(raw['$blockStart']);
  }

  static bool hasAny(Map<String, dynamic> records, String dateKey) =>
      (_day(records, dateKey)[_overridesKey] is Map) &&
      (_day(records, dateKey)[_overridesKey] as Map).isNotEmpty;

  /// 记一次纠偏。返回新的 records（原对象不动，方便 setState 比较）。
  static Map<String, dynamic> withOverride(
    Map<String, dynamic> records,
    String dateKey,
    int blockStart,
    Category category,
  ) {
    final out = Map<String, dynamic>.from(records);
    final day = Map<String, dynamic>.from(_day(records, dateKey));
    final overrides = Map<String, dynamic>.from(
      (day[_overridesKey] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
    overrides['$blockStart'] = category.key;
    day[_overridesKey] = overrides;
    out[dateKey] = day;
    return out;
  }

  /// 某天的「实际」块列表：边界和名字全部沿用计划，只换分类。
  static List<DayBlock> actualBlocks(
    List<DayBlock> plan,
    Map<String, dynamic> records,
    String dateKey,
  ) => [
    for (final b in plan)
      b.copyWith(category: overrideOf(records, dateKey, b.start) ?? b.category),
  ];

  static int minutesOf(List<DayBlock> blocks, Category c) =>
      TimeMath.minutesOf(blocks, c);
}
