import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/domain/plan.dart';
import 'package:routine_reminder/ui/l1/dashboard_screen.dart';
import 'package:routine_reminder/ui/shell/plan_manager.dart';
import 'package:routine_reminder/ui/shell/plan_popover.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

/// #9 三个新浮层的整窗截图。压在真实看板上，验的是浮层与窗口的
/// 配色、阴影、层级关系，而不是把面板单独截一张。
void main() {
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  final now = DateTime(2026, 11, 4, 19, 32); // 周三 → 工作日表
  final data = SeedData.build();

  Future<void> shell(
    WidgetTester tester, {
    required AppTheme theme,
    required Widget overlay,
  }) async {
    await pumpGoldenApp(
      tester,
      theme: theme,
      fontReady: fontReady,
      planLabel: data.forDate(now).label,
      view: AppView.dashboard,
      body: DashboardScreen(data: data, now: now, onOverride: (_) {}),
      overlay: overlay,
    );
  }

  PlanPickerPanel picker({bool overridden = false}) => PlanPickerPanel(
    plans: data.plans,
    currentPlanId: PlanDefaults.workdayId,
    currentSource: overridden ? '手动改判' : '按星期几',
    autoPlanName: '工作日',
    overriddenAt: overridden ? '2026-11-04T19:32:00.000' : null,
    onSelect: (_) {},
    onClose: () {},
  );

  testWidgets('表选择器 · 自动判定态', (tester) async {
    await shell(
      tester,
      theme: AppTheme.dark,
      overlay: PopoverLayer(onClose: () {}, child: picker()),
    );
    await shootGolden(tester, 'shell_plan_picker.png');
  });

  testWidgets('表选择器 · 浅色且已改判', (tester) async {
    await shell(
      tester,
      theme: AppTheme.light,
      overlay: PopoverLayer(onClose: () {}, child: picker(overridden: true)),
    );
    await shootGolden(tester, 'shell_plan_picker_light.png');
  });

  testWidgets('计划表管理 · 列表', (tester) async {
    await shell(
      tester,
      theme: AppTheme.dark,
      overlay: PlanManagerLayer(
        data: data,
        now: now,
        onPlansChanged: (_) {},
        onEditBlocks: (_) {},
        onClose: () {},
      ),
    );
    await shootGolden(tester, 'shell_plan_manager.png');
  });

  testWidgets('单表编辑器 · 重复设置与特殊日期', (tester) async {
    await shell(
      tester,
      theme: AppTheme.dark,
      overlay: PopoverLayer(
        width: 430,
        onClose: () {},
        child: PopoverCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 430),
            child: SingleChildScrollView(
              child: PlanEditor(
                plan: data.plans.first,
                now: now,
                onChanged: (_) {},
                onEditBlocks: (_) {},
                onBack: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await shootGolden(tester, 'shell_plan_editor.png');
  });

  testWidgets('日历指派 · 单日改判', (tester) async {
    await shell(
      tester,
      theme: AppTheme.dark,
      overlay: PopoverLayer(
        top: 120,
        onClose: () {},
        child: DayAssignPanel(
          date: DateTime(2026, 11, 9),
          plans: data.plans,
          assignedPlanId: null,
          autoPlanName: '工作日',
          onSelect: (_) {},
          onClose: () {},
        ),
      ),
    );
    await shootGolden(tester, 'shell_day_assign.png');
  });
}
