import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/ui/shell/plan_popover.dart';
import 'package:routine_reminder/ui/shell/settings_panel.dart';
import 'package:routine_reminder/ui/widgets/hover_intent.dart';
import 'package:routine_reminder/ui/widgets/segmented.dart';

/// v0.9.1 两条打磨的回归闸门：
/// 1. 所有按钮 hover 都得整块变灰；选中态不能被 active 配色盖住变成「没反应」。
/// 2. 浮层背后必须有压暗遮罩，且遮罩不能吃掉「点空白处收起」。
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

  BoxDecoration decorationOf(WidgetTester tester, Finder finder) =>
      (tester.widget<AnimatedContainer>(finder).decoration as BoxDecoration);

  /// 把鼠标停在 [target] 中心。返回的 gesture 用来再移开验 onExit。
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(1, 1));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    // v0.9.2：所有按钮都要「停留才算 hover」，快速掠过不得触发。
    // 这里补上延迟，测的才是真正停在按钮上的状态。
    await tester.pump(
      HoverIntent.defaultDelay + const Duration(milliseconds: 20),
    );
    await tester.pump();
    return gesture;
  }

  Future<void> moveAway(WidgetTester tester, TestGesture gesture) async {
    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
  }

  group('按钮 hover', () {
    testWidgets('BarButton 悬浮时整块底变灰，移开恢复', (tester) async {
      await tester.pumpWidget(wrap(BarButton(label: '设置', onTap: () {})));
      final box = find.descendant(
        of: find.byType(BarButton),
        matching: find.byType(AnimatedContainer),
      );
      expect(decorationOf(tester, box).color, Palette.panel2);

      final gesture = await hover(tester, find.byType(BarButton));
      expect(decorationOf(tester, box).color, Palette.hover);

      await moveAway(tester, gesture);
      expect(decorationOf(tester, box).color, Palette.panel2);
    });

    testWidgets('带 Tooltip 的按钮：提示浮出后 hover 不丢', (tester) async {
      await tester.pumpWidget(
        wrap(BarButton(label: '计划表', tooltip: '新建 / 编辑 / 排序计划表', onTap: () {})),
      );
      final box = find.descendant(
        of: find.byType(BarButton),
        matching: find.byType(AnimatedContainer),
      );
      await hover(tester, find.byType(BarButton));
      expect(decorationOf(tester, box).color, Palette.hover);

      // 600ms 后 Tooltip 挂上 Overlay。旧结构里 Tooltip 夹在 hover 层内侧，
      // 这里守住「浮层出现也不能把按钮打回未 hover」。
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(decorationOf(tester, box).color, Palette.hover);
    });

    testWidgets('分段控件当前选中项也有 hover 反馈', (tester) async {
      await tester.pumpWidget(
        wrap(
          Segmented<AppTheme>(
            items: AppTheme.values,
            value: AppTheme.dark,
            onChanged: (_) {},
            labelOf: (t) => t.label,
          ),
        ),
      );
      final boxes = find.descendant(
        of: find.byType(Segmented<AppTheme>),
        matching: find.byType(AnimatedContainer),
      );
      final active = boxes.at(0); // AppTheme.values = [dark, light]
      expect(decorationOf(tester, active).color, Palette.raised);

      await hover(tester, active);
      expect(decorationOf(tester, active).color, isNot(Palette.raised));
    });

    testWidgets('表选择器里已选中的那一行也有 hover 反馈', (tester) async {
      final plans = SeedData.build().plans;
      await tester.pumpWidget(
        wrap(
          PlanChoiceList(
            plans: plans,
            currentPlanId: plans.first.id,
            onSelect: (_) {},
          ),
        ),
      );
      final boxes = find.byType(AnimatedContainer);
      final active = boxes.at(0);
      final before = decorationOf(tester, active).color;
      expect(before, isNotNull);

      await hover(tester, active);
      expect(decorationOf(tester, active).color, isNot(before));
    });
  });

  group('浮层遮罩', () {
    for (final theme in AppTheme.values) {
      test('${theme.label}主题的遮罩是半透明压暗层', () {
        Palette.setTheme(theme);
        final c = Palette.scrim;
        expect(c.a, greaterThan(0.35));
        expect(c.a, lessThan(1.0));
      });
    }

    testWidgets('PopoverLayer 压暗底下内容，点空白处仍可收起', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: Palette.themeData(),
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('底层看板')),
                PopoverLayer(
                  onClose: () => closed++,
                  child: const SizedBox(width: 120, height: 60),
                ),
              ],
            ),
          ),
        ),
      );
      final scrim = find.descendant(
        of: find.byType(PopoverLayer),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Palette.scrim,
        ),
      );
      expect(scrim, findsOneWidget);
      expect(tester.getSize(scrim).width, greaterThan(0));

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('SettingsLayer 同样带压暗遮罩', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: Palette.themeData(),
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('底层看板')),
                SettingsLayer(
                  theme: Palette.theme,
                  onThemeChanged: (_) {},
                  floatEnabled: true,
                  onFloatChanged: () {},
                  openAtLogin: false,
                  onAutostartChanged: () {},
                  onManagePlans: () {},
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(SettingsLayer),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == Palette.scrim,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
