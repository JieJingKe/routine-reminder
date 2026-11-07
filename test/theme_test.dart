import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_mode.dart';
import 'package:routine_reminder/ui/widgets/segmented.dart';

import 'golden_harness.dart';

/// 浅/深双主题是 UI 稿 v2 最大的新增项。
/// 这里守三条：两套令牌确实不同、切换立即生效、偏好能存进 JSON。
void main() {
  setUp(() => Palette.setTheme(AppTheme.dark));
  tearDown(() => Palette.setTheme(AppTheme.dark));

  test('两套主题的窗口底色、文字色、分类色都不同', () {
    Palette.setTheme(AppTheme.dark);
    final dark = (
      app: Palette.app,
      text: Palette.text,
      work: Palette.of(Category.work),
      seam: Palette.seam,
    );

    Palette.setTheme(AppTheme.light);
    expect(Palette.isLight, isTrue);
    expect(Palette.app, isNot(dark.app));
    expect(Palette.text, isNot(dark.text));
    expect(Palette.of(Category.work), isNot(dark.work));
    expect(Palette.seam, isNot(dark.seam));

    // 缝色必须等于窗口底色，否则色块之间会出现一条来路不明的黑线。
    expect(Palette.seam, Palette.app);
    expect(Palette.unplanned, Palette.track);
  });

  test('themeData 的亮度跟着主题走', () {
    Palette.setTheme(AppTheme.dark);
    expect(Palette.themeData().brightness, Brightness.dark);
    Palette.setTheme(AppTheme.light);
    expect(Palette.themeData().brightness, Brightness.light);
  });

  test('同色提亮在两套主题上方向相反', () {
    Palette.setTheme(AppTheme.dark);
    final darkBase = Palette.of(Category.work);
    final darkHi = Palette.hiStroke(darkBase);

    Palette.setTheme(AppTheme.light);
    final lightBase = Palette.of(Category.work);
    final lightHi = Palette.hiStroke(lightBase);

    expect(darkHi, isNot(darkBase));
    expect(lightHi, isNot(lightBase));
    expect(darkHi, isNot(lightHi));
    // 深色底提亮读作「这块亮着」；浅色底加饱和、压明度读作「这块更实」。
    expect(
      HSLColor.fromColor(darkHi).lightness,
      greaterThan(HSLColor.fromColor(darkBase).lightness),
    );
    expect(
      HSLColor.fromColor(lightHi).lightness,
      lessThan(HSLColor.fromColor(lightBase).lightness),
    );
  });

  test('热图在浅色主题下越深=越多，深色主题下越亮=越多', () {
    Palette.setTheme(AppTheme.dark);
    final darkLow = Palette.heatFill(0.0);
    final darkHigh = Palette.heatFill(1.0);
    expect(
      HSLColor.fromColor(darkHigh).lightness,
      greaterThan(HSLColor.fromColor(darkLow).lightness),
    );

    Palette.setTheme(AppTheme.light);
    final lightLow = Palette.heatFill(0.0);
    final lightHigh = Palette.heatFill(1.0);
    expect(
      HSLColor.fromColor(lightHigh).lightness,
      lessThan(HSLColor.fromColor(lightLow).lightness),
    );
  });

  test('主题偏好写进 ui，JSON 往返不丢，且不动作息表', () {
    final original = SeedData.build();
    final next = original.withUi(original.ui.copyWith(theme: 'light'));

    // v2 起 plans 是唯一真相源，schedules 只是派生 getter。
    expect(next.plans, same(original.plans));
    expect(next.records, same(original.records));
    expect(next.ui.theme, 'light');

    final restored = AppData.fromJson(next.toJson());
    expect(restored.ui.theme, 'light');
    expect(
      restored.schedules[DayMode.workday]?.length,
      original.schedules[DayMode.workday]?.length,
    );

    // 没选过时是 null = 跟随系统，不能悄悄写成某个固定主题。
    expect(const UiPrefs().theme, isNull);
    expect(UiPrefs.fromJson(const {'theme': 'garbage'}).theme, isNull);
  });

  // #7 之后主题不再是顶栏的「深色 / 浅色」翻转按钮，而是设置面板里的
  // 二选一分段。这个用例守住「入口确实搬走了」，别哪天又被加回顶栏。
  testWidgets('主题收进设置面板，顶栏只留「设置」入口', (tester) async {
    for (final theme in AppTheme.values) {
      await pumpGoldenApp(
        tester,
        theme: theme,
        fontReady: false,
        planLabel: '工作日（按星期几）',
        view: AppView.dashboard,
        body: const SizedBox.expand(),
        settingsOpen: true,
      );
      expect(find.text('深色'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      // 顶栏胶囊 + 面板标题。
      expect(find.text('设置'), findsNWidgets(2));
      expect(find.widgetWithText(BarButton, '设置'), findsOneWidget);
      // 齿轮图标必须真的挂上：Release 包曾因图标字体子集没重跑而缺字形，
      // 留下 13px 空白却不显示图形，看起来就是「设置」不居中。
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.widgetWithText(BarButton, '深色'), findsNothing);
      expect(find.widgetWithText(BarButton, '浅色'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
