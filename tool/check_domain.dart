// 这是一个命令行探针，print 就是它的输出方式。
// ignore_for_file: avoid_print

// 领域逻辑自检。不依赖 Flutter，可以直接 `dart run tool/check_domain.dart`。
//
// 这不是给 CI 用的单测（单测在 test/ 里），而是一个"看得见结果"的探针：
// 环上画的东西、卡片上的数字，最终都来自这里算出来的值。
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/domain/category.dart';
import 'package:routine_reminder/domain/day_mode.dart';
import 'package:routine_reminder/domain/stats.dart';
import 'package:routine_reminder/domain/time_math.dart';

var failures = 0;

void check(String label, bool ok, [String detail = '']) {
  print(
    '${ok ? '  ok  ' : '  FAIL'}  $label${detail.isEmpty ? '' : '  →  $detail'}',
  );
  if (!ok) failures++;
}

void main() {
  final workday = SeedData.workday;

  print('— 内置表 —');
  check('工作日 14 块', workday.length == 14, '${workday.length}');
  check(
    '节假日 15 块',
    SeedData.holiday.length == 15,
    '${SeedData.holiday.length}',
  );

  final totals = DayTotals.of(workday);
  print(
    '  已安排 ${TimeMath.formatDuration(totals.scheduled)} / '
    '未安排 ${TimeMath.formatDuration(totals.unplanned)}',
  );
  check('排满无空档', totals.unplanned == 0);
  check('已安排 24 小时', totals.scheduled == 1440);

  print('— 学习与锻炼 —');
  print(
    '  学习 ${totals.minutesOf(Category.study)} 分钟 / '
    '锻炼 ${totals.minutesOf(Category.exercise)} 分钟',
  );
  check('学习 60 分钟', totals.minutesOf(Category.study) == 60);
  check('锻炼 60 分钟', totals.minutesOf(Category.exercise) == 60);

  print('— 当前块（跨零点） —');
  for (final hm in ['02:00', '07:15', '12:30', '19:32', '23:30']) {
    final minute = TimeMath.parseHm(hm);
    final cur = TimeMath.blockAt(workday, minute);
    final left = cur == null
        ? 0
        : cur.end - (minute < cur.start ? minute + 1440 : minute);
    print('  $hm  ${cur?.name ?? '（空档）'}  还剩 $left 分钟');
    check('$hm 有当前块', cur != null);
    check('$hm 剩余时间合理', left > 0 && left <= 1440, '$left');
  }

  print('— 下一块 —');
  final next = TimeMath.nextAfter(workday, TimeMath.parseHm('19:32'));
  print('  19:32 之后是 ${next?.name} @ ${TimeMath.formatHm(next?.start ?? 0)}');
  check('下一块是洗澡', next?.name == '洗澡');

  print('— 23:00 起点排序 —');
  final sorted = TimeMath.sorted(workday);
  print('  首块 ${sorted.first.name}，末块 ${sorted.last.name}');
  check('首块是睡眠（23:00）', sorted.first.name == '睡眠');

  print('— 空档识别 —');
  final withHole = workday
      .where((b) => !(b.start == 1290 && b.end == 1380))
      .toList();
  final gaps = TimeMath.gaps(withHole);
  print(
    '  删掉 21:30–23:00 后：${gaps.map((g) => '${TimeMath.formatHm(g.start)}–${TimeMath.formatHm(g.end)}').join(', ')}',
  );
  check('只剩一处空档', gaps.length == 1);
  check('空档 90 分钟', gaps.isNotEmpty && gaps.single.minutes == 90);

  print('— 规则栈 —');
  final data = SeedData.build();
  for (final d in [DateTime(2026, 11, 5), DateTime(2026, 11, 7)]) {
    final r = data.rules.resolve(d);
    print('  ${d.month}/${d.day}  ${r.label}');
  }
  check(
    '周四工作日',
    data.rules.resolve(DateTime(2026, 11, 5)).mode == DayMode.workday,
  );
  check(
    '周六节假日',
    data.rules.resolve(DateTime(2026, 11, 7)).mode == DayMode.holiday,
  );

  print('— JSON 往返 —');
  final json = data.toJson();
  final again = data.blocksForMode(DayMode.workday);
  check('工作日块数一致', again.length == 14);
  final sleepJson =
      (json['plans'][0]['blocks'] as List).last as Map<String, dynamic>;
  print('  睡眠序列化：${sleepJson['start']} → ${sleepJson['end']}');
  check('跨零点写回 07:00', sleepJson['end'] == '07:00');

  print('');
  print(failures == 0 ? '全部通过' : '$failures 项不通过');
}
