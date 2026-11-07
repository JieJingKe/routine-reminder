import 'dart:convert';

import '../domain/day_block.dart';

/// 主进程 → 悬浮窗进程的唯一状态包。
///
/// 悬浮窗不读 data.json：两个进程各读一次文件就会变成两份状态，
/// 改了一边另一边不变，而且不会报错。所有数据只从这条连接来。
class FloatSnapshot {
  const FloatSnapshot({required this.blocks, required this.theme});

  /// 今天生效的那套表（已经过规则栈解析）。
  final List<DayBlock> blocks;

  /// `light` / `dark`。主进程已经把「跟随系统」解析成具体值，
  /// 悬浮窗不需要再猜一次系统亮度。
  final String theme;

  Map<String, dynamic> toJson() => {
    'blocks': [for (final b in blocks) b.toJson()],
    'theme': theme,
  };

  factory FloatSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['blocks'];
    return FloatSnapshot(
      blocks: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => DayBlock.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      theme: json['theme'] == 'light' ? 'light' : 'dark',
    );
  }
}

/// 一行一条 JSON，由 `LineSplitter` 切开。
String encodeFloatMessage(Map<String, dynamic> message) => jsonEncode(message);

Map<String, dynamic>? decodeFloatMessage(String line) {
  try {
    final value = jsonDecode(line);
    if (value is Map) return Map<String, dynamic>.from(value);
  } on FormatException {
    return null;
  }
  return null;
}
