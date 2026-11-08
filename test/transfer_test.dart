import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:routine_reminder/data/seed_data.dart';
import 'package:routine_reminder/data/transfer.dart';

void main() {
  final seed = SeedData.build();

  group('PlanBackup 跨端备份', () {
    test('encode → decode 往返不丢数据', () {
      final text = PlanBackup.encode(
        seed,
        sourcePlatform: 'android',
        appVersion: '0.10.0',
        at: DateTime.utc(2026, 11, 8, 1, 2, 3),
      );
      final parsed = PlanBackup.decode(text);
      expect(parsed.data.toJson(), seed.toJson());
      expect(parsed.origin, contains('android'));
      expect(parsed.origin, contains('2026-11-08'));

      final envelope = jsonDecode(text) as Map<String, dynamic>;
      expect(envelope['format'], PlanBackup.format);
      expect(envelope['formatVersion'], PlanBackup.formatVersion);
      expect(envelope['deviceId'], isNull);
      expect(envelope['updatedAt'], isA<String>());
      expect((envelope['data'] as Map)['plans'], isA<List>());
    });

    test('裸 data.json 也能直接导入', () {
      final raw = const JsonEncoder.withIndent('  ').convert(seed.toJson());
      final parsed = PlanBackup.decode(raw);
      expect(parsed.origin, '裸 data.json');
      expect(parsed.data.plans.length, seed.plans.length);
      expect(
        parsed.data.forDate(DateTime(2026, 11, 9)).planId,
        seed.forDate(DateTime(2026, 11, 9)).planId,
      );
    });

    test('比当前程序更新的格式版本要拒绝', () {
      final envelope = {
        'format': PlanBackup.format,
        'formatVersion': PlanBackup.formatVersion + 1,
        'exportedAt': '2026-11-08T00:00:00Z',
        'data': seed.toJson(),
      };
      expect(
        () => PlanBackup.decode(jsonEncode(envelope)),
        throwsA(
          isA<PlanBackupException>().having(
            (e) => e.message,
            'message',
            contains('请先升级'),
          ),
        ),
      );
    });

    test('坏文件给出人话报错，不甩 FormatException', () {
      for (final bad in [
        'not json',
        '[]',
        '{}',
        '{"plans": []}',
        jsonEncode({
          'format': PlanBackup.format,
          'data': {'plans': []},
        }),
      ]) {
        expect(
          () => PlanBackup.decode(bad),
          throwsA(isA<PlanBackupException>()),
          reason: '应该被挡下：$bad',
        );
      }
    });

    test('导出文件名带日期时间且无非法字符', () {
      final name = PlanBackup.fileName(DateTime(2026, 11, 8, 9, 5));
      expect(name, 'routine-reminder-20261108-0905.json');
      expect(name.contains(RegExp(r'[\\/:*?"<>|]')), isFalse);
    });
  });
}
