import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 跨端文件搬运的唯一入口。
///
/// 两端共用 `file_picker` 10.x：Windows 是原生文件对话框，Android 是 SAF。
/// 停在 10.x 是因为 13.x 会把 win32 拉到 6.x，破坏桌面悬浮窗的点击穿透。
/// 导出用 `saveFile` 直接把字节交给系统保存，不需要申请存储权限；
/// 导入用 `pickFiles(withData: true)` 选一个 .json，再按 UTF-8 读成字符串。
abstract final class PlanFileTransfer {
  static Future<String?> saveText({
    required String suggestedName,
    required String content,
    String dialogTitle = '保存计划表备份',
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [suggestedName.endsWith('.md') ? 'md' : 'json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  }

  static Future<String?> readText() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择计划表备份（.json）',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null) return null;
    final bytes = picked.bytes;
    if (bytes != null) return utf8.decode(bytes, allowMalformed: true);
    final path = picked.path;
    if (path == null) return null;
    return File(path).readAsString();
  }
}
