import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/l1/dashboard_screen.dart';
import 'package:routine_reminder/ui/ring/dual_ring.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

/// 深色主题下未安排弧几乎融进底色，用户要求「悬停圆心的空档 xx →
/// 高亮环上所有未安排段」。这里守住交互链路，并给两套主题各留一张基线。
void main() {
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  bool gapHighlighted(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<DualRingPainter>()
      .any((p) => p.highlightGaps);

  Future<void> hover(WidgetTester tester, Finder target) async {
    expect(target, findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
  }

  for (final theme in AppTheme.values) {
    testWidgets('悬停空档高亮 · ${theme.label}', (tester) async {
      final seed = SeedData.build();
      final now = DateTime(2026, 11, 4, 19, 32);
      // SeedData 默认把 24h 排满（中心显示「已排满」）。必须先挖掉中间一块
      // 造出空档，才测得到用户反馈的「深色下未安排不明显」这个场景。
      final resolved = seed.forDate(now);
      final withGap = [...resolved.blocks]
        ..removeAt(resolved.blocks.length ~/ 2);
      final data = seed.withSchedule(resolved.mode, withGap);

      await pumpGoldenApp(
        tester,
        theme: theme,
        fontReady: fontReady,
        planLabel: data.forDate(now).label,
        view: AppView.dashboard,
        body: DashboardScreen(data: data, now: now, onOverride: (_) {}),
      );
      // 初始不高亮，默认截图仍按原配色。
      expect(gapHighlighted(tester), isFalse);

      await hover(tester, find.textContaining('空档'));
      expect(gapHighlighted(tester), isTrue);

      await shootGolden(
        tester,
        'l1_gap_highlight${theme == AppTheme.light ? '_light' : ''}.png',
      );
    });
  }

  testWidgets('显示「已排满」时中心不接管悬停', (tester) async {
    final data = SeedData.build();
    final now = DateTime(2026, 11, 4, 19, 32);
    await pumpGoldenApp(
      tester,
      theme: AppTheme.dark,
      fontReady: fontReady,
      planLabel: data.forDate(now).label,
      view: AppView.dashboard,
      body: Center(
        child: DualRing(
          blocks: data.forDate(now).blocks,
          nowMinute: now.hour * 60 + now.minute,
          diameter: 336,
          showCenter: true,
          centerTitle: '24h',
          centerSub: '已排满',
          centerSubInteractive: false,
        ),
      ),
    );

    await hover(tester, find.text('已排满'));
    expect(gapHighlighted(tester), isFalse);
  });
}
