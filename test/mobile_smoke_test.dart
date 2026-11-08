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
    expect(find.textContaining('点开一段可改分类'), findsOneWidget);

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

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // 数据页：导入导出入口与云同步说明。
    await tester.tap(find.byIcon(Icons.storage_outlined));
    await tester.pumpAndSettle();
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
    expect(find.textContaining('PlanStore'), findsOneWidget);
  });
}
