import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/day_block.dart';
import 'package:routine_reminder/domain/time_math.dart';

void main() {
  group('时间格式', () {
    test('HH:mm 解析与还原', () {
      expect(TimeMath.parseHm('07:30'), 450);
      expect(TimeMath.parseHm('00:00'), 0);
      expect(TimeMath.parseHm('23:59'), 1439);
      expect(TimeMath.formatHm(450), '07:30');
      expect(TimeMath.formatHm(0), '00:00');
    });

    test('超过 24 小时的分钟数按取模格式化', () {
      expect(TimeMath.formatHm(1860), '07:00');
      expect(TimeMath.formatHm(1440), '00:00');
    });

    test('非法格式直接抛错，不猜', () {
      expect(TimeMath.parseHm('07:30'), 450);
      expect(TimeMath.parseHm('7:30'), 450, reason: '单位数小时也要能读');
      expect(() => TimeMath.parseHm('25:00'), throwsFormatException);
      expect(() => TimeMath.parseHm('0730'), throwsFormatException);
    });

    test('时长格式', () {
      expect(TimeMath.formatDuration(1350), '22h30m');
      expect(TimeMath.formatDuration(120), '2h');
      expect(TimeMath.formatDuration(45), '45m');
    });
  });

  group('空档计算', () {
    test('排满的一天没有空档', () {
      final blocks = SeedData.workday;
      expect(TimeMath.gaps(blocks), isEmpty);
      expect(TimeMath.unplannedMinutes(blocks), 0);
      expect(TimeMath.scheduledMinutes(blocks), TimeMath.minutesPerDay);
    });

    test('删掉 21:30–23:00 后，空档正好是 90 分钟', () {
      final blocks = SeedData.workday
          .where((b) => !(b.start == 1290 && b.end == 1380))
          .toList();
      final gaps = TimeMath.gaps(blocks);
      expect(gaps.length, 1);
      expect(gaps.single.start, 1290);
      expect(gaps.single.end, 1380);
      expect(TimeMath.unplannedMinutes(blocks), 90);
    });

    test('跨零点睡眠的两半都算已占用，后半夜不是空档', () {
      // 只放一块 23:00–07:00，如果只算右半段，00:00–07:00 会被误判成空档
      final sleep = DayBlock(
        start: 23 * 60,
        end: 7 * 60 + 1440,
        name: '睡眠',
        category: SeedData.workday.last.category,
      );
      final gaps = TimeMath.gaps([sleep]);
      expect(gaps.length, 1);
      expect(gaps.single.start, 7 * 60);
      expect(gaps.single.end, 23 * 60);
    });

    test('两块之间的空洞被单独识别', () {
      final a = SeedData.workday.first.copyWith(start: 7 * 60, end: 8 * 60);
      final b = SeedData.workday[1].copyWith(start: 9 * 60, end: 10 * 60);
      final gaps = TimeMath.gaps([a, b]);
      expect(
        gaps.map((g) => '${g.start}-${g.end}').toList(),
        contains('480-540'),
      );
    });
  });

  group('当前块与下一块', () {
    final blocks = SeedData.workday;

    test('晚上 19:32 正在锻炼', () {
      final cur = TimeMath.blockAt(blocks, 19 * 60 + 32);
      expect(cur?.name, '锻炼');
    });

    test('凌晨 02:00 仍在睡眠，跨零点的左半边能命中', () {
      final cur = TimeMath.blockAt(blocks, 2 * 60);
      expect(cur?.name, '睡眠');
    });

    test('23:30 也是睡眠，右半边同样命中', () {
      expect(TimeMath.blockAt(blocks, 23 * 60 + 30)?.name, '睡眠');
    });

    test('19:32 的下一块是 20:00 洗澡', () {
      final next = TimeMath.nextAfter(blocks, 19 * 60 + 32);
      expect(next?.name, '洗澡');
      expect(next?.start, 20 * 60);
    });

    test('一天的起点是 23:00：睡眠排在清单最前', () {
      final sorted = TimeMath.sorted(blocks);
      expect(sorted.first.name, '睡眠');
      expect(TimeMath.sortKey(blocks.last), -60);
    });
  });
}
