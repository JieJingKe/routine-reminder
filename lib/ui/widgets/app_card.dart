import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 卡片：1px 细边 + 轻阴影（浅色主题才有），底色只比窗口亮/暗一档。
///
/// UI 稿 v2 放弃了「纯明度分层」：浅色底上白卡片不描边会融进背景，
/// 深色底上则靠 1px 边把层级勾出来。环仍然是唯一的主角，
/// 所以阴影只给 3px，不做大投影。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.pad),
    this.width,
    this.color,
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;
  final Color? color;

  /// 小卡（今天学习 / 今天锻炼）用 11，普通卡用 13。
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Palette.surface,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(radius ?? Radii.card),
        boxShadow: Palette.cardShadow,
      ),
      child: child,
    );
  }
}

/// 图例圆点。分类色 + 未安排的纹理底。
class LegendDot extends StatelessWidget {
  const LegendDot({
    super.key,
    required this.color,
    this.hatched = false,
    this.size = 8,
  });

  final Color color;
  final bool hatched;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: hatched
          ? CustomPaint(
              painter: _HatchDotPainter(color: Palette.unplannedHatch),
            )
          : null,
    );
  }
}

class _HatchDotPainter extends CustomPainter {
  const _HatchDotPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.butt;
    for (var i = -size.height; i < size.width; i += 2.5) {
      canvas.drawLine(
        Offset(i, size.height),
        Offset(i + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchDotPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 顶部一条细分隔线。用来分开顶栏和内容，不用投影。
class ThinRule extends StatelessWidget {
  const ThinRule({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Palette.rule);
}
