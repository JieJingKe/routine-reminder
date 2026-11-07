import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/data/summary.dart';
import 'package:routine_reminder/domain/actual_records.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/domain/time_math.dart';
import 'package:routine_reminder/ui/l3/summary_screen.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

void main() {
  final now = DateTime(2026, 11, 5, 14, 37);
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  /// 造一段「已经装了 40 天」的历史，好让周/月两种图形都有内容可画。
  /// 正式环境第一次启动只有今天一条快照，其余全是空心格 —— 另外有测试覆盖。
  AppData withHistory() {
    var data = SeedData.build();
    for (var i = 40; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final r = data.forDate(date);
      data = data.withSnapshot(
        TimeMath.dateKey(date),
        DaySnapshot(planId: r.planId, mode: r.mode, source: r.source),
      );
      if (i % 3 == 0) {
        data = data.withRecords(
          ActualRecords.withOverride(
            data.records,
            TimeMath.dateKey(date),
            9 * 60, // 09:00 工作 → 学习
            Category.study,
          ),
        );
      }
      if (i % 5 == 0) {
        data = data.withRecords(
          ActualRecords.withOverride(
            data.records,
            TimeMath.dateKey(date),
            13 * 60, // 13:00 工作 → 锻炼
            Category.exercise,
          ),
        );
      }
    }
    return data;
  }

  Future<void> pump(WidgetTester tester, AppData data) async {
    await pumpGoldenApp(
      tester,
      fontReady: fontReady,
      planLabel: data.forDate(now).label,
      view: AppView.summary,
      // 汇总态窗口撑到 720，月历 6 行才放得下。
      size: const Size(1060, 720),
      body: SummaryScreen(data: data, now: now),
    );
  }

  Future<void> shoot(WidgetTester tester, String name) async =>
      shootGolden(tester, name);

  testWidgets('L3 今天：计划/实际双环 + 明细表', (tester) async {
    await pump(tester, withHistory());
    await shoot(tester, 'l3_day.png');
  });

  testWidgets('L3 本周：7 根堆叠柱', (tester) async {
    await pump(tester, withHistory());
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    await shoot(tester, 'l3_week.png');
  });

  testWidgets('L3 本月：日历热图', (tester) async {
    await pump(tester, withHistory());
    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();
    await shoot(tester, 'l3_month.png');
  });

  testWidgets('导出 MD 直接写下载目录，内容含 5 项', (tester) async {
    // 注意：flutter_test 跑在假异步环境里，dart:io 的异步回调不会回来。
    // 测试里所有文件操作都走 *Sync，否则整个用例会静默挂死。
    final dir = Directory.systemTemp.createTempSync('l3export');
    addTearDown(() => dir.deleteSync(recursive: true));
    File? exported;

    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SummaryScreen(
            data: withHistory(),
            now: now,
            downloadDirOverride: dir,
            onExported: (f) => exported = f,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出 MD'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    expect(exported, isNotNull, reason: '不弹目录选择框，直接写文件');
    expect(exported!.path.endsWith('作息分析-2026-11-05-日.md'), isTrue);
    final text = exported!.readAsStringSync();
    expect(text, contains('## 1. 元信息'));
    expect(text, contains('## 2. 当前计划表'));
    expect(text, contains('## 3. 计划时间分配'));
    expect(text, contains('## 4. 计划 vs 实际'));
    expect(text, contains('请重点看偏差集中在哪些分类'));
    expect(text, contains('100.0%'), reason: '分母固定 24 小时');
    expect(text, contains('无数据'), reason: '无数据的日子明确标注');
  });

  group('汇总口径', () {
    test('周从周一开始，共 7 天；月按当月天数', () {
      final week = SummaryModel.datesOf(SummaryPeriod.week, now);
      expect(week.length, 7);
      expect(week.first.weekday, DateTime.monday);
      final month = SummaryModel.datesOf(SummaryPeriod.month, now);
      expect(month.length, 30, reason: '2026 年 11 月有 30 天');
    });

    test('安装之前与未来都是无数据，不画成 0 分钟', () {
      final data = SeedData.build();
      final today = SummaryModel.forDay(data, now, now);
      expect(today.hasData, isTrue, reason: '今天一定有数据');

      final before = SummaryModel.forDay(
        data,
        now.subtract(const Duration(days: 10)),
        now,
      );
      expect(before.hasData, isFalse);
      final future = SummaryModel.forDay(
        data,
        now.add(const Duration(days: 2)),
        now,
      );
      expect(future.hasData, isFalse);
      expect(future.isFuture, isTrue);
    });

    test('纠偏只改当前这一段，偏差之和为 0', () {
      final base = SeedData.build();
      final key = TimeMath.dateKey(now);
      final data = base.withRecords(
        ActualRecords.withOverride(base.records, key, 9 * 60, Category.study),
      );
      final day = SummaryModel.forDay(data, now, now);
      expect(day.overrideCount, 1);
      expect(day.deviation(Category.work), -180);
      expect(day.deviation(Category.study), 180);
      expect(
        Category.values.fold(0, (s, c) => s + day.deviation(c)),
        0,
        reason: '只换分类不改时长，总分钟数守恒',
      );

      final actual = day.actual.firstWhere((b) => b.start == 9 * 60);
      expect(actual.category, Category.study);
      expect(actual.start, 9 * 60);
      expect(actual.end, 12 * 60);
      expect(
        day.plan.firstWhere((b) => b.start == 9 * 60).category,
        Category.work,
        reason: '计划表本身没被改',
      );
    });

    test('导出文件名三种周期各不相同', () {
      expect(reportFileName(now, SummaryPeriod.day), '作息分析-2026-11-05-日.md');
      expect(reportFileName(now, SummaryPeriod.week), '作息分析-2026-11-05-周.md');
      expect(reportFileName(now, SummaryPeriod.month), '作息分析-2026-11.md');
    });

    test('2 小时学习占全天 8.3%，不是 100%', () {
      final only = [
        const DayBlock(
          start: 540,
          end: 660,
          name: '学习',
          category: Category.study,
        ),
      ];
      var data = SeedData.build();
      data = data.withPlanBlocks(data.forDate(now).planId, only);
      final text = buildMarkdown(
        data: data,
        now: now,
        period: SummaryPeriod.day,
      );
      expect(text, contains('8.3%'));
      expect(text, contains('| 学习 | 120 | 2 小时 | 8.3% |'));
    });
  });
}
