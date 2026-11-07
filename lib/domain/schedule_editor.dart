import 'dart:math' as math;

import 'category.dart';
import 'day_block.dart';
import 'time_math.dart';

/// 编辑态的合法性判断全部集中在这里，UI 只负责把鼠标位置换算成分钟数。
///
/// ## 为什么用「循环 24 小时轴」
///
/// 一个作息块在存储上是 `[start, end)`，`end > 1440` 表示跨过了午夜。
/// 如果直接拿线性区间算"右边邻居是谁"，跨零点的睡眠块（`1380–1860`）
/// 就要到处写特判，而特判漏一处就会安静地算错。
///
/// 这里的做法是把 24 小时看成一个**圆**：每个块是从 `start` 顺时针走
/// `duration` 分钟的一段弧。「不重叠」就等价于任意两段弧在圆上不相交。
/// 于是「结束边界最多能拖到哪」统一变成一句话：
/// 从本块起点顺时针出发，遇到**下一个块的起点**就停。
///
/// 睡眠 23:00 的下一个块是 07:00 起床，顺时针距离正好 480 分钟，
/// 所以它的结束时间上限自动就是 `1860`。不用为跨零点写任何 if。
abstract final class ScheduleEditor {
  /// 吸附粒度。全天 288 格。
  static const int step = 5;

  /// 任何任务最短 5 分钟。
  static const int minDuration = 5;

  /// 吸附到最近的 5 分钟。所有时间值进数据层之前都要过这一道。
  static int snap(int minute) => (minute / step).round() * step;

  /// 向下吸附。新建块时不能把结束时间吸到空隙外面去。
  static int snapDown(int minute) => (minute / step).floor() * step;

  /// 向上吸附。空隙起点若不是 5 的倍数（旧数据手改过），新建块只能从
  /// 空隙内部的第一个整格开始，不能吸到空隙外面去造成重叠。
  static int snapUp(int minute) => (minute / step).ceil() * step;

  /// 从 `from` 顺时针走到 `to` 的分钟数，结果落在 [0, 1440)。
  static int _forward(int from, int to) =>
      ((to - from) % TimeMath.minutesPerDay + TimeMath.minutesPerDay) %
      TimeMath.minutesPerDay;

  /// 从 `from` 逆时针走到 `to` 的分钟数，结果落在 [0, 1440)。
  static int _backward(int from, int to) => _forward(to, from);

  static List<DayBlock> _others(List<DayBlock> blocks, int index) => [
    for (var i = 0; i < blocks.length; i++)
      if (i != index) blocks[i],
  ];

  /// 结束时间的上限：顺时针遇到的下一个块起点。
  ///
  /// 只有一个块时上限是整整一天，允许它自己跨零点。
  static int maxEnd(List<DayBlock> blocks, int index) {
    final t = blocks[index];
    final others = _others(blocks, index);
    if (others.isEmpty) return t.start + TimeMath.minutesPerDay;
    final dists = others
        .map((o) => _forward(t.start, o.start))
        .where((d) => d > 0)
        .toList();
    if (dists.isEmpty) return t.start;
    return t.start + dists.reduce(math.min);
  }

  /// 开始时间的下限：逆时针遇到的上一个块终点。
  static int minStart(List<DayBlock> blocks, int index) {
    final t = blocks[index];
    final others = _others(blocks, index);
    if (others.isEmpty) return t.end - TimeMath.minutesPerDay;
    final dists = others
        .map((o) => _backward(t.end, o.end))
        .where((d) => d > 0)
        .toList();
    if (dists.isEmpty) return t.end;
    return t.end - dists.reduce(math.min);
  }

  /// 改结束时间：开始不动。
  ///
  /// 两条钳制对应验收 #9 和 #10：
  /// - 逆时针拖过开始 → 停在 `start + 5`，继续拖数值不动、任务不翻转；
  /// - 顺时针撞到邻居 → 停在邻居起点，邻居纹丝不动（不推动、不覆盖）。
  static DayBlock withEnd(List<DayBlock> blocks, int index, int wantedEnd) {
    final t = blocks[index];
    final lo = t.start + minDuration;
    final hi = maxEnd(blocks, index);
    if (hi < lo) return t;
    final end = snap(wantedEnd).clamp(lo, hi);
    return t.copyWith(end: end);
  }

  /// 改开始时间：结束不动。钳制到上一个块终点之后、且至少留 5 分钟。
  static DayBlock withStart(List<DayBlock> blocks, int index, int wantedStart) {
    final t = blocks[index];
    // 起点必须留在当天 [0,1440) 内；结束不动，所以上限还要给时长留 5 分钟。
    final lo = minStart(blocks, index);
    final hi = math.min(t.end - minDuration, 1435);
    if (hi < lo) return t;
    final start = snap(wantedStart).clamp(lo, hi);
    return t.copyWith(start: start);
  }

