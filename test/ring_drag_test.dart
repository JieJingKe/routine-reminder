import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/domain/schedule_editor.dart';
import 'package:routine_reminder/ui/ring/dual_ring.dart';
import 'package:routine_reminder/ui/ring/ring_geometry.dart';

/// 直径给 340（等于画布尺寸），缩放为 1，画布坐标可直接当 widget 内坐标用。
const _d = 340.0;
const _outerMid = 132.0;

Offset _at(int minute, {double r = _outerMid}) {
  final p = RingGeometry.polar(r, minute.toDouble());
  return p - const Offset(RingGeometry.center, RingGeometry.center);
}

void main() {
  group('键盘微调不漂移', () {
    test('连按 10 次 → 正好 50 分钟，不累积浮点误差', () {
      var blocks = SeedData.workday;
      // 19:00–20:00 锻炼，下标 9。后面 20:00 有洗澡，所以先往回缩。
      const i = 9;
      for (var n = 0; n < 10; n++) {
        final next = ScheduleEditor.nudge(
          blocks,
          i,
          direction: -1,
          shift: false,
        );
        blocks = ScheduleEditor.replaceAt(blocks, i, next);
      }
      expect(blocks[i].start, 19 * 60, reason: '起点不动');
      expect(blocks[i].end, 20 * 60 - 50);
      expect(blocks[i].duration, 10, reason: '最短 5 分钟之上');
    });

    test('撞到上一块后继续按，数值不再变化', () {
      var blocks = SeedData.workday;
      const i = 9;
      for (var n = 0; n < 40; n++) {
        blocks = ScheduleEditor.replaceAt(
          blocks,
          i,
          ScheduleEditor.nudge(blocks, i, direction: -1, shift: false),
        );
      }
      expect(blocks[i].end, 19 * 60 + 5, reason: '停在 19:05，不会翻过起点把任务倒过来');
      expect(ScheduleEditor.isValid(blocks), isTrue);
    });

    test('Shift 改开始，结束保持不动', () {
      final out = ScheduleEditor.nudge(
        SeedData.workday,
        9,
        direction: 1,
        shift: true,
      );
      expect(out.start, 19 * 60 + 5);
      expect(out.end, 20 * 60);
      expect(out.duration, 55);
    });
  });

  group('环上拖拽', () {
    testWidgets('拖结束边界：吸附到 5 分钟，且不推动邻居', (tester) async {
      late List<DayBlock> current;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: _Harness(
                onBlocks: (b) => current = b,
                child: (blocks, onChanged) => DualRing(
                  blocks: blocks,
                  nowMinute: 19 * 60 + 32,
                  diameter: _d,
                  editing: true,
                  onBlocksChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DualRing));
      // 19:00–20:00 锻炼在下标 9。起点选在 19:56（结束边界内侧 4 分钟），
      // 正好落在「结束手柄」的 11px 容差里，又不会命中 20:00 的下一块。
      final from = center + _at(1196);
      final to = center + _at(1166);
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();

      final exercise = current.firstWhere((b) => b.start == 19 * 60);
      expect(
        exercise.end,
        19 * 60 + 30,
        reason: '从 20:00 往回拖 30 分钟，吸附后是 19:30',
      );
      expect(exercise.start, 19 * 60, reason: '起点不动');
      expect(
        current.firstWhere((b) => b.start == 20 * 60).start,
        20 * 60,
        reason: '20:00 洗澡那块纹丝不动',
      );
      expect(ScheduleEditor.isValid(current), isTrue);
    });

    testWidgets('L1 只读态拖不动环', (tester) async {
      final original = SeedData.workday;
      var touched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DualRing(
                blocks: original,
                nowMinute: 19 * 60 + 32,
                diameter: _d,
                onBlocksChanged: (_) => touched = true,
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DualRing));
      await tester.dragFrom(center + _at(1196), _at(1166) - _at(1196));
      await tester.pumpAndSettle();
      expect(touched, isFalse, reason: 'editing 默认 false，不响应拖拽');
    });

    testWidgets('跨零点块的结束手柄落在内圈，不是外圈的 23:00', (tester) async {
      late List<DayBlock> current;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: _Harness(
                onBlocks: (b) => current = b,
                child: (blocks, onChanged) => DualRing(
                  blocks: blocks,
                  nowMinute: 2 * 60,
                  diameter: _d,
                  editing: true,
                  onBlocksChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DualRing));
      // 23:00 睡眠的可见结束边界在次日 07:00 = 内圈 420 分。
      // 往回拖 40 分钟应该缩到 06:20；顺时针则会被 07:00 起床挡住，这是对的。
      final from = center + _at(416, r: 76);
      final to = center + _at(376, r: 76);
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();

      final sleep = current.firstWhere((b) => b.start == 23 * 60);
      expect(sleep.end, 6 * 60 + 20 + 1440);
      expect(sleep.crossesMidnight, isTrue);
      expect(ScheduleEditor.isValid(current), isTrue);
    });

    testWidgets('拖过 12 点接缝不会跳变一整天', (tester) async {
      late List<DayBlock> current;
      const seed = [
        DayBlock(
          start: 1410, // 23:30
          end: 1500, // 次日 01:00
          name: '跨零点',
          category: Category.sleep,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: _SingleHarness(seed: seed, onBlocks: (b) => current = b),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DualRing));
      // 从内圈 20 分逆时针拖到 680 分，跨过 0/720 的接缝，实际只走了 -60 分。
      // 若没把 delta 折回 ±360，这里会算出 +660 分钟，任务被拖到第二天去。
      final from = center + _at(20, r: 76);
      final to = center + _at(680, r: 76);
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();

      expect(current.single.start, 1350, reason: '起点从 23:30 变成 22:30');
      expect(current.single.duration, 90, reason: '时长不变');
      expect(ScheduleEditor.isValid(current), isTrue);
    });
  });
}

typedef _RingBuilder = Widget Function(
  List<DayBlock> blocks,
  ValueChanged<List<DayBlock>> onChanged,
);

class _Harness extends StatefulWidget {
  const _Harness({required this.child, required this.onBlocks});

  final _RingBuilder child;
  final ValueChanged<List<DayBlock>> onBlocks;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<DayBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = SeedData.workday;
    widget.onBlocks(_blocks);
  }

  @override
  Widget build(BuildContext context) => widget.child(_blocks, (next) {
    setState(() => _blocks = next);
    widget.onBlocks(next);
  });
}

/// 只有一块、留着大片空档的测试台，专门用来验证「能整块平移」的场景。
class _SingleHarness extends StatefulWidget {
  const _SingleHarness({required this.seed, required this.onBlocks});

  final List<DayBlock> seed;
  final ValueChanged<List<DayBlock>> onBlocks;

  @override
  State<_SingleHarness> createState() => _SingleHarnessState();
}

class _SingleHarnessState extends State<_SingleHarness> {
  late List<DayBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = widget.seed;
    widget.onBlocks(_blocks);
  }

  @override
  Widget build(BuildContext context) => DualRing(
    blocks: _blocks,
    nowMinute: 2 * 60,
    diameter: _d,
    editing: true,
    onBlocksChanged: (next) {
      setState(() => _blocks = next);
      widget.onBlocks(next);
    },
  );
}
