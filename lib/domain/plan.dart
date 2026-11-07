import 'calendar_rules.dart';
import 'day_block.dart';
import 'day_mode.dart';
import 'reminder.dart';

/// 迁移出来的两张默认表用的固定 id。
///
/// 固定而不是随机生成：`withSchedule(DayMode)` 兼容入口、旧快照的
/// `mode → planId` 换算、以及 #9 的编辑目标都要靠它认表。
abstract final class PlanDefaults {
  static const String workdayId = 'plan_workday';
  static const String holidayId = 'plan_holiday';
  static const String workdayName = '工作日';
  static const String holidayName = '节假日';
}

/// 重复规则四选一（交接文档第 4 节已批准，别再加第五种）。
///
/// 「每天遵从」= daily；「特殊日期遵从」= dates（或任意类型里的 dates 附加日）。
/// weekly / cycle 是闹钟习惯里的「按星期几」「隔周」。
enum RepeatKind {
  daily('daily', '每天'),
  weekly('weekly', '按星期几'),
  cycle('cycle', '周期规则'),
  dates('dates', '指定日期');

  const RepeatKind(this.key, this.label);

  final String key;
  final String label;

  static RepeatKind fromKey(Object? key) => RepeatKind.values.firstWhere(
    (k) => k.key == key,
    orElse: () => RepeatKind.daily,
  );
}

/// 一张计划表「在哪些日子生效」。
///
/// 判定分两层，由 `AppData.forDate` 按顺序调用：
/// - [matchesSpecial]：这张表自己维护的特殊日期，优先级高于所有常规重复；
/// - [matchesRegular]：四选一的常规重复。
///
/// 这样「只在特殊日期遵从」和「每天遵从，但某几天另算」都能表达，
/// 且不会让全局规则栈重新变成多计划表的上帝对象。
class RepeatRule {
  const RepeatRule({
    this.kind = RepeatKind.daily,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.cycle = const CycleRule(),
    this.cycleBigWeek = true,
    this.dates = const <String>{},
  });

  final RepeatKind kind;

  /// DateTime.weekday：1=周一 … 7=周日。weekly 与 cycle 都读它。
  final Set<int> weekdays;

  /// cycle 类型用的绝对锚点（大小周 / 单休）。
  final CycleRule cycle;

  /// cycle 且大小周时：这张表在大周生效(true)还是小周生效(false)。
  /// 迁移后的工作日表是 true，节假日表是 false。
  final bool cycleBigWeek;

  /// 本表自己维护的特殊日期，格式 `YYYY-MM-DD`。
  /// 不共享全局 specialDates —— 两张表可以各自圈不同的日子。
  final Set<String> dates;

  String get sourceLabel => kind.label;

  /// 管理面板 / 表选择器里的一行摘要。写清楚「什么时候生效」，
  /// 比只显示一个「按星期几」更容易在 N 张表里找到目标。
  String get summary {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    switch (kind) {
      case RepeatKind.daily:
        return '每天';
      case RepeatKind.weekly:
        final wd = weekdays.toList()..sort();
        if (wd.isEmpty) return '按星期几（未选）';
        if (wd.length == 7) return '每天';
        return '每周 ${wd.map((w) => names[w - 1]).join(' ')}';
      case RepeatKind.cycle:
        return switch (cycle.type) {
          CycleType.none => '周期规则（未设置）',
          CycleType.bigSmallWeek => cycleBigWeek ? '大小周 · 大周' : '大小周 · 小周',
          CycleType.singleDayOff => '单休',
        };
      case RepeatKind.dates:
        return dates.isEmpty ? '仅指定日期（未选）' : '仅指定日期 · ${dates.length} 天';
    }
  }

  bool matchesSpecial(DateTime date) =>
      dates.contains(CalendarRules.dateKey(date));

