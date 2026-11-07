import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../float/float_protocol.dart';

/// 主进程侧的悬浮窗管理：拉起子进程、维持本机连接、转发状态和指令。
///
/// 悬浮窗是第二个 Flutter 进程。这样不用升级窗口库、不用改 runner，
/// 代价是多一份引擎内存。数据仍然只有一个写入口：子进程既不读也不写
/// data.json，所有状态都从这条连接推过去。
class FloatController {
  FloatController({
    required this.onShowMain,
    required this.onHideFloat,
    required this.onMoved,
  });

  final void Function() onShowMain;
  final Future<void> Function() onHideFloat;
  final void Function(Offset position) onMoved;

  ServerSocket? _server;
  Socket? _client;
  Process? _process;
  String? _token;
  FloatSnapshot? _snapshot;
  bool _wantedEnabled = false;
  bool _disposed = false;

  /// 测试宿主是 flutter_tester，没有 GUI 也没有可启动的 exe。
  /// 不进这层判断的话，跑测试会真的拉起一个窗口进程。
  static bool get canRun {
    if (kIsWeb) return false;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return false;
    if (Platform.resolvedExecutable.contains('flutter_tester')) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  bool get running => _process != null;

  Future<void> start() async {
    if (!canRun || _server != null) return;
    try {
      _token = _randomToken();
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_accept);
    } on Object catch (e) {
      debugPrint('悬浮窗通道启动失败：$e');
    }
  }

  Future<void> show(Offset position, FloatSnapshot snapshot) async {
    _snapshot = snapshot;
    _wantedEnabled = true;
    if (!canRun) return;
    if (_process != null) {
      _sendState();
      return;
    }
    final server = _server;
    final token = _token;
    if (server == null || token == null) return;

    try {
      final process = await Process.start(Platform.resolvedExecutable, [
        '--float',
        '--port=${server.port}',
        '--token=$token',
        '--x=${position.dx}',
        '--y=${position.dy}',
      ], mode: ProcessStartMode.normal);
      _process = process;
      // 子进程没有自己的控制台。把它的输出转发回来，
      // 否则它崩在启动阶段时这边只会看到"窗口不见了"。
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[float] $line'));
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[float] $line'));
      unawaited(
        process.exitCode.then((_) {
          _process = null;
          _client = null;
          if (!_disposed && _wantedEnabled) {
            debugPrint('悬浮窗进程已退出，可从托盘重新打开');
          }
        }),
      );
    } on Object catch (e) {
      debugPrint('悬浮窗进程启动失败：$e');
      _process = null;
    }
  }

  Future<void> hide() async {
    _wantedEnabled = false;
    _client?.destroy();
    _client = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    }
  }

  void broadcast(FloatSnapshot snapshot) {
    _snapshot = snapshot;
    _sendState();
  }

  void _sendState() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _send({'type': 'state', 'state': snapshot.toJson()});
  }

  void _send(Map<String, dynamic> message) {
    final socket = _client;
    if (socket == null) return;
    try {
      socket.writeln(jsonEncode(message));
    } on Object {
      _client = null;
    }
  }

  void _accept(Socket socket) {
    if (_client != null) {
      socket.destroy();
      return;
    }

    var authenticated = false;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final message = decodeFloatMessage(line);
            if (message == null) return;

            if (!authenticated) {
              if (message['type'] == 'hello' && message['token'] == _token) {
                authenticated = true;
                _client = socket;
                _sendState();
              } else {
                socket.destroy();
              }
              return;
            }

            switch (message['type']) {
              case 'showMain':
                onShowMain();
              case 'hideFloat':
                unawaited(onHideFloat());
              case 'moved':
                final x = (message['x'] as num?)?.toDouble();
                final y = (message['y'] as num?)?.toDouble();
                if (x != null && y != null) onMoved(Offset(x, y));
            }
          },
          onDone: () {
            if (identical(_client, socket)) _client = null;
          },
          onError: (_) {
            if (identical(_client, socket)) _client = null;
          },
          cancelOnError: true,
        );
  }

  Future<void> dispose() async {
    _disposed = true;
    await hide();
    await _server?.close();
    _server = null;
  }

  static String _randomToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
