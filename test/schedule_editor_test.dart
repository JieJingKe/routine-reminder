import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/domain/schedule_editor.dart';
import 'package:routine_reminder/domain/time_math.dart';

void main() {
  group('吸附与基线', () {
    test('5 分钟吸附，全天 288 格', () {
      expect(ScheduleEditor.snap(0), 0);
      expect(ScheduleEditor.snap(3), 5);
      expect(ScheduleEditor.snap(7), 5);
      expect(ScheduleEditor.snap(8), 10);
      expect(ScheduleEditor.snap(1439), 1440);
      expect(ScheduleEditor.snapDown(1439), 1435);
      expect(ScheduleEditor.snapUp(1436), 1440);
    });

    test('内置的两套表本身合法且排满', () {
      expect(ScheduleEditor.isValid(SeedData.workday), isTrue);
      expect(ScheduleEditor.isValid(SeedData.holiday), isTrue);
      expect(TimeMath.gaps(SeedData.workday), isEmpty);
      expect(TimeMath.gaps(SeedData.holiday), isEmpty);
    });

    test('跨零点睡眠的结束上限自动落在次日 07:00，不用写特判', () {
      final i = SeedData.workday.indexWhere(
        (b) => b.category == Category.sleep,
      );
      expect(ScheduleEditor.maxEnd(SeedData.workday, i), 1860);
    });
  });

  group('验收 #9 / #10：结束边界钳制', () {
    final blocks = SeedData.workday;
    const workIndex = 4; // 09:00–12:00 工作

    test('逆时针拖过开始，停在 start+5，继续拖数值不再变', () {
      final a = ScheduleEditor.withEnd(blocks, workIndex, 8 * 60);
      expect(a.end, 540 + 5);
      final b = ScheduleEditor.withEnd(blocks, workIndex, 0);
      expect(b.end, 540 + 5);
      expect(a.start, 540, reason: '开始时间不能动');
      expect(
        ScheduleEditor.isValid(ScheduleEditor.replaceAt(blocks, workIndex, a)),
        isTrue,
      );
    });

    test('顺时针撞到右侧邻居，停在邻居起点，邻居纹丝不动', () {
      final neighbour = blocks[5]; // 12:00–13:00
      final a = ScheduleEditor.withEnd(blocks, workIndex, 14 * 60);
      expect(a.end, 720);
      final out = ScheduleEditor.replaceAt(blocks, workIndex, a);
      expect(out[5].start, neighbour.start);
      expect(out[5].end, neighbour.end);
      expect(out[5].name, neighbour.name);
    });

    test('最短 5 分钟，不产生零时长或负时长', () {
      final base = <DayBlock>[
        const DayBlock(
          start: 100,
          end: 200,
          name: 'A',
          category: Category.work,
        ),
      ];
      final a = ScheduleEditor.withEnd(base, 0, 0);
      expect(a.duration, 5);
      expect(a.end, 105);
      final b = ScheduleEditor.withStart(base, 0, 1440);
      expect(b.duration, 5);
      expect(b.start, 195);
    });
  });

  group('验收 #11：键盘微调不漂移', () {
    test('连按 10 次 →，累计正好 +50 分钟', () {
      // 先删掉 12:00 的午休，腾出 60 分钟空隙给工作块扩展。
      var blocks = ScheduleEditor.removeAt(SeedData.workday, 5);
      for (var i = 0; i < 10; i++) {
        final next = ScheduleEditor.nudge(
          blocks,
          4,
          direction: 1,
          shift: false,
        );
        blocks = ScheduleEditor.replaceAt(blocks, 4, next);
      }
      expect(blocks[4].end - 720, 50);
      expect(ScheduleEditor.isValid(blocks), isTrue);
    });

    test('撞到邻居后继续按，数值不再变（不累积漂移）', () {
      var blocks = [...SeedData.workday];
      for (var i = 0; i < 20; i++) {
        final next = ScheduleEditor.nudge(
          blocks,
          4,
          direction: 1,
          shift: false,
        );
        blocks = ScheduleEditor.replaceAt(blocks, 4, next);
      }
      expect(blocks[4].end, 720, reason: '12:00 有邻居，一分钟都不该多');
    });

    test('Shift+← 改开始，结束不动（先腾出左侧空隙）', () {
      // 工作日 08:30–09:00 紧贴在 09:00 前面，不删它的话应该被钳住。
      final blocked = ScheduleEditor.nudge(
        SeedData.workday,
        4,
        direction: -1,
        shift: true,
      );
      expect(blocked.start, 540, reason: '撞到左邻居，原地不动');

      final base = ScheduleEditor.removeAt(SeedData.workday, 3);
      final a = ScheduleEditor.nudge(base, 3, direction: -1, shift: true);
      expect(a.start, 540 - 5);
      expect(a.end, 720);
      expect(a.duration, 185);
    });
  });

  group('验收 #13：跨零点平移不断裂', () {
    test('睡眠整体移动后仍是一块，时长不变、两半同分类', () {
      // 删掉 21:30–23:00 的自由，给睡眠起点前面腾出空。
      final base = ScheduleEditor.removeAt(SeedData.workday, 12);
      final i = base.indexWhere((b) => b.category == Category.sleep);
      final before = base[i];

      final moved = ScheduleEditor.movedTo(base, i, 22 * 60 + 30);
      final out = ScheduleEditor.replaceAt(base, i, moved);

      expect(moved.duration, before.duration, reason: '时长必须原样保留');
      expect(moved.category, before.category);
      expect(moved.name, before.name);
      expect(
        out.where((b) => b.category == Category.sleep).length,
        1,
        reason: '不能在 0 点断成两个任务',
      );
      expect(moved.ringPieces().length, 2, reason: '渲染仍是内外各一段');
      expect(ScheduleEditor.isValid(out), isTrue);
    });
  });

  group('验收 #8 / #15：新建', () {
    test('点击空隙任意位置，开始时间都取空隙起点', () {
      final base = ScheduleEditor.removeAt(
        SeedData.workday,
        5,
      ); // 空隙 12:00–13:00
      for (final at in const [721, 750, 779]) {
        final hit = ScheduleEditor.createAt(base, at, Category.study);
        expect(hit, isNotNull);
        expect(
          hit!.blocks[hit.createdIndex].start,
          720,
          reason: '不是点击位置 $at，也不是上一个任务结束时间',
        );
        expect(hit.blocks[hit.createdIndex].duration, 30);
        expect(hit.blocks[hit.createdIndex].remind, isFalse);
      }
    });

    test('空隙不足 30 分钟时取到空隙终点；不足 5 分钟时放弃', () {
      final short = [
        const DayBlock(start: 0, end: 20, name: 'A', category: Category.work),
        const DayBlock(
          start: 40,
          end: 1440,
          name: 'B',
          category: Category.sleep,
        ),
      ];
      final a = ScheduleEditor.createAt(short, 25, Category.study);
      expect(a, isNotNull);
      expect(a!.blocks[a.createdIndex].end, 40);

      final tiny = [
        const DayBlock(start: 0, end: 1437, name: 'A', category: Category.work),
      ];
      expect(ScheduleEditor.createAt(tiny, 1438, Category.study), isNull);
    });

    test('新建 11:30–12:30 横跨内外圈，仍是一个任务', () {
      final base = [
        const DayBlock(start: 0, end: 690, name: '上午', category: Category.work),
        const DayBlock(
          start: 750,
          end: 1440,
          name: '下午',
          category: Category.work,
        ),
      ];
      final hit = ScheduleEditor.createAt(base, 700, Category.study);
      expect(hit, isNotNull);
      final created = hit!.blocks[hit.createdIndex];
      expect(created.start, 690);
      expect(created.end, 720, reason: '空隙只有 30 分钟，取到空隙终点');
      expect(created.ringPieces().length, 1);

      // 把右邻居挪走，再拖结束到 12:30，验证跨圈两段联动。
      final roomy = ScheduleEditor.removeAt(
        hit.blocks,
        hit.blocks.indexWhere((b) => b.start == 750),
      );
      final idx = roomy.indexOf(created);
      final stretched = ScheduleEditor.withEnd(roomy, idx, 750);
      expect(stretched.end, 750);
      expect(stretched.ringPieces().length, 2);
      expect(stretched.ringPieces().map((p) => p.side).toSet().length, 2);
    });

    test('清空后从 00:00 开始逐块新建', () {
      final hit = ScheduleEditor.createAt(const [], 0, Category.study);
      expect(hit, isNotNull);
      expect(hit!.blocks[hit.createdIndex].start, 0);
      expect(hit.blocks[hit.createdIndex].end, 30);
      expect(TimeMath.unplannedMinutes(hit.blocks), 1410);
    });
  });

  group('验收 #25：清单里手输时间非法要回退', () {
    test('结束早于开始、格式错、越界都返回 null', () {
      const i = 4;
      expect(
        ScheduleEditor.parseTimeEdit(
          SeedData.workday,
          i,
          '08:00',
          isStart: false,
        ),
        isNull,
        reason: '倒挂且撞到自己的开始，必须拒绝',
      );
      expect(
        ScheduleEditor.parseTimeEdit(
          SeedData.workday,
          i,
          'abc',
          isStart: false,
        ),
        isNull,
      );
      expect(
        ScheduleEditor.parseTimeEdit(
          SeedData.workday,
          i,
          '25:00',
          isStart: false,
        ),
        isNull,
      );
      expect(
        ScheduleEditor.parseTimeEdit(
          SeedData.workday,
          i,
          '12:5',
          isStart: false,
        ),
        isNull,
      );
    });

    test('合法值生效并吸附', () {
      final a = ScheduleEditor.parseTimeEdit(
        SeedData.workday,
        4,
        '11:30',
        isStart: false,
      );
      expect(a, isNotNull);
      expect(a!.end, 690);
    });

    test('跨零点块手输结束时间 07:00 不会被当成倒挂', () {
      final i = SeedData.workday.indexWhere(
        (b) => b.category == Category.sleep,
      );
      final a = ScheduleEditor.parseTimeEdit(
        SeedData.workday,
        i,
        '06:00',
        isStart: false,
      );
      expect(a, isNotNull);
      expect(a!.end, 1800, reason: '次日 06:00 = 1440 + 360');
    });
  });

  test('isValid 能抓出重叠', () {
    const overlap = [
      DayBlock(start: 0, end: 120, name: 'A', category: Category.work),
      DayBlock(start: 60, end: 180, name: 'B', category: Category.work),
    ];
    expect(ScheduleEditor.isValid(overlap), isFalse);

    const touching = [
      DayBlock(start: 0, end: 120, name: 'A', category: Category.work),
      DayBlock(start: 120, end: 180, name: 'B', category: Category.work),
    ];
    expect(ScheduleEditor.isValid(touching), isTrue, reason: '端点相接是允许的');
  });
}
