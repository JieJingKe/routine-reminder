import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/shell/settings_panel.dart';

/// #7 设置层的交互回归。逻辑仍复用 app.dart 的 _setTheme / _toggleFloat /
/// _toggleAutostart，这里只验「面板把用户的点击正确交出去」。
void main() {
  setUp(() => Palette.setTheme(AppTheme.dark));
  tearDown(() => Palette.setTheme(AppTheme.dark));

  Future<void> pumpLayer(
    WidgetTester tester, {
    required ValueChanged<AppTheme> onTheme,
    required VoidCallback onFloat,
    required VoidCallback onAutostart,
    required VoidCallback onClose,
    bool floatEnabled = true,
    bool openAtLogin = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SettingsLayer(
                theme: Palette.theme,
                onThemeChanged: onTheme,
                floatEnabled: floatEnabled,
                onFloatChanged: onFloat,
                openAtLogin: openAtLogin,
                onAutostartChanged: onAutostart,
                onManagePlans: () {},
                onClose: onClose,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('主题分段把选中的那一套传出去', (tester) async {
    final picked = <AppTheme>[];
    await pumpLayer(
      tester,
      onTheme: picked.add,
      onFloat: () {},
      onAutostart: () {},
      onClose: () {},
    );

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(picked, [AppTheme.light]);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(picked, [AppTheme.light, AppTheme.dark]);
  });

  testWidgets('两个开关整行都能点，状态按传入值显示', (tester) async {
    var floats = 0;
    var autos = 0;
    await pumpLayer(
      tester,
      onTheme: (_) {},
      onFloat: () => floats++,
      onAutostart: () => autos++,
      onClose: () {},
      floatEnabled: true,
      openAtLogin: false,
    );

    expect(find.text('桌面悬浮窗'), findsOneWidget);
    expect(find.text('开机自启'), findsOneWidget);
    expect(find.text('单击空白处或按 Esc 收起设置'), findsOneWidget);

    // 点在说明文字上也要算整行点击，不能只有那个 34px 小开关有效。
    await tester.tap(find.text('在桌面右下角显示 168px 悬浮环'));
    await tester.pumpAndSettle();
    expect(floats, 1);

    await tester.tap(find.text('开机只启动托盘与悬浮窗，不弹主窗口'));
    await tester.pumpAndSettle();
    expect(autos, 1);
  });

  testWidgets('空白处 / 关闭图标 / Esc 都能收起面板', (tester) async {
    var closes = 0;
    await pumpLayer(
      tester,
      onTheme: (_) {},
      onFloat: () {},
      onAutostart: () {},
      onClose: () => closes++,
    );

    // 面板在右上角，左上角一定落在透明遮罩上。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(closes, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(closes, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closes, 3);
  });
}
