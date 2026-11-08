import 'dart:io';

import 'app_data.dart';
import 'app_repository.dart';

/// 数据存储抽象。
///
/// 目前只有 [LocalFilePlanStore] 一个实现：每个设备各存一份 data.json，
/// 两端通过「导出 / 导入」搬运。云同步不在这轮范围内，但入口刻意收在这一层：
/// 未来要接服务端时，只需再写一个 `RemotePlanStore`（或包一层的
/// `SyncingPlanStore`），界面层不需要知道数据落在本地还是网络。
///
/// 一个云同步实现至少要回答四个问题，接口里都留了位置：
/// - `load`：冲突时以哪一端为准（建议用 `updatedAt` + 设备 id 的 LWW）；
/// - `save`：离线改动如何排队、何时重放；
/// - `replace`：导入 / 首次拉取时如何整体覆盖并保留回退点；
/// - `identity`：账号与设备标识由谁提供（这需要服务端与登录，见文档）。
abstract class PlanStore {
  Future<AppData> load({bool forceReload = false});

  Future<void> save(AppData data);

  /// 整体替换（导入备份 / 未来拉取远端全量快照）。
  /// 实现必须先把现有文件备份成 `.pre-import.bak`，且已存在时不覆盖。
  Future<void> replace(AppData data);

  /// 当前数据文件的绝对路径，供界面显示与人工拷贝。
  Future<String> dataFilePath();
}

/// 本地文件实现，包一层 [AppRepository]（仍是唯一的 data.json 读写入口）。
class LocalFilePlanStore implements PlanStore {
  LocalFilePlanStore({AppRepository? repository})
    : _repository = repository ?? AppRepository();

  final AppRepository _repository;

  @override
  Future<AppData> load({bool forceReload = false}) =>
      _repository.load(forceReload: forceReload);

  @override
  Future<void> save(AppData data) => _repository.save(data);

  @override
  Future<String> dataFilePath() async => (await _repository.file()).path;

  @override
  Future<void> replace(AppData data) async {
    final f = await _repository.file();
    final bak = File('${f.path}.pre-import.bak');
    if (await f.exists() && !await bak.exists()) {
      await f.copy(bak.path);
    }
    await _repository.save(data);
    // save() 会刷新缓存；这里不需要再动缓存。
  }
}
