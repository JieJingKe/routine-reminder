import 'dart:convert';

import 'app_data.dart';

/// 跨端搬运计划表的备份格式。
///
/// 两端（Windows / Android）用同一份 `data.json` 结构；导出时套一层信封，
/// 记录来源、时间与格式版本，便于将来云同步时做冲突判定。
/// 导入同时接受两种输入：
/// - 本类导出的信封文件；
/// - 直接从 `%APPDATA%` 拷出来的裸 `data.json`（方便手工搬运）。
class PlanBackup {
  PlanBackup._();

  static const String format = 'routine-reminder/plan-backup';
  static const int formatVersion = 1;

  static String encode(
    AppData data, {
    required String sourcePlatform,
    required String appVersion,
    DateTime? at,
  }) {
    final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
    final envelope = <String, dynamic>{
      'format': format,
      'formatVersion': formatVersion,
      'exportedAt': stamp,
      'sourcePlatform': sourcePlatform,
      'appVersion': appVersion,
      // 未来云同步的冲突判定字段先占位：现在恒为空，写入端不依赖它。
      'deviceId': null,
      'updatedAt': stamp,
      'data': data.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// 解析备份，返回数据和一句给人看的来源说明。
  /// 任何结构问题都抛 [PlanBackupException]，界面直接显示 message 即可。
  static ({AppData data, String origin}) decode(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException catch (e) {
      throw PlanBackupException('不是合法的 JSON 文件：${e.message}');
    }
    if (raw is! Map) {
      throw PlanBackupException('文件顶层必须是对象');
    }
    final root = Map<String, dynamic>.from(raw);
    Map<String, dynamic> payload;
    var origin = '裸 data.json';

    final nested = root['data'];
    if (root['format'] == format && nested is Map) {
      final v = root['formatVersion'];
      if (v is int && v > formatVersion) {
        throw PlanBackupException(
          '备份格式版本 $v 比当前程序支持的 $formatVersion 更新，请先升级应用',
        );
      }
      payload = Map<String, dynamic>.from(nested);
      final platform = root['sourcePlatform'] as String? ?? '未知平台';
      final at = root['exportedAt'] as String? ?? '';
      origin = '$platform${at.isEmpty ? '' : ' · $at'}';
    } else if (root.containsKey('plans') || root.containsKey('schemaVersion')) {
      payload = root;
    } else {
      throw PlanBackupException('这不像是计划表备份，缺少 plans / data 字段');
    }

    final plans = payload['plans'];
    if (plans is! List || plans.isEmpty) {
      throw PlanBackupException('备份里没有计划表，或者是无法识别的旧格式');
    }
    try {
      final data = AppData.fromJson(payload);
      if (data.plans.isEmpty) {
        throw PlanBackupException('备份里的计划表解析后为空');
      }
      return (data: data, origin: origin);
    } on PlanBackupException {
      rethrow;
    } on Object catch (e) {
      throw PlanBackupException('计划表内容解析失败：$e');
    }
  }

  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'routine-reminder-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.json';
  }
}

class PlanBackupException implements Exception {
  PlanBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