  bool matchesRegular(DateTime date) {
    switch (kind) {
      case RepeatKind.daily:
        return true;
      case RepeatKind.weekly:
        return weekdays.contains(date.weekday);
      case RepeatKind.cycle:
        if (!weekdays.contains(date.weekday)) return false;
        // 大小周只改写「周六」的归属；周日与周一至周五必须照常，
        // 否则「小周表」会在大周的周日凭空消失（旧规则栈踩过这个坑）。
        if (cycle.type != CycleType.bigSmallWeek) return true;
        if (date.weekday != DateTime.saturday) return true;
        return CalendarRules(cycle: cycle).isBigWeek(date) == cycleBigWeek;
      case RepeatKind.dates:
        // 只靠 matchesSpecial，常规层一律不命中。
        return false;
    }
  }

  RepeatRule copyWith({
    RepeatKind? kind,
    Set<int>? weekdays,
    CycleRule? cycle,
    bool? cycleBigWeek,
    Set<String>? dates,
  }) => RepeatRule(
    kind: kind ?? this.kind,
    weekdays: weekdays ?? this.weekdays,
    cycle: cycle ?? this.cycle,
    cycleBigWeek: cycleBigWeek ?? this.cycleBigWeek,
    dates: dates ?? this.dates,
  );

  factory RepeatRule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RepeatRule();
    Set<int> parseInts(Object? raw) =>
        (raw is List) ? raw.whereType<int>().toSet() : const <int>{};
    Set<String> parseDates(Object? raw) =>
        (raw is List) ? raw.whereType<String>().toSet() : const <String>{};
    return RepeatRule(
      kind: RepeatKind.fromKey(json['kind']),
      weekdays: parseInts(json['weekdays']),
      cycle: CycleRule.fromJson(json['cycle'] as Map<String, dynamic>?),
      cycleBigWeek: json['cycleBigWeek'] as bool? ?? true,
      dates: parseDates(json['dates']),
    );
  }

  Map<String, dynamic> toJson() {
    // 集合必须排序后落盘，否则同一份数据两次 toJson 的键顺序可能不同，
    // 迁移的幂等断言与 `.tmp → rename` 的字节比对都会假失败。
    final wd = weekdays.toList()..sort();
    final ds = dates.toList()..sort();
    return {
      'kind': kind.key,
      'weekdays': wd,
      'cycle': cycle.toJson(),
      'cycleBigWeek': cycleBigWeek,
      'dates': ds,
    };
  }
}

/// 一张计划表。列表顺序 = 同日冲突优先级（first match wins）。
class Plan {
  const Plan({
    required this.id,
    required this.name,
    this.blocks = const <DayBlock>[],
    this.reminders = const <Reminder>[],
    this.repeat = const RepeatRule(),
    this.legacyMode,
  });

  final String id;
  final String name;
  final List<DayBlock> blocks;
  final List<Reminder> reminders;
  final RepeatRule repeat;

  /// 迁移出来的两张旧表才带这个标记，供 `blocksForMode(DayMode)` 等兼容入口
  /// 与「工作日 / 节假日」文案使用。用户新建的表为 null。
  final DayMode? legacyMode;

  /// 顶栏 / 汇总显示的「今天用哪套表」。
  DayMode get displayMode => legacyMode ?? DayMode.workday;

  Plan copyWith({
    String? id,
    String? name,
    List<DayBlock>? blocks,
    List<Reminder>? reminders,
    RepeatRule? repeat,
    DayMode? legacyMode,
  }) => Plan(
    id: id ?? this.id,
    name: name ?? this.name,
    blocks: blocks ?? this.blocks,
    reminders: reminders ?? this.reminders,
    repeat: repeat ?? this.repeat,
    legacyMode: legacyMode ?? this.legacyMode,
  );

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名',
    blocks: (json['blocks'] is List)
        ? (json['blocks'] as List)
              .whereType<Map>()
              .map((e) => DayBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const <DayBlock>[],
    reminders: (json['reminders'] is List)
        ? (json['reminders'] as List)
              .whereType<Map>()
              .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const <Reminder>[],
    repeat: RepeatRule.fromJson(json['repeat'] as Map<String, dynamic>?),
    legacyMode: DayMode.tryFromKey(json['legacyMode']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (legacyMode != null) 'legacyMode': legacyMode!.key,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
    'repeat': repeat.toJson(),
  };
}
