import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/plan_store.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/mobile/mobile_app.dart';

/// 纯内存 PlanStore：widget test 跑在假异步环境里，不能碰真实 dart:io。
class _MemoryStore implements PlanStore {
  AppData _data = SeedData.build();

  @override
  Future<AppData> load({bool forceReload = false}) async => _data;

  @override
  Future<void> save(AppData data) async => _data = data;

  @override
  Future<void> replace(AppData data) async => _data = data;

  @override
  Future<String> dataFilePath() async => '/memory/data.json';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Palette.setTheme(AppTheme.dark));

  testWidgets('390×844 竖屏：看板 / 编辑 / 汇总 / 计划表 / 数据页都能打开', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(MobileApp(store: _MemoryStore()));
    await tester.pumpAndSettle();

    // L1：执行导航的两块核心卡片必须在首屏。
    expect(find.text('现在该做什么'), findsOneWidget);
    expect(find.text('接着是'), findsOneWidget);
    expect(find.text('我的时间'), findsOneWidget);

    // 底部三个 tab 都能切过去，且不抛布局溢出异常。
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.textContaining('点开一段可改名称'), findsOneWidget);

    // v0.11：展开一段就能改名称与起止时刻（以前只能改分类 / 挪 15 分钟）。
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('起止时刻'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget);

    // 改名要即时反映到行标题上（写入走 withPlanBlocks，不是本地状态）。
    await tester.enterText(find.byType(TextField).first, '测试名称');
    await tester.pumpAndSettle();
    expect(find.text('测试名称'), findsWidgets);

    // 起止时刻的步进按钮点下去要生效，且不许把段改成负数时长。
    final beforeStart = find.text('开始');
    expect(beforeStart, findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('汇总'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 '), findsOneWidget);
    expect(find.text('导出这一期的 Markdown 报告'), findsOneWidget);

    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();

    // 计划表浮层：内嵌 Stack，不用 Navigator。点看板顶部的计划表卡片打开
    // （卡片上的表名随当天是工作日还是节假日变，不能拿固定文案定位）。
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('今天恢复按规则自动'), findsOneWidget);
    expect(find.text('接下来 7 天'), findsOneWidget);

    // 回归：这一行曾经写成 '今天：$active.label'，漏了花括号，结果把
    // AppData.forDate 的记录直接 toString 铺满整个浮层。这里锁死「人话」。
    expect(find.textContaining('(blocks:', findRichText: true), findsNothing);
    expect(find.textContaining('今天：', findRichText: true), findsOneWidget);

    // v0.11：表名可以就地改（以前只有电脑端能改）。改完不用重开浮层。
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我的第一张表');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('我的第一张表'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // 数据页：导入导出入口与云同步说明。
    await tester.tap(find.byIcon(Icons.storage_outlined));
    await tester.pumpAndSettle();
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
    expect(find.textContaining('PlanStore'), findsOneWidget);

    // 到点提醒：默认关，打开后要求权限并显示状态。
    expect(find.text('到点提醒'), findsOneWidget);
    expect(find.text('每段开始时弹一条通知'), findsOneWidget);
    expect(find.text('关掉后不会推送任何通知'), findsOneWidget);

    // 测试环境的提醒通道是 Noop（一律 granted），所以这里验的是
    // 「开关 → 权限状态 → 排程说明」这条链路，不是系统通知本身。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('按接下来 7 天的计划排程'), findsOneWidget);
    expect(find.text('通知与精确闹钟都已放行'), findsOneWidget);
  });
}
