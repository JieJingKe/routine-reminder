import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/ui/ring/dual_ring.dart';
import 'package:routine_reminder/ui/ring/ring_geometry.dart';

void main() {
  group('环的几何', () {
    test('12 点方向是 0 弧度，且内外圈共用同一套角度', () {
      expect(RingGeometry.angleOf(0), closeTo(-math.pi / 2, 1e-9));
      expect(RingGeometry.angleOf(720), closeTo(-math.pi / 2, 1e-9));
      expect(RingGeometry.angleOf(1440), closeTo(-math.pi / 2, 1e-9));
    });

    test('00:00 落在正上方，06:00 在正下方，18:00 也在正下方', () {
      final top = RingGeometry.polar(56, 0);
      expect(top.dx, closeTo(170, 0.001));
      expect(top.dy, closeTo(114, 0.001));

      final six = RingGeometry.polar(56, 360);
      expect(six.dx, closeTo(170, 0.001));
      expect(six.dy, closeTo(226, 0.001));

      final eighteen = RingGeometry.polar(112, 1080);
      expect(eighteen.dy, closeTo(282, 0.001));
    });

    test('07:00 在内圈左下（验收 #5 的方位描述是笔误，按公式算）', () {
      final p = RingGeometry.polar(76, 420);
      expect(p.dx, lessThan(170), reason: '左侧');
      expect(p.dy, greaterThan(170), reason: '下方');
    });
  });

  group('跨零点块的分段', () {
    test('23:00–07:00 切成外圈尾巴 + 内圈头部两块', () {
      final sleep = DayBlock(
        start: 1380,
        end: 420 + 1440,
        name: '睡眠',
        category: SeedData.workday.last.category,
      );
      final pieces = sleep.ringPieces();
      expect(pieces.length, 2);
      expect(pieces[0].side, RingSide.outer);
      expect(pieces[0].from, 1380);
      expect(pieces[0].to, 1440);
      expect(pieces[1].side, RingSide.inner);
      expect(pieces[1].from, 0);
      expect(pieces[1].to, 420);
    });

    test('普通块只落在一圈上', () {
      final work = DayBlock(
        start: 540,
        end: 720,
        name: '工作',
        category: SeedData.workday[4].category,
      );
      expect(work.ringPieces().single.side, RingSide.inner);
    });

    test('色段弧长扣掉 0.6px 的缝，不会画成整整 180 度', () {
      final arc = RingGeometry.arcOf(RingSide.inner, 0, 720);
      final full = 2 * math.pi;
      expect(arc.sweep, lessThan(full));
      expect(arc.sweep, greaterThan(full - 0.02));
    });
  });

  group('鼠标命中', () {
    // 直径给 340（= canvasSize），缩放就是 1，可以直接拿画布坐标当鼠标坐标。
    ({int minute, DayBlock? block})? hitAt(
      int minute, {
      double r = 76,
      List<DayBlock>? blocks,
    }) {
      return RingGeometry.hitTest(
        RingGeometry.polar(r, minute.toDouble()),
        340,
        blocks ?? SeedData.workday,
      );
    }

    test('内圈 10:30 命中工作块，且分钟数能回读', () {
      final hit = hitAt(630);
      expect(hit, isNotNull);
      expect(hit!.block?.category, Category.work);
      expect(hit.minute, closeTo(630, 1));
    });

    test('内圈 03:00 命中跨零点睡眠的前半段', () {
      final hit = hitAt(180);
      expect(hit?.block?.category, Category.sleep);
      expect(hit?.block?.start, 1380, reason: '起点仍是昨晚 23:00');
    });

    test('外圈 14:00 命中的是下午工作，分钟数要加上 720', () {
      final hit = hitAt(840, r: 132);
      expect(hit?.block?.category, Category.work);
      expect(hit?.minute, closeTo(840, 1));
    });

    test('圆心和两环之间的缝都算没碰到', () {
      expect(
        RingGeometry.hitTest(const Offset(170, 170), 340, SeedData.workday),
        isNull,
      );
      expect(hitAt(600, r: 104), isNull, reason: '两条环之间是空的');
      expect(hitAt(600, r: 200), isNull, reason: '环外');
    });

    test('落在空档上返回结果但 block 为 null', () {
      final only = [
        DayBlock(start: 540, end: 720, name: '上午工作', category: Category.work),
      ];
      final hit = hitAt(300, blocks: only);
      expect(hit, isNotNull, reason: '碰到环了');
      expect(hit!.block, isNull, reason: '但这里没排东西');
    });
  });

  testWidgets('双环能渲染，不抛异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF161A2A),
          body: Center(
            child: DualRing(
              blocks: SeedData.workday,
              nowMinute: 19 * 60 + 32,
              diameter: 340,
              showCenter: true,
              centerTitle: '22h30m',
              centerSub: '已排满',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(DualRing), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标移进环里会出提示条，移出就消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF161A2A),
          body: Center(
            child: DualRing(
              blocks: SeedData.workday,
              nowMinute: 19 * 60 + 32,
              diameter: 340,
            ),
          ),
        ),
      ),
    );

    // 10:30 那块是工作。直径 340、画布 340，所以半径直接是画布单位。
    final center = tester.getCenter(find.byType(DualRing));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(center + const Offset(-54, -54));
    await tester.pumpAndSettle();
    expect(find.textContaining('工作'), findsWidgets);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('未安排'), findsNothing);
  });
}
