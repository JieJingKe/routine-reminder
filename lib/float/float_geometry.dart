import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 悬浮窗单圈几何：24 小时铺满 360°，0 点在正上方。
///
/// 双环的 0 点也在上方，但那是「内圈 0–12、外圈 12–24」；
/// 这里只有一圈，12 点在正下方。两者方位不一致是故意的。
abstract final class FloatGeometry {
  static const double size = 168;
  static const double center = 84;
  static const double outer = 74;
  static const double inner = 51;
  static const double mid = (outer + inner) / 2;
  static const double ringWidth = outer - inner;
  static const double pointerWidth = 2.4;

  /// 分钟数换算成画布弧度。0 点在 -90°。
  static double angleOf(int minute) =>
      minute / 1440 * 2 * math.pi - math.pi / 2;

  static Offset polar(double radius, double angle) => Offset(
    center + radius * math.cos(angle),
    center + radius * math.sin(angle),
  );

  /// 跨零点的块拆成同一圈上的两段弧。
  ///
  /// 逐段画、不合并：合并后从 00:00 开始的那一段会绕到路径终点之外，
  /// 在圆上显示不出来。
  static List<({int from, int to})> pieces(int start, int end) {
    if (end <= 1440) return [(from: start, to: end)];
    return [(from: start, to: 1440), (from: 0, to: end - 1440)];
  }
}
