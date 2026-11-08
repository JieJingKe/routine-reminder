import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'data/app_data.dart';
import 'data/app_repository.dart';
import 'data/plan_store.dart';
import 'design/tokens.dart';
import 'float/float_main.dart';
import 'mobile/mobile_app.dart';
import 'platform/reminders.dart';

/// 入口。
///
/// 两个进程角色：
/// - 主进程持有数据和托盘；
/// - `--float` 子进程只画 168px 悬浮窗，状态全部由主进程通过本机连接推送。
///
/// 悬浮窗不各自读 JSON —— 那样会变成两份数据，改一边另一边不变。
Future<void> main(List<String> args) async {
  // Android 没有窗口管理、托盘、第二进程悬浮窗与注册表自启，
  // 直接走移动端那棵独立的树；下面的桌面初始化一行都不执行。
  if (Platform.isAndroid) {
    // 只有 Android 才把提醒通道换成真实现；桌面端保持 NoopReminders，
    // Windows 构建与测试都不会碰平台通道。
    Reminders.instance = LocalNotificationReminders();
    try {
      await Reminders.instance.init();
    } on Object {
      // 初始化失败不该挡住启动，界面里的开关会给出权限提示。
    }
    await _runMobile();
    return;
  }

  if (args.contains('--float')) {
    await runFloatProcess(args);
    return;
  }

  // 开机自启只拉托盘和悬浮窗，不弹主窗口。
  final startHidden = args.contains('--autostart');

  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 先把数据读进来，窗口首帧就能按用户选过的主题上色。
  // 否则浅色系统会先闪一下深色，再被 app 层校正回来。
  final repository = AppRepository();
  AppData? data;
  Object? error;
  try {
    data = await repository.load();
  } on Object catch (e) {
    error = e;
  }

  final saved = data?.ui.theme;
  Palette.setTheme(
    saved != null
        ? AppTheme.fromKey(saved)
        : (PlatformDispatcher.instance.platformBrightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark),
  );
  final ground = Palette.ground;

  // 主窗口不再用透明分层窗口。窗口内容本来就铺满整个矩形（ground 底色 +
  // 渐变地面 + 18px 边圈），没有真正透出桌面的区域；透明只会让 DWM 在
  // 最大化 / 还原动画时把整块窗口重合成一次，肉眼就是一闪。
  // 悬浮窗（--float 分支）仍保持透明，那边的圆必须透出桌面。
  final options = WindowOptions(
    size: const Size(1060, Spacing.dashboardWindowHeight),
    minimumSize: const Size(1000, 500),
    center: true,
    backgroundColor: ground,
    titleBarStyle: TitleBarStyle.hidden,
    title: '我的时间',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setBackgroundColor(ground);
    if (!startHidden) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(
    RoutineApp(
      repository: repository,
      initialData: data,
      loadError: error,
      startHidden: startHidden,
    ),
  );
}

/// Android 启动路径：只做「读数据 → 定首帧主题 → runApp」三件事。
///
/// 数据目录由 `path_provider_android` 给出（应用私有目录），格式与 Windows
/// 的 data.json 完全一致；主题仍按「用户选过的 > 系统亮度」判定。
Future<void> _runMobile() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalFilePlanStore();
  AppData? data;
  Object? error;
  try {
    data = await store.load();
  } on Object catch (e) {
    error = e;
  }
  final saved = data?.ui.theme;
  Palette.setTheme(
    saved != null
        ? AppTheme.fromKey(saved)
        : (PlatformDispatcher.instance.platformBrightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark),
  );
  runApp(MobileApp(store: store, initialData: data, loadError: error));
}
