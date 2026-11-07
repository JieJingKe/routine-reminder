import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/design/tokens.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/ui/ring/dual_ring.dart';

/// 把双环渲染成 PNG 存成基线，用来和 `04-截图/环细节.jpg` 并排比。
///
/// 第一次跑要加 `--update-goldens` 生成基线；之后每次跑都会拿当前渲染和基线比，
/// 环画歪了、颜色串了、跨零点断了，都会直接报 diff，不用靠眼睛盯。
///
/// 测试环境的默认字体是 Ahem（每个字符都是一个实心方块），所以这里显式加载
/// Windows 自带的 simhei.ttf，否则环里的文字全是色块。加载失败时跳过整组测试
/// —— 字形不该成为 CI 上的失败原因，几何才是。
void main() {
  const fontFamily = 'RoutineReminderTestCJK';
  var fontReady = false;

  setUpAll(() async {
    final file = File(r'C:\Windows\Fonts\simhei.ttf');
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(fontFamily)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
    fontReady = true;
  });

  Future<void> mount(
    WidgetTester tester, {
    required List<DayBlock> blocks,
    required int nowMinute,
    required String title,
    required String sub,
  }) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: fontReady ? fontFamily : null,
          ),
          home: Material(
            color: Palette.surface,
            child: Center(
              child: DualRing(
                blocks: blocks,
                nowMinute: nowMinute,
                diameter: 380,
                showCenter: true,
                centerTitle: title,
                centerSub: sub,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shoot(
    WidgetTester tester, {
    required String name,
    required List<DayBlock> blocks,
    required int nowMinute,
    required String title,
    required String sub,
  }) async {
    await mount(
      tester,
      blocks: blocks,
      nowMinute: nowMinute,
      title: title,
      sub: sub,
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/$name'),
    );
  }

  testWidgets('工作日 19:32（当前块是锻炼）', (tester) async {
    await shoot(
      tester,
      name: 'ring_workday.png',
      blocks: SeedData.workday,
      nowMinute: 19 * 60 + 32,
      title: '14h20',
      sub: '已排满',
    );
  });

  testWidgets('休息日 02:00（跨零点，当前块是睡眠）', (tester) async {
    await shoot(
      tester,
      name: 'ring_holiday.png',
      blocks: SeedData.holiday,
      nowMinute: 2 * 60,
      title: '14h20',
      sub: '已排满',
    );
  });

  testWidgets('鼠标停在 10:30 的工作块上（其余压暗 + 名称提示）', (tester) async {
    await mount(
      tester,
      blocks: SeedData.workday,
      nowMinute: 19 * 60 + 32,
      title: '14h20',
      sub: '已排满',
    );

    // 环直径 380、画布 340，缩放 1.1176；内圈中径 76 → 屏幕半径约 85。
    // 10:30 在内圈的左上 45°，即 (-60, -60)。
    final center = tester.getCenter(find.byType(DualRing));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center + const Offset(-60, -60));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/ring_hover.png'),
    );
  });
}
