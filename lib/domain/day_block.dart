import 'category.dart';
import 'time_math.dart';

/// 一个作息块。坐标是「当天的分钟数」，不是绝对时间。
///
/// 跨零点用 `end > 1440` 表示：23:00–07:00 存成 `start=1380, end=1860`。
/// 不这么存的话，"这一段到底是 8 小时还是负 16 小时"在每个用到它的地方都要重新判断一遍，
/// 早晚会有一处判错 —— 而且不会报错。
class DayBlock {
  const DayBlock({
    required this.start,
    required this.end,
    required this.name,
    required this.category,
    this.remind = false,
  }) : assert(end > start, '块的结束必须晚于开始；跨零点请在构造前换算成 1440+');

  final int start;
  final int end;
  final String name;
  final Category category;

  /// 这一块的起点是否提醒。V1 只做「整点提醒」的开关，不做块内多次提醒。
  final bool remind;

  int get duration => end - start;

  bool get crossesMidnight => end > TimeMath.minutesPerDay;

  /// 这一块在 24 小时轴上覆盖的区间列表。
  /// 跨零点的块返回两段：右端 [start,1440) 与左端 [0,end-1440)。
  List<MinuteRange> get occupiedRanges {
    if (!crossesMidnight) return [MinuteRange(start, end)];
    return [
      MinuteRange(start, TimeMath.minutesPerDay),
      MinuteRange(0, end - TimeMath.minutesPerDay),
    ];
  }

  /// 环上"这一段落在哪一圈、起止多少"。
  ///
  /// 内圈管 00:00–12:00（0–720），外圈管 12:00–24:00（720–1440）。
  /// 跨零点的块会同时落在内圈两端，必须画成两块同色。
  List<RingPiece> ringPieces() {
    final list = <RingPiece>[];
    void add(int a, int c, RingSide side) {
      if (c > a) list.add(RingPiece(a, c, side));
    }

    if (start < 720) add(start, end.clamp(0, 720), RingSide.inner);
    if (end > 720) {
      add(start.clamp(720, 1440), end.clamp(720, 1440), RingSide.outer);
    }
    if (end > 1440) add(0, end - 1440, RingSide.inner);
    return list;
  }

  DayBlock copyWith({
    int? start,
    int? end,
    String? name,
    Category? category,
    bool? remind,
  }) => DayBlock(
    start: start ?? this.start,
    end: end ?? this.end,
    name: name ?? this.name,
    category: category ?? this.category,
    remind: remind ?? this.remind,
  );

  /// 从 JSON 读。`end <= start` 一律按跨零点处理（23:00–07:00）。
  factory DayBlock.fromJson(Map<String, dynamic> json) {
    final s = TimeMath.parseHm(json['start'] as String);
    final rawEnd = TimeMath.parseHm(json['end'] as String);
    final e = rawEnd <= s ? rawEnd + TimeMath.minutesPerDay : rawEnd;
    final cat = Category.tryFromKey(json['category']);
    if (cat == null) {
      throw FormatException('作息块分类非法：${json['category']}', json);
    }
    return DayBlock(
      start: s,
      end: e,
      name: (json['name'] as String?)?.trim() ?? cat.label,
      category: cat,
      // 新建/读盘默认不响铃。一天十几个通知会让人开始无意识关掉，
      // 最后连下班、锻炼这种真正重要的提醒也一起被无视。
      remind: json['remind'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': TimeMath.formatHm(start),
    'end': TimeMath.formatHm(end),
    'name': name,
    'category': category.key,
    'remind': remind,
  };

  @override
  String toString() =>
      'DayBlock(${TimeMath.formatHm(start)}–${TimeMath.formatHm(end)} $name/${category.key})';
}

/// 环的内外圈。内圈 00–12，外圈 12–24。
enum RingSide { inner, outer }

/// 一段落在某一圈上的弧，区间是 [from, to)，单位分钟（0–720 或 720–1440）。
class RingPiece {
  const RingPiece(this.from, this.to, this.side);

  final int from;
  final int to;
  final RingSide side;
}
