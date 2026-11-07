import 'dart:ui' show Offset;

import 'package:screen_retriever/screen_retriever.dart';

import '../float/float_geometry.dart';

/// 悬浮窗启动位置。
///
/// 存过的坐标必须校验：上次在副屏、这次副屏拔了，窗口会跑到看不见的地方，
/// 用户只会觉得"悬浮窗坏了"。落在任一显示器的可用区域内才采用，
/// 否则回到主屏右下角，距边缘 24px。
Offset resolveFloatPosition({
  double? x,
  double? y,
  required List<Display> displays,
  required Display? primary,
  double size = FloatGeometry.size,
  double margin = 24,
}) {
  if (x != null && y != null) {
    for (final display in displays) {
      final origin = display.visiblePosition;
      final area = display.visibleSize;
      if (origin == null || area == null) continue;
      final fits =
          x >= origin.dx &&
          y >= origin.dy &&
          x + size <= origin.dx + area.width &&
          y + size <= origin.dy + area.height;
      if (fits) return Offset(x, y);
    }
  }

  final target = primary ?? (displays.isEmpty ? null : displays.first);
  final origin = target?.visiblePosition;
  final area = target?.visibleSize;
  if (origin == null || area == null) return const Offset(100, 100);

  return Offset(
    origin.dx + area.width - size - margin,
    origin.dy + area.height - size - margin,
  );
}
