import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../domain/category.dart';
import '../../domain/day_block.dart';
import '../../domain/time_math.dart';

/// 双环的几何常量。**定死的数字，别自己调**（交接文档「参数速查」）。
///
/// 画布 340×340，圆心 (170,170)，12 点方向是起点，顺时针递增。
/// 内圈半径 56–96 管 00:00–12:00，外圈 112–152 管 12:00–24:00。
abstract final class RingGeometry {
  static const double canvasSize = 340;
  static const double center = 170;

  static const double innerR0 = 56;
  static const double innerR1 = 96;
  static const double outerR0 = 112;
  static const double outerR1 = 152;

  /// 小时数字放的位置：内圈数字落在两道环之间的缝里，外圈数字在外侧。
  static const double innerHourLabelR = 104;
  static const double outerHourLabelR = 163;

  /// 12:00 标签牌的位置（相对圆心）。
  static const double labelPlateTop = -113;
  static const double labelPlateWidth = 38;
  static const double labelPlateHeight = 15;
  static const double labelTextDy = -101.6;

  static double r0(RingSide side) => side == RingSide.inner ? innerR0 : outerR0;

  static double r1(RingSide side) => side == RingSide.inner ? innerR1 : outerR1;

  static double rMid(RingSide side) => (r0(side) + r1(side)) / 2;

  /// 一分钟映射到弧度：`0°` 在正上方，顺时针。
  ///
  /// 两圈都用「分钟数对 720 取模」—— 外圈 12:00（720）落回 0°，
  /// 这样内外圈共用一套角度，不用分情况。
  static double angleOf(double minute) =>
      (minute % 720) / 720 * 2 * math.pi - math.pi / 2;

  static Offset polar(double r, double minute) {
    final a = angleOf(minute);
    return Offset(center + r * math.cos(a), center + r * math.sin(a));
  }

  /// 极坐标，直接给角度（度）。用于固定刻度。
  static Offset polarDeg(double r, double deg) {
    final a = (deg - 90) * math.pi / 180;
    return Offset(center + r * math.cos(a), center + r * math.sin(a));
  }

  /// 一段弧的圆心角（弧度），已减去 0.6 个像素的缝宽，避免相邻段糊在一起。
  ///
  /// 与样张的 `stroke-dasharray: len-0.6` 等价：0.6 是弧长像素，不是角度，
  /// 所以要除以半径换成弧度。
  static ({double start, double sweep}) arcOf(RingSide side, int from, int to) {
    final mid = rMid(side);
    final full = 2 * math.pi * mid;
    final arcPx = (to - from) / 720 * full;
    final drawPx = math.max(arcPx - 0.6, 0.4);
    return (start: angleOf(from.toDouble()), sweep: drawPx / mid);
  }

  /// 鼠标位置落在环上的哪一块。
  ///
  /// 返回 `null` 表示根本没碰到环（圆心、环外、两环之间的缝）。
  /// 返回的 record 里 `block` 为 null 表示**落在空档上** ——
  /// 这和"没碰到"是两件不同的事：空档也要能悬停出提示，
  /// 否则鼠标扫过半个环都没反应，会让人以为功能坏了。
  static ({int minute, DayBlock? block})? hitTest(
    Offset local,
    double diameter,
    List<DayBlock> blocks,
  ) {
    final scale = diameter / canvasSize;
    final dx = local.dx / scale - center;
    final dy = local.dy / scale - center;
    final r = math.sqrt(dx * dx + dy * dy);

    // 容差 3 个画布单位：鼠标贴边时常常差一两个像素，不给容差会点不中。
    // 内圈上限 99、外圈下限 109，中间的缝仍然不会误命中。
    final RingSide side;
    if (r >= innerR0 - 3 && r <= innerR1 + 3) {
      side = RingSide.inner;
    } else if (r >= outerR0 - 3 && r <= outerR1 + 3) {
      side = RingSide.outer;
    } else {
      return null;
    }

    // atan2 以 3 点方向为 0°、逆时针为正；环以 12 点为 0°、顺时针递增。
    var deg = math.atan2(dy, dx) * 180 / math.pi + 90;
    if (deg < 0) deg += 360;
    var minute = (deg / 360 * 720).floor();
    if (minute >= 720) minute = 0; // 正好压在 12 点线上，归到起点
    if (side == RingSide.outer) minute += 720;

    return (minute: minute, block: TimeMath.blockAt(blocks, minute));
  }
}

/// 环上一个待画的色段。
class ArcSegment {
  const ArcSegment({
    required this.side,
    required this.from,
    required this.to,
    required this.category,
    required this.isCurrent,
    required this.isGap,
  });

  final RingSide side;
  final int from;
  final int to;
  final Category? category;
  final bool isCurrent;
  final bool isGap;
}
