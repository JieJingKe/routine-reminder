/// 提醒。文案固定是「该…啦」，且只提醒"开始"，不提醒"结束"。
///
/// 领域层保持纯 Dart，不引 `package:flutter`：一旦这里 import foundation，
/// `dart run tool/check_domain.dart` 和迁移演练脚本都会因为 `dart:ui`
/// 不可用而崩。类本来就是 const + final 字段，不需要 @immutable 注解。
class Reminder {
  const Reminder({required this.time, required this.text});

  /// 距离 00:00 的分钟数。
  final int time;

  /// 例如「该出门走 20 分钟啦」。
  final String text;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    time: parseHm(json['time'] as String),
    text: json['text'] as String,
  );

  Map<String, dynamic> toJson() => {'time': formatHm(time), 'text': text};

  static int parseHm(String hm) {
    final parts = hm.split(':');
    if (parts.length != 2) throw FormatException('提醒时间必须是 HH:mm', hm);
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String formatHm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
