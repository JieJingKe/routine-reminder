import 'dart:io';
import 'dart:typed_data';

import 'package:win32_registry/win32_registry.dart';

/// 开机自启写在 HKCU 的 Run 键下，不要求管理员权限。
///
/// 不引 launch_at_startup：它把 exe 路径和参数直接拼成
/// `C:\Program Files\... --autostart`，路径带空格时命令会被拆坏。
/// 这里自己加引号，另外同步 StartupApproved —— 用户曾在任务管理器里
/// 关过自启的话，只写 Run 键 Windows 仍然不会启动。
const String _appName = 'routine_reminder';
const String _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
const String _approvedKeyPath =
    r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

String get _command => '"${Platform.resolvedExecutable}" --autostart';

Future<bool> isAutostartEnabled() async {
  if (!Platform.isWindows) return false;
  try {
    final key = Registry.openPath(RegistryHive.currentUser, path: _runKeyPath);
    final value = key.getStringValue(_appName);
    key.close();
    if (value != _command) return false;

    final approved = Registry.openPath(
      RegistryHive.currentUser,
      path: _approvedKeyPath,
    );
    final bytes = approved.getBinaryValue(_appName);
    approved.close();
    if (bytes == null || bytes.isEmpty) return true;
    return bytes[0].isEven;
  } on Object {
    return false;
  }
}

Future<bool> setAutostart(bool enabled) async {
  if (!Platform.isWindows) return false;
  try {
    final key = Registry.openPath(
      RegistryHive.currentUser,
      path: _runKeyPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    if (enabled) {
      key.createValue(RegistryValue.string(_appName, _command));
    } else if (key.getValue(_appName) != null) {
      key.deleteValue(_appName);
    }
    key.close();

    final approved = Registry.openPath(
      RegistryHive.currentUser,
      path: _approvedKeyPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    if (enabled) {
      final bytes = Uint8List(12);
      bytes[0] = 2;
      approved.createValue(RegistryValue.binary(_appName, bytes));
    } else if (approved.getValue(_appName) != null) {
      approved.deleteValue(_appName);
    }
    approved.close();
    return true;
  } on Object {
    return false;
  }
}