  /// 整块平移：时长不变，撞到任一侧邻居就停住。
  ///
  /// `wantedStart` 是鼠标希望把起点放到哪；实际能放多少由两侧的空隙决定。
  /// 起点可能跨过 24:00，所以最后要规范化回 [0,1440)，但时长必须原样保留 ——
  /// 这就是验收 #13「拖动睡眠不在 0 点断成两个任务」的实现。
  static DayBlock movedTo(List<DayBlock> blocks, int index, int wantedStart) {
    final t = blocks[index];
    final delta = snap(
      wantedStart - t.start,
    ).clamp(minStart(blocks, index) - t.start, maxEnd(blocks, index) - t.end);
    return _normalized(t, t.start + delta, t.duration);
  }

  /// 键盘微调。`shift` 为 true 时改开始，否则改结束。
  /// 每次正好 ±5 分钟，撞到边界就原地不动（连按 10 次不会累积漂移）。
  static DayBlock nudge(
    List<DayBlock> blocks,
    int index, {
    required int direction,
    required bool shift,
  }) {
    final t = blocks[index];
    final delta = direction.sign * step;
    return shift
        ? withStart(blocks, index, t.start + delta)
        : withEnd(blocks, index, t.end + delta);
  }

  static DayBlock _normalized(DayBlock t, int rawStart, int duration) {
    final s =
        ((rawStart % TimeMath.minutesPerDay) + TimeMath.minutesPerDay) %
        TimeMath.minutesPerDay;
    return t.copyWith(start: s, end: s + duration);
  }

  /// 替换指定位置的块，并校验结果仍然合法。非法就原样退回，绝不把脏数据写盘。
  static List<DayBlock> replaceAt(
    List<DayBlock> blocks,
    int index,
    DayBlock next,
  ) {
    final out = [...blocks];
    out[index] = next;
    return isValid(out) ? out : blocks;
  }

  /// 在包含 `minute` 的空隙里新建一块。
  ///
  /// - 开始时间取**该空隙的起点**，不是点击位置（验收 #8）；
  /// - 默认 30 分钟，空隙不够就取到空隙终点；
  /// - 不足 5 分钟的空隙直接放弃，不产生非法块；
  /// - 新建块的铃铛默认关闭（需求：别给每一行都默认开铃铛）。
  static ({List<DayBlock> blocks, int createdIndex})? createAt(
    List<DayBlock> blocks,
    int minute,
    Category category,
  ) {
    MinuteRange? gap;
    for (final g in TimeMath.gaps(blocks)) {
      if (g.contains(minute)) {
        gap = g;
        break;
      }
    }
    if (gap == null) return null;

    final start = snapUp(gap.start);
    if (start >= gap.end) return null;
    final end = snapDown((start + 30).clamp(start, gap.end));
    if (end - start < minDuration) return null;

    final created = DayBlock(
      start: start,
      end: end,
      name: category.label,
      category: category,
      remind: false,
    );
    final out = [...blocks, created]
      ..sort((a, b) => a.start.compareTo(b.start));
    return (blocks: out, createdIndex: out.indexOf(created));
  }

  static List<DayBlock> removeAt(List<DayBlock> blocks, int index) {
    final out = [...blocks]..removeAt(index);
    return out;
  }

  /// 不重叠校验：把每块展开成 24 小时轴上的 1–2 个占用区间再线性检查。
  /// 端点相接是合法的，只有真正交叉才算违规。
  static bool isValid(List<DayBlock> blocks) {
    if (blocks.any((b) => b.duration < minDuration)) return false;
    final marks = <MinuteRange>[for (final b in blocks) ...b.occupiedRanges]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < marks.length - 1; i++) {
      if (marks[i].end > marks[i + 1].start) return false;
    }
    return marks.fold(0, (sum, r) => sum + r.minutes) <= TimeMath.minutesPerDay;
  }

  /// 清单里手输时间。解析失败、重叠、倒挂一律返回 null，
  /// 由 UI 把输入框回退到修改前的值 —— 不弹错误框（验收 #25）。
  static DayBlock? parseTimeEdit(
    List<DayBlock> blocks,
    int index,
    String text, {
    required bool isStart,
  }) {
    final raw = text.trim();
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(raw)) return null;
    int minute;
    try {
      minute = TimeMath.parseHm(raw);
    } on Object {
      return null;
    }
    final t = blocks[index];

    if (isStart) {
      // 输入 23:30 而块结束在 07:00 时，应当理解为次日 07:00 之前的起点，
      // 仍然合法；但输入 12:00 而结束在 07:00 就是倒挂，拒绝。
      final candidate = withStart(blocks, index, minute);
      return candidate.start == snap(minute) ? candidate : null;
    }

    // 结束时间输入的值小于开始时间，只可能是跨到次日凌晨（如 23:00–07:00）。
    final wanted = minute <= t.start ? minute + TimeMath.minutesPerDay : minute;
    final candidate = withEnd(blocks, index, wanted);
    return (candidate.end % TimeMath.minutesPerDay) == snap(minute)
        ? candidate
        : null;
  }
}
