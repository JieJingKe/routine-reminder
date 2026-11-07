import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/l1/dashboard_screen.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

/// 整窗截图基线：1060×600（正式窗口默认尺寸）。
///
/// 两套主题各存一张 —— UI 稿 v2 同时给了浅色和深色预览，
/// 只验一套等于放掉一半的配色回归。
void main() {
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  for (final theme in AppTheme.values) {
    testWidgets('L1 看板整窗 · ${theme.label}', (tester) async {
      final data = SeedData.build();
      // 2026-11-04 是周三，走工作日表；19:32 是"锻炼"块，指针落在左下。
      final now = DateTime(2026, 11, 4, 19, 32);

      await pumpGoldenApp(
        tester,
        theme: theme,
        fontReady: fontReady,
        planLabel: data.forDate(now).label,
        view: AppView.dashboard,
        body: DashboardScreen(data: data, now: now, onOverride: (_) {}),
      );

      await shootGolden(
        tester,
        'l1_dashboard${theme == AppTheme.light ? '_light' : ''}.png',
      );
    });
  }
}
