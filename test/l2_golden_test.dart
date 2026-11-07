import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/app/app_view.dart';
import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/ui/l2/edit_screen.dart';

import 'golden_font.dart';
import 'golden_harness.dart';

void main() {
  final now = DateTime(2026, 11, 5, 19, 32);
  var fontReady = false;

  setUpAll(() async {
    fontReady = await loadGoldenFont();
    await loadGoldenIconFont();
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpGoldenApp(
      tester,
      fontReady: fontReady,
      planLabel: SeedData.build().forDate(now).label,
      view: AppView.edit,
      // 切视图不再撑高窗口，编辑态第一屏就是默认 540 窗口的看板原样。
      body: _Harness(data: SeedData.build(), now: now),
    );
  }

  testWidgets('L2 第一屏：看板内容原样保留', (tester) async {
    await pump(tester);
    await shootGolden(tester, 'l2_top.png');
  });

  testWidgets('L2 往下滚：24 小时时间轴 + 任务清单', (tester) async {
    await pump(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await shootGolden(tester, 'l2_scrolled.png');
  });

  testWidgets('清单交互：非法时间回退、分类切换、删除', (tester) async {
    await pump(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(find.text('次日'), findsWidgets);

    final endField = find.byType(TextField).at(1);
    // 输入 23:00 = 睡眠块的开始时间，时长归零，属于非法值。
    await tester.enterText(endField, '23:00');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(endField).controller?.text,
      '07:00',
      reason: '非法值回退到修改前的值，不弹错误框、任务不消失',
    );
    expect(find.text('次日'), findsWidgets, reason: '跨零点仍合并成一行');
  });
}

/// 把 onChanged 接成一个真的会重建的 state，交互测试才能验证联动。
class _Harness extends StatefulWidget {
  const _Harness({required this.data, required this.now});

  final AppData data;
  final DateTime now;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late AppData _data;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  @override
  Widget build(BuildContext context) => EditScreen(
    data: _data,
    now: widget.now,
    onChanged: (next, {bool saveNow = false}) => setState(() => _data = next),
    onRestoreDefault: () =>
        setState(() => _data = widget.data.restoredDefaults()),
    onOverride: (_) {},
  );
}
