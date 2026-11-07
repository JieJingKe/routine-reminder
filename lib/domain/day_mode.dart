/// 今天用哪套表：工作日还是节假日。
///
/// 只有这两个值。不要用 `mode: "workday" | "holiday" | "bigweek"` 这类混装字段 ——
/// 「大周/小周」是判断方式，不是表的类型，混在一起以后每处都要重新理解一遍。
enum DayMode {
  workday('workday', '工作日'),
  holiday('holiday', '节假日');

  const DayMode(this.key, this.label);

  final String key;
  final String label;

  static DayMode fromKey(String key) => DayMode.values.firstWhere(
    (m) => m.key == key,
    orElse: () => throw ArgumentError('未知的表类型: $key'),
  );

  static DayMode? tryFromKey(Object? key) {
    if (key is! String) return null;
    for (final m in DayMode.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}
