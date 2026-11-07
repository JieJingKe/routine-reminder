import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/l1/dashboard_screen.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

/// 设置浮层压在真实看板上的整窗截图。两套主题各一张，同时把两个开关
/// 的「开 / 关」两种样子都覆盖到：深色版「悬浮窗开 · 自启关」，
/// 浅色版「悬浮窗关 · 自启开」。
void main() {
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  for (final theme in AppTheme.values) {
    testWidgets('设置面板 · ${theme.label}', (tester) async {
      final data = SeedData.build();
      // 与 L1 基线同一时刻，方便横向对照。
      final now = DateTime(2026, 11, 4, 19, 32);

      await pumpGoldenApp(
        tester,
        theme: theme,
        fontReady: fontReady,
        planLabel: data.forDate(now).label,
        view: AppView.dashboard,
        body: DashboardScreen(data: data, now: now, onOverride: (_) {}),
        settingsOpen: true,
        floatEnabled: theme == AppTheme.dark,
        openAtLogin: theme == AppTheme.light,
      );

      await shootGolden(
        tester,
        'shell_settings${theme == AppTheme.light ? '_light' : ''}.png',
      );
    });
  }
}
