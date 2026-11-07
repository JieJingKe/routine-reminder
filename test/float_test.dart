import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart';

import 'package:routine_reminder/app/float_position.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/float/float_geometry.dart';
import 'package:routine_reminder/float/float_protocol.dart';
import 'package:routine_reminder/float/float_text.dart';

void main() {
  group('单圈几何', () {
    test('0 点在正上方，6 点在右，12 点在下，18 点在左', () {
      expect(FloatGeometry.angleOf(0), closeTo(-1.5708, 0.001));
      expect(FloatGeometry.angleOf(360), closeTo(0, 0.001));
      expect(FloatGeometry.angleOf(720), closeTo(1.5708, 0.001));
      expect(FloatGeometry.angleOf(1080), closeTo(3.1416, 0.001));
    });

    test('跨零点的块拆成两段，不合并', () {
      expect(FloatGeometry.pieces(1380, 1860), [
        (from: 1380, to: 1440),
        (from: 0, to: 420),
      ]);
      expect(FloatGeometry.pieces(480, 540), [(from: 480, to: 540)]);
    });
  });

  group('中心文案', () {
    test('任务名超过 5 个字留 4 个加省略号', () {
      expect(floatTaskName('看书'), '看书');
      expect(floatTaskName('起床洗漱'), '起床洗漱');
      expect(floatTaskName('学习专业技能'), '学习专业…');
    });

    test('剩余时间格式与原型一致', () {
      expect(floatRemaining(28), '还剩 28m');
      expect(floatRemaining(60), '还剩 1h00');
      expect(floatRemaining(150), '还剩 2h30');
    });

    test('当前块显示名称与剩余时间', () {
      final blocks = [
        const DayBlock(
          start: 480,
          end: 540,
          name: '工作',
          category: Category.work,
        ),
      ];
      final center = floatCenterText(blocks, 480);
      expect(center.title, '工作');
      expect(center.sub, '还剩 1h00');
    });

    test('空档显示下一个任务的时刻与名称', () {
      final blocks = [
        const DayBlock(
          start: 480,
          end: 540,
          name: '工作',
          category: Category.work,
        ),
        const DayBlock(
          start: 700,
          end: 760,
          name: '学习专业技能',
          category: Category.study,
        ),
      ];
      final center = floatCenterText(blocks, 600);
      expect(center.title, '空档');
      expect(center.sub, '11:40 学习专…');
    });
  });

  group('状态包', () {
    test('跨零点块 JSON 往返不丢字段', () {
      const snapshot = FloatSnapshot(
        blocks: [
          DayBlock(
            start: 1380,
            end: 1860,
            name: '睡眠',
            category: Category.sleep,
            remind: true,
          ),
        ],
        theme: 'light',
      );

      final restored = FloatSnapshot.fromJson(snapshot.toJson());
      expect(restored.theme, 'light');
      expect(restored.blocks.single.start, 1380);
      expect(restored.blocks.single.end, 1860);
      expect(restored.blocks.single.name, '睡眠');
      expect(restored.blocks.single.category, Category.sleep);
      expect(restored.blocks.single.remind, isTrue);
    });
  });

  group('记住的坐标校验', () {
    const primary = Display(
      id: 'primary',
      size: Size(1920, 1080),
      visiblePosition: Offset.zero,
      visibleSize: Size(1920, 1040),
    );
    const second = Display(
      id: 'second',
      size: Size(1920, 1080),
      visiblePosition: Offset(1920, 0),
      visibleSize: Size(1920, 1040),
    );

    test('落在任一屏幕内就沿用', () {
      expect(
        resolveFloatPosition(
          x: 100,
          y: 100,
          displays: const [primary, second],
          primary: primary,
        ),
        const Offset(100, 100),
      );
      expect(
        resolveFloatPosition(
          x: 2000,
          y: 120,
          displays: const [primary, second],
          primary: primary,
        ),
        const Offset(2000, 120),
      );
    });

    test('副屏拔掉后回到主屏右下角，距边缘 24px', () {
      expect(
        resolveFloatPosition(
          x: 2600,
          y: 120,
          displays: const [primary],
          primary: primary,
        ),
        const Offset(1728, 848),
      );
    });

    test('从没拖过时用主屏右下角', () {
      expect(
        resolveFloatPosition(displays: const [primary], primary: primary),
        const Offset(1728, 848),
      );
    });
  });
}
