import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/actual_records.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/time_math.dart';
import 'package:routine_reminder/ui/l1/dashboard_screen.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10, 15); // 落在 09:00–12:00 工作块里

  group('纠偏记录', () {
    test('只改当前这一段，别的段和别的日子都不动', () {
      final base = SeedData.build();
      final key = TimeMath.dateKey(now);
      final next = ActualRecords.withOverride(
        base.records,
        key,
        9 * 60,
        Category.study,
      );

      expect(ActualRecords.overrideOf(next, key, 9 * 60), Category.study);
      expect(ActualRecords.overrideOf(next, key, 13 * 60), isNull);
      expect(ActualRecords.overrideOf(next, '2026-11-04', 9 * 60), isNull);
      expect(ActualRecords.hasAny(next, key), isTrue);
      expect(ActualRecords.hasAny(next, '2026-11-04'), isFalse);
      expect(base.records.isEmpty, isTrue, reason: '原对象不变');

      final plan = base.forDate(now).blocks;
      final actual = ActualRecords.actualBlocks(plan, next, key);
      final before = plan.where((b) => b.category == Category.study).length;
      expect(
        actual.where((b) => b.category == Category.study).length,
        before + 1,
        reason: '只多出被纠偏的这一段',
      );
      expect(
        actual.firstWhere((b) => b.start == 9 * 60).duration,
        180,
        reason: '边界不动，只换分类',
      );
    });

    test('没有记录时实际等于计划，两环完全一致', () {
      final data = SeedData.build();
      final plan = data.forDate(now).blocks;
      final actual = ActualRecords.actualBlocks(
        plan,
        data.records,
        TimeMath.dateKey(now),
      );
      for (var i = 0; i < plan.length; i++) {
        expect(actual[i].category, plan[i].category);
      }
    });
  });

  testWidgets('看板「我实际在做…」：点开七类快选，选中后只回调一次', (tester) async {
    final picked = <Category>[];
    Future<void> pump(AppData data) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(data: data, now: now, onOverride: picked.add),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(SeedData.build());
    expect(find.text('我实际在做…'), findsOneWidget, reason: '纠偏入口必须在看板，不在编辑层');

    await tester.tap(find.text('我实际在做…'));
    await tester.pumpAndSettle();
    expect(find.text('我现在实际在做…'), findsOneWidget);
    expect(find.text('学习'), findsWidgets);

    await tester.tap(find.text('学习').last);
    await tester.pumpAndSettle();
    expect(picked, [Category.study]);
    expect(find.text('我现在实际在做…'), findsNothing, reason: '选完立刻关闭');
  });

  testWidgets('纠偏后「现在」卡片显示实际分类', (tester) async {
    final base = SeedData.build();
    final data = base.withRecords(
      ActualRecords.withOverride(
        base.records,
        TimeMath.dateKey(now),
        9 * 60,
        Category.study,
      ),
    );
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(data: data, now: now, onOverride: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('实际：学习'), findsOneWidget);
  });
}
