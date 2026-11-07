import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'float_protocol.dart';

/// 悬浮窗进程与主进程之间的长连接。
///
/// 主进程先启动 ServerSocket，再把端口和一次性令牌作为启动参数传进来。
/// 连接断了就说明主进程没了，悬浮窗直接退出 —— 留一个孤儿窗口没有意义，
/// 而且它拿不到新数据，只会显示一张过期的图。
class FloatClient {
  FloatClient({
    required this.port,
    required this.token,
    required this.onSnapshot,
    required this.onClosed,
  });

  final int port;
  final String token;
  final ValueChangedSnapshot onSnapshot;
  final void Function() onClosed;

  Socket? _socket;
  bool _disposed = false;

  Future<void> connect() async {
    while (!_disposed && _socket == null) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 1),
        );
        socket.setOption(SocketOption.tcpNoDelay, true);
        _socket = socket;
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleLine,
              onDone: _handleClosed,
              onError: (_) => _handleClosed(),
              cancelOnError: true,
            );
        _send({'type': 'hello', 'token': token});
      } on Object {
        if (_disposed) return;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  void _handleLine(String line) {
    final message = decodeFloatMessage(line);
    if (message == null) return;
    if (message['type'] != 'state') return;
    final state = message['state'];
    if (state is Map) {
      onSnapshot(FloatSnapshot.fromJson(Map<String, dynamic>.from(state)));
    }
  }

  void _handleClosed() {
    if (_disposed) return;
    _disposed = true;
    _socket = null;
    onClosed();
  }

  void showMain() => _send({'type': 'showMain'});

  void hideFloat() => _send({'type': 'hideFloat'});

  void reportPosition(Offset position) =>
      _send({'type': 'moved', 'x': position.dx, 'y': position.dy});

  void _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null) return;
    socket.writeln(encodeFloatMessage(message));
  }

  void dispose() {
    _disposed = true;
    _socket?.destroy();
    _socket = null;
  }
}

typedef ValueChangedSnapshot = void Function(FloatSnapshot snapshot);
