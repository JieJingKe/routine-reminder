import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'float_app.dart';
import 'float_geometry.dart';

/// `--float` 入口：只画 168px 的环，不读数据文件、不写数据文件。
///
/// 端口和令牌由主进程通过命令行传进来。连不上主进程就直接退出 ——
/// 一个拿不到数据的悬浮窗没有存在的意义。
Future<void> runFloatProcess(List<String> args) async {
  final port = int.tryParse(_valueOf(args, '--port') ?? '');
  final token = _valueOf(args, '--token');
  if (port == null || token == null) {
    exit(0);
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final position = Offset(
    double.tryParse(_valueOf(args, '--x') ?? '') ?? 100,
    double.tryParse(_valueOf(args, '--y') ?? '') ?? 100,
  );

  // 注意：waitUntilReadyToShow 的 callback 是 VoidCallback，库内部**不 await**。
  // 把设置写进回调里，runApp 会抢在 setPosition 之前跑，首帧拿到的坐标是
  // 窗口的初始位置，之后一直错。所以这里不用回调，自己顺序 await。
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(FloatGeometry.size, FloatGeometry.size),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
      title: '我的时间',
    ),
  );
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setSkipTaskbar(true);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setHasShadow(false);
  await windowManager.setResizable(false);
  await windowManager.setPosition(position);

  // 不在这里 show：窗口默认是隐藏的，runner 会在首帧画完后自己显示
  // （且不抢焦点）。先 show 出来只会多闪一个空窗口。
  runApp(FloatApp(port: port, token: token));
}

String? _valueOf(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}
