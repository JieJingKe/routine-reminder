import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/domain/plan.dart';
import 'package:routine_reminder/ui/shell/plan_manager.dart';
import 'package:routine_reminder/ui/shell/plan_popover.dart';
import 'package:routine_reminder/ui/widgets/segmented.dart';

import 'golden_harness.dart';

/// #9 的界面交互回归：入口在、旧入口已撤、回调把用户的选择正确交出去。
void main() {
  final now = DateTime(2026, 11, 4, 19, 32); // 周三 → 工作日表

  setUp(() => Palette.setTheme(AppTheme.dark));
  tearDown(() => Palette.setTheme(AppTheme.dark));

  Future<void> pumpPanel(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 430, height: 470, child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('顶栏只剩表标签 / 计划表 / 设置，二选一与全局周期弹窗已撤', (tester) async {
    await pumpGoldenApp(
      tester,
      fontReady: false,
      planLabel: '工作日（按星期几）',
      view: AppView.dashboard,
      body: const SizedBox.expand(),
    );
    expect(find.textContaining('今天：'), findsOneWidget);
    expect(find.widgetWithText(BarButton, '计划表'), findsOneWidget);
    expect(find.widgetWithText(BarButton, '设置'), findsOneWidget);
    expect(find.widgetWithText(BarButton, '周期规则'), findsNothing);
    expect(find.widgetWithText(BarButton, '工作日'), findsNothing);
    expect(find.widgetWithText(BarButton, '节假日'), findsNothing);
  });

  testWidgets('管理面板列出全部表，新建用不抢日期的安全默认', (tester) async {
    final data = SeedData.build();
    final got = <List<Plan>>[];
    await pumpPanel(
      tester,
      PlanManagerPanel(
        data: data,
        now: now,
        onPlansChanged: got.add,
        onEditBlocks: (_) {},
        onClose: () {},
      ),
    );
    expect(find.text('工作日'), findsOneWidget);
    expect(find.text('节假日'), findsOneWidget);
    expect(find.text('共 2 张'), findsOneWidget);

    await tester.tap(find.widgetWithText(BarButton, '新建'));
    await tester.pumpAndSettle();
    expect(got, hasLength(1));
    final added = got.last.last;
    expect(added.name, '新计划表');
    expect(added.repeat.kind, RepeatKind.dates);
    expect(added.repeat.dates, isEmpty);
    expect(added.legacyMode, isNull);
    // 新表默认不命中任何一天，不会凭空抢走今天。
    final withAdded = data.withPlans(got.last);
    expect(withAdded.forDate(now).planId, PlanDefaults.workdayId);
  });

  testWidgets('复制表不继承 legacyMode，且插在被复制表后面', (tester) async {
    final data = SeedData.build();
    final got = <List<Plan>>[];
    await pumpPanel(
      tester,
      PlanManagerPanel(
        data: data,
        now: now,
        onPlansChanged: got.add,
        onEditBlocks: (_) {},
        onClose: () {},
      ),
    );
    await tester.tap(find.byTooltip('复制').first);
    await tester.pumpAndSettle();
    expect(got, hasLength(1));
    expect(got.last, hasLength(3));
    expect(got.last[1].name, '工作日 副本');
    expect(got.last[1].legacyMode, isNull);
  });

  testWidgets('编辑器能切重复方式、能跳去编作息', (tester) async {
    final plan = SeedData.build().plans.first;
    final got = <Plan>[];
    final edited = <String>[];
    await pumpPanel(
      tester,
      SingleChildScrollView(
        child: PlanEditor(
          plan: plan,
          now: now,
          onChanged: got.add,
          onEditBlocks: edited.add,
          onBack: () {},
        ),
      ),
    );
    expect(find.text('重复设置'), findsOneWidget);
    await tester.tap(find.text('指定日期'));
    await tester.pumpAndSettle();
    expect(got.last.repeat.kind, RepeatKind.dates);

    // 月历默认折叠，点开才出现；这样「编辑作息」入口始终在首屏。
    expect(find.text('选择日期'), findsOneWidget);
    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();
    expect(find.text('收起日历'), findsOneWidget);
    await tester.tap(find.text('收起日历'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('编辑这张表的作息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑这张表的作息'));
    await tester.pumpAndSettle();
    expect(edited, [plan.id]);
  });

  testWidgets('表选择器把选中项与「恢复自动判定」都交出去', (tester) async {
    final data = SeedData.build();
    final picked = <String?>[];
    await pumpPanel(
      tester,
      PlanPickerPanel(
        plans: data.plans,
        currentPlanId: PlanDefaults.workdayId,
        currentSource: '手动改判',
        autoPlanName: '工作日',
        overriddenAt: '2026-11-04T19:32:00.000',
        onSelect: picked.add,
        onClose: () {},
      ),
    );
    expect(find.textContaining('按规则本应是'), findsOneWidget);
    await tester.tap(find.text('节假日').last);
    await tester.pumpAndSettle();
    expect(picked, [PlanDefaults.holidayId]);

    await tester.tap(find.text('恢复自动判定'));
    await tester.pumpAndSettle();
    expect(picked.last, isNull);
  });

  testWidgets('日历指派浮层显示日期与自动结果', (tester) async {
    final data = SeedData.build();
    final picked = <String?>[];
    final date = DateTime(2026, 11, 9);
    await pumpPanel(
      tester,
      DayAssignPanel(
        date: date,
        plans: data.plans,
        assignedPlanId: null,
        autoPlanName: '工作日',
        onSelect: picked.add,
        onClose: () {},
      ),
    );
    expect(find.textContaining('2026-11-09'), findsOneWidget);
    expect(find.textContaining('工作日（按重复规则）'), findsOneWidget);
    await tester.tap(find.text('节假日').last);
    await tester.pumpAndSettle();
    expect(picked, [PlanDefaults.holidayId]);
  });

  test('AppData.assignDay 与界面回调共用同一套语义', () {
    final data = SeedData.build();
    final key =
        '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final assigned = data.assignDay(
      key,
      PlanDefaults.holidayId,
      at: '2026-11-04T19:32:00.000',
    );
    expect(assigned.forDate(now).planId, PlanDefaults.holidayId);
    expect(assigned.daySnapshots[key]!.source, '手动改判');
  });
}
