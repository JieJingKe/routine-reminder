/// 一条待发出的到点提醒。
///
/// 只是「几点、说什么」，不关心用哪个通道发 —— Android 走本地通知，
/// 桌面端目前没有实现，测试里换成内存实现。放在 domain 是为了让它保持
/// 纯 Dart（不 import 任何 flutter / meta），`dart run tool/*.dart` 也能用。
class ReminderSlot {
  const ReminderSlot({
    required this.at,
    required this.title,
    required this.body,
    this.blockId = '',
  });

  /// 绝对本地时刻。跨天排程时由排程器按「日期 + 段起点」算好。
  final DateTime at;

  /// 通知标题，直接用作息段名称。
  final String title;

  /// 通知正文，形如 `07:30 – 08:30 · 学习`。
  final String body;

  /// 来源段。同一天改名后仍能对上号，便于将来做「点了通知跳过去」。
  final String blockId;

  int get minuteOfDay => at.hour * 60 + at.minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderSlot &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.blockId == blockId;

  @override
  int get hashCode => Object.hash(at, title, body, blockId);

  @override
  String toString() => 'ReminderSlot($at, $title)';
}
