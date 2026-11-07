import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/shell/app_window_bar.dart';
import 'package:routine_reminder/ui/shell/settings_panel.dart';

import 'golden_font.dart';

/// golden 截图用的整窗外壳。
///
/// 必须和 `app.dart` 里的真实外壳逐层一致（桌面底色 → 18px 留白 →
/// 圆角卡片 → 顶栏 → 内容 → 可选浮层），否则截图验的是另一套布局，
/// 配色/圆角/阴影的回归一个都发现不了。
/// 外围四条拖动带是纯透明的，不产生像素，这里不放也不影响截图。
const goldenWindowSize = Size(1060, 540);

void prepareGoldenSurface(WidgetTester tester, {Size size = goldenWindowSize}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ThemeData goldenTheme(AppTheme theme, bool fontReady) {
  Palette.setTheme(theme);
  final base = Palette.themeData();
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: fontReady ? goldenFontFamily : null,
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
  );
}

Future<void> pumpGoldenApp(
  WidgetTester tester, {
  required Widget body,
  required AppView view,
  required String planLabel,
  String dateLabel = '11月5日 周四',
  AppTheme theme = AppTheme.dark,
  bool fontReady = true,
  Size size = goldenWindowSize,
  bool settingsOpen = false,
  bool floatEnabled = true,
  bool openAtLogin = false,
  Widget? overlay,
}) async {
  prepareGoldenSurface(tester, size: size);
  await tester.pumpWidget(
    RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: goldenTheme(theme, fontReady),
        home: Scaffold(
          backgroundColor: Palette.ground,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: Palette.backgroundGlow),
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.pad),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Palette.app,
                        borderRadius: BorderRadius.circular(Radii.window),
                        border: Border.all(color: Palette.border),
                        boxShadow: Palette.windowShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.window),
                        child: Column(
                          children: [
                            AppWindowBar(
                              dateLabel: dateLabel,
                              planLabel: planLabel,
                              view: view,
                              onViewChanged: (_) {},
                              planPickerOpen: false,
                              onPlanPicker: () {},
                              planManagerOpen: false,
                              onPlanManager: () {},
                              settingsOpen: settingsOpen,
                              onSettings: () {},
                              maximized: false,
                              onToggleMaximize: () {},
                              onClose: () {},
                              onMinimize: () {},
                            ),
                            Expanded(child: body),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (settingsOpen)
                SettingsLayer(
                  theme: theme,
                  onThemeChanged: (_) {},
                  floatEnabled: floatEnabled,
                  onFloatChanged: () {},
                  openAtLogin: openAtLogin,
                  onAutostartChanged: () {},
                  onManagePlans: () {},
                  onClose: () {},
                ),
              // 新浮层（表选择器 / 管理面板 / 日历指派）由各测试自己构造后
              // 从外面塞进来，外壳只负责把它放在 Stack 最上层。
              ?overlay,
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> shootGolden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('goldens/$name'),
  );
}
