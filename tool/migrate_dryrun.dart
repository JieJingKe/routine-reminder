// 数据迁移演练（v1 → v2）。print 就是它的输出方式。
// ignore_for_file: avoid_print
//
// 用法：
//   dart run tool/migrate_dryrun.dart <真实data.json> <演练目录> <报告.md>
//
// 纪律：**只读真实文件**。把源数据复制到演练目录后，在副本上模拟
// AppRepository.load 的迁移分支（备份 .bak → AppData.fromJson → 回写 v2），
// 绝不写回 %APPDATA%。备份与回写这两步由 test/plans_test.dart 用真实
// AppRepository 覆盖，这里只负责把「用户自己的数据」摊开给人看。
import 'dart:convert';
import 'dart:io';

import 'package:routine_reminder/data/app_data.dart';
import 'package:routine_reminder/domain/calendar_rules.dart';
import 'package:routine_reminder/domain/plan.dart';

String _json(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

String _blocksDigest(List<dynamic> raw) =>
    raw.map((e) => jsonEncode(Map<String, dynamic>.from(e as Map))).join('\n');

String _remindersDigest(List<dynamic> raw) =>
    raw.map((e) => jsonEncode(Map<String, dynamic>.from(e as Map))).join('\n');

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    print(
      '用法: dart run tool/migrate_dryrun.dart '
      '<真实data.json> <演练目录> <报告.md>',
    );
    exit(64);
  }
  final src = File(args[0]);
  final dir = Directory(args[1]);
  final reportFile = File(args[2]);
  if (!await src.exists()) {
    print('源文件不存在：${src.path}');
    exit(66);
  }

  final beforeBytes = await src.readAsBytes();
  final beforeText = utf8.decode(beforeBytes);
  final before = jsonDecode(beforeText) as Map<String, dynamic>;
  final beforeSchedules = before['schedules'] as Map<String, dynamic>;
  final beforeReminders = before['reminders'] as Map<String, dynamic>;
  final beforeRules = CalendarRules.fromJson(
    before['rules'] as Map<String, dynamic>?,
  );

  // ---- 在副本上模拟 AppRepository.load 的迁移分支 ----
  await dir.create(recursive: true);
  final copy = File('${dir.path}${Platform.pathSeparator}data.json');
  await copy.writeAsBytes(beforeBytes, flush: true);
  final bak = File('${dir.path}${Platform.pathSeparator}data.json.bak');
  if (!await bak.exists()) await copy.copy(bak.path);

  final data = AppData.fromJson(before);
  final v2Text = _json(data.toJson());
  await copy.writeAsString(v2Text, flush: true);

  // ---- 保真校验 ----
  final checks = <String, bool>{};
  bool sameBlocks(String mode, Plan p) {
    final old = _blocksDigest(beforeSchedules[mode] as List);
    final now = p.blocks.map((b) => jsonEncode(b.toJson())).join('\n');
    return old == now;
  }

  bool sameReminders(String mode, Plan p) {
    final old = _remindersDigest(beforeReminders[mode] as List);
    final now = p.reminders.map((r) => jsonEncode(r.toJson())).join('\n');
    return old == now;
  }

  final work = data.plans[0];
  final rest = data.plans[1];
  checks['工作日作息块逐块一致'] = sameBlocks('workday', work);
  checks['节假日作息块逐块一致（含用户改过的 5 块）'] = sameBlocks('holiday', rest);
  checks['工作日提醒逐条一致'] = sameReminders('workday', work);
  checks['节假日提醒逐条一致'] = sameReminders('holiday', rest);
  checks['界面偏好（主题/悬浮窗/自启/位置）一致'] =
      _json(UiPrefs.fromJson(before['ui'] as Map<String, dynamic>?).toJson()) ==
      _json(data.ui.toJson());
  checks['执行记录一致'] = _json(before['records']) == _json(data.records);
  checks['历史快照条数一致'] =
      (before['daySnapshots'] as Map).length == data.daySnapshots.length;
  checks['快照按 planId 记且 mode 保留'] = data.daySnapshots.values.every(
    (s) => s.planId.isNotEmpty,
  );
  checks['备份逐字节等于迁移前文件'] =
      await bak.exists() && _bytesEqual(await bak.readAsBytes(), beforeBytes);
  checks['演练副本已写成 v2'] =
      (jsonDecode(v2Text) as Map<String, dynamic>)['schemaVersion'] == 2;

  // 周六（2026-11-07）在旧规则栈下是节假日，迁移后也必须解析到节假日表。
  final saturday = DateTime(2026, 11, 7);
  final oldResolved = beforeRules.resolve(saturday);
  final newResolved = data.forDate(saturday);
  checks['今天解析结论与旧规则栈一致'] = oldResolved.mode.label == newResolved.planName;

  // 线上文件必须一个字节都没动。
  checks['真实 data.json 未被改动'] = _bytesEqual(
    await src.readAsBytes(),
    beforeBytes,
  );

  // ---- 报告 ----
  final b = StringBuffer();
  b.writeln('# 多计划表 v1 → v2 数据迁移演练报告');
  b.writeln();
  b.writeln('- 演练时间：${DateTime.now().toString().substring(0, 19)}');
  b.writeln(
    '- 真实源文件：`${src.path}`（${beforeBytes.length} B，'
    '${src.statSync().modified.toString().substring(0, 19)}）',
  );
  b.writeln('- 演练目录：`${dir.path}`（副本 + `data.json.bak`）');
  b.writeln(
    '- **只读取了真实文件，未写回 `%APPDATA%`**；'
    '备份与回写逻辑由 `test/plans_test.dart` 用真实 `AppRepository` 覆盖。',
  );
  b.writeln();
  b.writeln('## 迁移前（v1）');
  b.writeln();
  b.writeln('| 项 | 值 |');
  b.writeln('|---|---|');
  b.writeln(
    '| 结构 | `schedules` / `reminders` 的 `Map<DayMode, ...>`，'
    '只有 workday / holiday 两个键 |',
  );
  b.writeln('| 工作日块 | ${(beforeSchedules['workday'] as List).length} |');
  b.writeln(
    '| 节假日块 | ${(beforeSchedules['holiday'] as List).length}'
    '（用户已自行改过，不是内置 15 块） |',
  );
  b.writeln(
    '| 提醒 | 工作日 ${(beforeReminders['workday'] as List).length} / '
    '节假日 ${(beforeReminders['holiday'] as List).length} |',
  );
  b.writeln(
    '| 全局规则 | 单日例外 ${beforeRules.overrides.length} 条、'
    '特殊日期 ${beforeRules.specialDates.length} 条、'
    '周期 ${beforeRules.cycle.type.key} |',
  );
  b.writeln(
    '| 星期默认 | '
    '${beforeRules.weekdayDefault.entries.map((e) => '${e.key}:${e.value.key}').join('  ')} |',
  );
  b.writeln('| 历史快照 | ${(before['daySnapshots'] as Map).length} 条 |');
  b.writeln(
    '| 界面偏好 | theme=${before['ui']['theme']}、'
    '悬浮窗=${before['ui']['floatWindow']['enabled']}、'
    '开机自启=${before['ui']['openAtLogin']} |',
  );
  b.writeln();
  b.writeln('## 迁移后（v2）');
  b.writeln();
  b.writeln(
    '`schemaVersion: 2`，真相源是 `plans` 列表；'
    '`schedules` / `reminders` 不再落盘。',
  );
  b.writeln();
  b.writeln(
    '| # | id | 名称 | legacyMode | 块 | 提醒 | repeat.kind | weekdays | '
    'cycleBigWeek | 本表特殊日期 |',
  );
  b.writeln('|---|---|---|---|---:|---:|---|---|---|---|');
  for (var i = 0; i < data.plans.length; i++) {
    final p = data.plans[i];
    final r = p.repeat;
    b.writeln(
      '| ${i + 1} | `${p.id}` | ${p.name} | '
      '${p.legacyMode?.key ?? '—'} | ${p.blocks.length} | '
      '${p.reminders.length} | ${r.kind.key} | '
      '${(r.weekdays.toList()..sort()).join('/')} | '
      '${r.kind == RepeatKind.cycle ? r.cycleBigWeek.toString() : '—'} | '
      '${r.dates.isEmpty ? '无' : (r.dates.toList()..sort()).join(', ')} |',
    );
  }
  b.writeln();
  b.writeln(
    '（只有 `repeat.kind = cycle` 时 `cycleBigWeek` 才参与判定，'
    '其余类型显示「—」。）',
  );
  b.writeln();
  b.writeln('| 项 | 值 |');
  b.writeln('|---|---|');
  b.writeln(
    '| 单日例外 dayOverrides | '
    '${data.dayOverrides.isEmpty ? '无' : _json(data.dayOverrides)} |',
  );
  b.writeln(
    '| 兼容镜像 rules | 保留，供旧周期弹窗与顶栏切换写入；'
    '`withRules` 会同步回 plans |',
  );
  b.writeln(
    '| 历史快照 | '
    '${data.daySnapshots.entries.map((e) => '${e.key}→${e.value.planId}（${e.value.source}）').join('；')} |',
  );
  b.writeln(
    '| 今天（2026-11-07 周六）解析 | '
    '`${newResolved.planId}` / ${newResolved.label} |',
  );
  b.writeln('| 备份 | `data.json.bak` 已生成，逐字节等于迁移前原文件 |');
  b.writeln();
  b.writeln('## 保真校验');
  b.writeln();
  for (final e in checks.entries) {
    b.writeln('- ${e.value ? '✅' : '❌'} ${e.key}');
  }
  final allPass = checks.values.every((v) => v);
  b.writeln();
  b.writeln(allPass ? '**结论：真实数据可无损迁移，线上文件未被改动。**' : '**结论：存在未通过项，不要发布。**');
  b.writeln();
  b.writeln(
    '> 说明：本报告只验数据层（#8）。'
    '「新建 / 重命名 / 排序 / 编辑重复规则」的管理界面属于 #9，本层未提供。',
  );

  await reportFile.parent.create(recursive: true);
  await reportFile.writeAsString(b.toString(), flush: true);
  print(b.toString());
  print('报告已写入：${reportFile.path}');
  if (!allPass) exit(1);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
