import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/shell/app_window_bar.dart';
import 'package:routine_reminder/ui/widgets/hover_intent.dart';

/// v0.9.2 的回归闸门：Jason 反馈「鼠标经过最小化 / 关闭等按钮时
/// 还是会有深色显示」。确认快速经过不触发、停留才亮、命中区域严格等于
/// 按钮视觉边界，且点击不受延迟影响。
void main() {
  setUp(() => Palette.setTheme(AppTheme.dark));
  tearDown(() => Palette.setTheme(AppTheme.dark));

  Widget wrap(Widget child) => MaterialApp(
    theme: Palette.themeData(),
    home: Scaffold(
      backgroundColor: Palette.ground,
      body: Center(child: child),
    ),
  );

  Widget button({VoidCallback? onTap, IconData icon = Icons.close}) =>
      WindowButton(icon: icon, onTap: onTap ?? () {}, semanticLabel: '关闭窗口');

  BoxDecoration decorationOf(WidgetTester tester) =>
      tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration
          as BoxDecoration;

  Color iconColorOf(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).color!;

  /// 建一个鼠标指针并移到 [at]。返回的 gesture 用来继续移动验 onExit。
  Future<TestGesture> mouse(WidgetTester tester, Offset at) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(1, 1));
    await tester.pump();
    await gesture.moveTo(at);
    await tester.pump();
    return gesture;
  }

  /// 等过停留门槛。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(
      HoverIntent.defaultDelay + const Duration(milliseconds: 20),
    );
    await tester.pump();
  }

  group('窗口按钮 hover 时序', () {
    testWidgets('默认透明底 + 弱图标，且不挂 Tooltip 浮层', (tester) async {
      await tester.pumpWidget(wrap(button()));
      expect(decorationOf(tester).color, Colors.transparent);
      expect(iconColorOf(tester), Palette.faint);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('快速掠过：进入后立刻离开，全程不出现深色', (tester) async {
      await tester.pumpWidget(wrap(button()));
      final gesture = await mouse(
        tester,
        tester.getCenter(find.byType(WindowButton)),
      );
      expect(decorationOf(tester).color, Colors.transparent);

      await gesture.moveTo(const Offset(1, 1));
      await tester.pump();
      // 延迟到点也不许「补亮」：Timer 必须在 onExit 时被取消。
      await settle(tester);
      expect(decorationOf(tester).color, Colors.transparent);
      expect(iconColorOf(tester), Palette.faint);
    });

    testWidgets('停留够久才出现深色反馈，离开立即恢复', (tester) async {
      await tester.pumpWidget(wrap(button()));
      final gesture = await mouse(
        tester,
        tester.getCenter(find.byType(WindowButton)),
      );

      await tester.pump(const Duration(milliseconds: 60));
      expect(decorationOf(tester).color, Colors.transparent);

      await settle(tester);
      expect(decorationOf(tester).color, Palette.hover);
      expect(iconColorOf(tester), Palette.text);

      await gesture.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(decorationOf(tester).color, Colors.transparent);
      expect(iconColorOf(tester), Palette.faint);
    });

    testWidgets('命中区域严格等于 26x26 按钮块，不外溢', (tester) async {
      await tester.pumpWidget(wrap(button()));
      final target = find.byType(WindowButton);
      expect(tester.getSize(target), const Size(26, 26));
      final center = tester.getCenter(target);

      // 图标只有 15px：+11 落在图标外、按钮内。旧实现的 MouseRegion
      // 只认图标那一小块，这里不会有任何反馈。
      final gesture = await mouse(tester, center + const Offset(11, 0));
      await settle(tester);
      expect(decorationOf(tester).color, Palette.hover);

      // +14 已经出了 26px 按钮边界，不该触发 hover。
      await gesture.moveTo(const Offset(1, 1));
      await tester.pump();
      await gesture.moveTo(center + const Offset(14, 0));
      await settle(tester);
      expect(decorationOf(tester).color, Colors.transparent);
    });

    testWidgets('点击不受停留延迟影响', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(button(onTap: () => taps++)));
      await tester.tap(find.byType(WindowButton));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('顶栏三个窗口按钮', () {
    testWidgets('最小化 / 最大化 / 关闭统一用 WindowButton，顺序不变', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppWindowBar(
            dateLabel: '11月7日 周六',
            planLabel: '工作日（按星期几）',
            view: AppView.values.first,
            onViewChanged: (_) {},
            planPickerOpen: false,
            onPlanPicker: () {},
            planManagerOpen: false,
            onPlanManager: () {},
            settingsOpen: false,
            onSettings: () {},
            maximized: false,
            onToggleMaximize: () {},
            onClose: () {},
            onMinimize: () {},
          ),
        ),
      );
      expect(find.byType(WindowButton), findsNWidgets(3));
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // 三个按钮默认都不带深色底。
      for (final box in find.byType(AnimatedContainer).evaluate()) {
        final w = box.widget as AnimatedContainer;
        final d = w.decoration as BoxDecoration?;
        if (d != null && d.color == Palette.hover) {
          fail('默认状态下不应有按钮处于 hover 深色');
        }
      }
    });
  });
}
