import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_data.dart';
import 'seed_data.dart';

/// 数据层自己的错误类型。界面只负责把它翻成一句人话，
/// 不要把 FileSystemException 的英文原文甩到用户脸上。
class AppDataException implements Exception {
  AppDataException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AppDataException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 本地 JSON 的唯一读写入口。
///
/// 约束（需求文档 638 行）：主进程是唯一数据源，两个窗口只渲染不写文件。
/// 所以整个应用只允许存在一个 AppRepository 实例，由 app 层持有。
class AppRepository {
  AppRepository({this.dataDirOverride});

  static const String fileName = 'data.json';

  /// 测试时可指定一个临时目录，正式运行走 path_provider。
  final Directory? dataDirOverride;
  Directory? _dataDir;
  AppData? _cache;

  Future<Directory> _dir() async {
    final existing = _dataDir ?? dataDirOverride;
    if (existing != null) {
      _dataDir = existing;
      return existing;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      _dataDir = dir;
      return dir;
    } on Object catch (e) {
      throw AppDataException('找不到可写的数据目录', cause: e);
    }
  }

  Future<File> file() async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$fileName');

  /// 读数据。文件不存在就用内置数据初始化并落盘，保证首次启动开箱可用。
  Future<AppData> load({bool forceReload = false}) async {
    if (!forceReload && _cache != null) return _cache!;
    final f = await file();

    if (!await f.exists()) {
      final seeded = SeedData.build();
      await save(seeded);
      _cache = seeded;
      return seeded;
    }

    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) throw const FormatException('数据文件是空的');
      final json = jsonDecode(raw);
      if (json is! Map) throw const FormatException('数据文件顶层必须是对象');
      final map = Map<String, dynamic>.from(json);
      final isV1 = !(map['plans'] is List && (map['plans'] as List).isNotEmpty);
      if (isV1) {
        // 迁移前逐字节备份。备份已存在就不覆盖 —— 否则一次迁移失败后
        // 重试会把「原始 v1」冲成半迁移状态，备份就没意义了。
        final bak = File('${f.path}.bak');
        if (!await bak.exists()) await f.copy(bak.path);
      }
      final data = AppData.fromJson(map);
      if (isV1) await save(data); // 立刻落 v2，下次启动不再走迁移分支
      _cache = data;
      return data;
    } on FormatException catch (e) {
      throw AppDataException('数据文件读不出来，可能被改坏了：${e.message}', cause: e);
    } on Object catch (e) {
      throw AppDataException('数据文件读取失败', cause: e);
    }
  }

  /// 写数据。先写临时文件再改名 —— 直接覆盖时如果进程被杀，
  /// 会留下一个半截 JSON，下次启动直接读不出来。
  Future<void> save(AppData data) async {
    final f = await file();
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.parent.create(recursive: true);
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data.toJson()),
        flush: true,
      );
      await tmp.rename(f.path);
      _cache = data;
    } on Object catch (e) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } on Object catch (_) {
          // 临时文件删不掉不影响主流程
        }
      }
      throw AppDataException('保存失败，改动没有写进磁盘', cause: e);
    }
  }

  /// 供测试与调试：当前缓存是否已加载。
  bool get isLoaded => _cache != null;

  @visibleForTesting
  void resetCache() => _cache = null;
}
