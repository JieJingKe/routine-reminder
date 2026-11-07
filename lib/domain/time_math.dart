import 'category.dart';
import 'day_block.dart';

/// 一段连续时间，单位是分钟，区间左闭右开 [start, end)。
class MinuteRange {
  const MinuteRange(this.start, this.end);

  final int start;
  final int end;

  int get minutes => end - start;

  bool contains(int minute) => minute >= start && minute < end;

  @override
  String toString() => '[$start, $end)';
}

/// 时间换算与作息计算。纯函数，不依赖 Flutter，可单独跑测试。
abstract final class TimeMath {
  /// 一天 1440 分钟。所有百分比的分母都是它，未安排也计入。
  static const int minutesPerDay = 1440;

  /// 一天的起点是 23:00，不是 00:00。见交接文档硬规则 #7。
  ///
  /// 排序、时间轴刻度、跨零点判定全都依赖这一条：人是躺下就睡觉的，
  /// 一天从睡前开始，而不是从零点开始。
  static const int dayStartMinute = 23 * 60;

  /// `2026-11-05`。记录、快照、导出的键统一用它，避免各处自己拼格式。
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${_two(d.month)}-${_two(d.day)}';

  /// `"07:30"` → `450`。格式不合法直接抛错，不猜。
  static int parseHm(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      throw FormatException('时间必须是 HH:mm 格式', value);
    }
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw FormatException('时间必须是 HH:mm 格式', value);
    }
    return h * 60 + m;
  }

  /// `450` → `"07:30"`。超过 1440 的分钟数按 24 小时取模（跨零点那一段）。
  static String formatHm(int minute) {
    final m = ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay;
    final h = m ~/ 60;
    return '${_two(h)}:${_two(m % 60)}';
  }

  /// `1350` → `"22h30m"`，`45` → `"45m"`，`120` → `"2h"`。
  static String formatDuration(int minutes) {
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h${_two(m)}m';
  }

  /// `1350` → `"22 小时 30 分"`。给文案用，不用于环中心的紧凑数字。
  static String formatDurationCn(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m 分钟';
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分';
  }

  /// 一天里所有没被块占用的时间。
  ///
  /// 关键点：跨零点的块（23:00–07:00）必须两半都算占用 —— 右端 [1380,1440)
  /// 和左端 [0,420)。只算一半会让后半夜被误判成"空档"，
  /// 环上会画出一段根本不存在的斜纹，而且中心数字会和环对不上。
  static List<MinuteRange> gaps(List<DayBlock> blocks) {
    final marks = <MinuteRange>[];
    for (final b in blocks) {
      if (b.start < minutesPerDay) {
        marks.add(MinuteRange(b.start, b.end.clamp(0, minutesPerDay)));
      }
      if (b.end > minutesPerDay) {
        marks.add(
          MinuteRange(0, (b.end - minutesPerDay).clamp(0, minutesPerDay)),
        );
      }
    }
    marks.sort((a, b) => a.start.compareTo(b.start));

    final out = <MinuteRange>[];
    var cursor = 0;
    for (final m in marks) {
      if (m.start > cursor) out.add(MinuteRange(cursor, m.start));
      if (m.end > cursor) cursor = m.end;
    }
    if (cursor < minutesPerDay) out.add(MinuteRange(cursor, minutesPerDay));
    return wherePositive(out);
  }

  static List<MinuteRange> wherePositive(List<MinuteRange> ranges) =>
      ranges.where((r) => r.minutes > 0).toList(growable: false);

  /// 某一分钟正在进行的块。跨零点块的左半边（凌晨那段）也能命中。
  static DayBlock? blockAt(List<DayBlock> blocks, int minute) {
    for (final b in blocks) {
      if (minute >= b.start && minute < b.end) return b;
      if (b.end > minutesPerDay && minute < b.end - minutesPerDay) return b;
    }
    return null;
  }

  /// 下一块（按 23:00 起点的顺序往后找第一块的开始）。
  static DayBlock? nextAfter(List<DayBlock> blocks, int minute) {
    final sorted = [...blocks]
      ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    for (final b in sorted) {
      final start = b.start >= dayStartMinute
          ? b.start - minutesPerDay
          : b.start;
      final now = minute >= dayStartMinute ? minute - minutesPerDay : minute;
      if (start > now) return b;
    }
    return sorted.isEmpty ? null : sorted.first;
  }

  /// 排序键：以 23:00 为一天起点，23:00 之后的块排在最后。
  static int sortKey(DayBlock b) =>
      b.start >= dayStartMinute ? b.start - minutesPerDay : b.start;

  /// 按 23:00 起点排序后的新列表。
  static List<DayBlock> sorted(List<DayBlock> blocks) =>
      [...blocks]..sort((a, b) => sortKey(a).compareTo(sortKey(b)));

  /// 某分类在一组块里占用的总分钟数（跨零点块按整段算，不分天）。
  static int minutesOf(List<DayBlock> blocks, Category category) => blocks
      .where((b) => b.category == category)
      .fold(0, (sum, b) => sum + b.duration);

  /// 已安排的总分钟数（可能超过 1440，若数据里有重叠）。
  static int scheduledMinutes(List<DayBlock> blocks) =>
      blocks.fold(0, (sum, b) => sum + b.duration);

  /// 未安排的总分钟数。
  static int unplannedMinutes(List<DayBlock> blocks) =>
      gaps(blocks).fold(0, (sum, g) => sum + g.minutes);

  static String _two(int v) => v.toString().padLeft(2, '0');
}
