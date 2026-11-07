import 'day_mode.dart';

/// 周期类型。允许值只能是这三个，别自己加。
enum CycleType {
  none('none'),
  bigSmallWeek('big_small_week'),
  singleDayOff('single_day_off');

  const CycleType(this.key);

  final String key;

  static CycleType fromKey(Object? key) => CycleType.values.firstWhere(
    (t) => t.key == key,
    orElse: () => CycleType.none,
  );
}

/// 周期性周规则（R2）。
class CycleRule {
  const CycleRule({
    this.type = CycleType.none,
    this.anchorDate,
    this.anchorIsBig = true,
  });

  final CycleType type;

  /// 「那一周的周一」，绝对日期。
  ///
  /// 绝不能存「本周是大周」这种相对标志 —— 下周打开时"本周"已经变了，
  /// 它会永远返回大周，隔周交替彻底失效。见需求文档「陷阱一」。
  final DateTime? anchorDate;

  final bool anchorIsBig;

  factory CycleRule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CycleRule();
    final raw = json['anchorDate'];
    return CycleRule(
      type: CycleType.fromKey(json['type']),
      anchorDate: raw is String ? DateTime.tryParse(raw) : null,
      anchorIsBig: json['anchorIsBig'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.key,
    if (anchorDate != null) 'anchorDate': CalendarRules.dateKey(anchorDate!),
    'anchorIsBig': anchorIsBig,
  };
}

/// 今天用了哪套表，以及为什么 —— 界面上要显示来源，否则这套规则就是黑盒。
class ResolvedDay {
  const ResolvedDay(this.mode, this.source);

  final DayMode mode;

  /// 例如「按星期几」「单日例外」「周期规则」。
  final String source;

  String get label => '${mode.label}（$source）';
}

/// 日历规则栈：R0 单日例外 → R1 法定节假日/调休 → R2 周期 → R3 星期几。
/// 第一个命中的决定今天用工作日表还是节假日表。
class CalendarRules {
  CalendarRules({
    Map<String, DayMode>? overrides,
    Map<String, DayMode>? specialDates,
    CycleRule? cycle,
    Map<int, DayMode>? weekdayDefault,
  }) : overrides = overrides ?? {},
       specialDates = specialDates ?? {},
       cycle = cycle ?? const CycleRule(),
       weekdayDefault = weekdayDefault ?? _defaultWeekday;

  /// 单日例外，键是 `2026-11-07`。优先级最高。
  final Map<String, DayMode> overrides;

  /// 法定节假日 / 调休上班日。
  final Map<String, DayMode> specialDates;

  final CycleRule cycle;

  /// 星期几默认，键是 DateTime.weekday（1=周一 … 7=周日）。
  final Map<int, DayMode> weekdayDefault;

  static const Map<int, DayMode> _defaultWeekday = {
    DateTime.monday: DayMode.workday,
    DateTime.tuesday: DayMode.workday,
    DateTime.wednesday: DayMode.workday,
    DateTime.thursday: DayMode.workday,
    DateTime.friday: DayMode.workday,
    DateTime.saturday: DayMode.holiday,
    DateTime.sunday: DayMode.holiday,
  };

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 判定今天用哪套表，并带上来源。**不查 daySnapshots** —— 快照只用于历史统计。
  ResolvedDay resolve(DateTime date) {
    final key = dateKey(date);

    final r0 = overrides[key];
    if (r0 != null) return ResolvedDay(r0, '单日例外');

    final r1 = specialDates[key];
    if (r1 != null) return ResolvedDay(r1, '节假日表');

    final r2 = _cycleMode(date);
    if (r2 != null) return ResolvedDay(r2, '周期规则');

    final r3 = weekdayDefault[date.weekday];
    if (r3 != null) return ResolvedDay(r3, '按星期几');

    return const ResolvedDay(DayMode.workday, '按星期几');
  }

  /// R2。返回 null 表示"这一层不管，交给 R3"。
  ///
  /// 注意：周六一旦启用大小周就必须给出确定答案。
  /// 若写成"小周的周六不返回，落到 weekdayDefault"，只要用户把
  /// weekdayDefault.sat 改成 workday，大小周就静默失效了。
  DayMode? _cycleMode(DateTime date) {
    switch (cycle.type) {
      case CycleType.none:
        return null;
      case CycleType.bigSmallWeek:
        if (date.weekday == DateTime.saturday) {
          return isBigWeek(date) ? DayMode.workday : DayMode.holiday;
        }
        if (date.weekday == DateTime.sunday) return DayMode.holiday;
        return null;
      case CycleType.singleDayOff:
        if (date.weekday == DateTime.sunday) return DayMode.holiday;
        return DayMode.workday;
    }
  }

  /// 这一周是不是大周。隔周交替，锚点是绝对日期。
  bool isBigWeek(DateTime date) {
    final anchor = cycle.anchorDate;
    if (anchor == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final anchorMonday = DateTime(anchor.year, anchor.month, anchor.day);
    final weeks = (monday.difference(anchorMonday).inDays / 7).round();
    return (weeks % 2 == 0) == cycle.anchorIsBig;
  }

  factory CalendarRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CalendarRules();
    Map<String, DayMode> parseMap(Object? raw) {
      final out = <String, DayMode>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          final mode = DayMode.tryFromKey(v);
          if (mode != null) out[k.toString()] = mode;
        });
      }
      return out;
    }

    final wd = <int, DayMode>{..._defaultWeekday};
    final rawWd = json['weekdayDefault'];
    if (rawWd is Map) {
      const names = {
        'mon': 1,
        'tue': 2,
        'wed': 3,
        'thu': 4,
        'fri': 5,
        'sat': 6,
        'sun': 7,
      };
      rawWd.forEach((k, v) {
        final idx = names[k.toString()];
        final mode = DayMode.tryFromKey(v);
        if (idx != null && mode != null) wd[idx] = mode;
      });
    }

    return CalendarRules(
      overrides: parseMap(json['overrides']),
      specialDates: parseMap(json['specialDates']),
      cycle: CycleRule.fromJson(json['cycle'] as Map<String, dynamic>?),
      weekdayDefault: wd,
    );
  }

  Map<String, dynamic> toJson() => {
    'overrides': {for (final e in overrides.entries) e.key: e.value.key},
    'specialDates': {for (final e in specialDates.entries) e.key: e.value.key},
    'cycle': cycle.toJson(),
    'weekdayDefault': {
      'mon': weekdayDefault[DateTime.monday]!.key,
      'tue': weekdayDefault[DateTime.tuesday]!.key,
      'wed': weekdayDefault[DateTime.wednesday]!.key,
      'thu': weekdayDefault[DateTime.thursday]!.key,
      'fri': weekdayDefault[DateTime.friday]!.key,
      'sat': weekdayDefault[DateTime.saturday]!.key,
      'sun': weekdayDefault[DateTime.sunday]!.key,
    },
  };
}
