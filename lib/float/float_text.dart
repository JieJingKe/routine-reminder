import '../domain/day_block.dart';
import '../domain/time_math.dart';

/// 悬浮窗中心两行字。168px 放不下更多，所以只回答
/// 「现在在干什么 / 还剩多久」或「空着 / 下一个是什么」。
///
/// 截断规则照原型：任务名超过 5 个字留 4 个加省略号；
/// 空档里预告的下一项超过 4 个字留 3 个加省略号（那一行更窄）。
String floatTaskName(String name) => _truncate(name, keep: 4, limit: 5);

String floatNextName(String name) => _truncate(name, keep: 3, limit: 4);

String _truncate(String text, {required int keep, required int limit}) {
  final runes = text.runes.toList();
  if (runes.length <= limit) return text;
  return '${String.fromCharCodes(runes.take(keep))}…';
}

/// `还剩 2h30` / `还剩 28m`，与原型一致；分钟补零。
String floatRemaining(int minutes) {
  if (minutes < 60) return '还剩 ${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '还剩 ${h}h${m.toString().padLeft(2, '0')}';
}

({String title, String sub}) floatCenterText(
  List<DayBlock> blocks,
  int minute,
) {
  final current = TimeMath.blockAt(blocks, minute);
  if (current != null) {
    return (
      title: floatTaskName(current.name),
      sub: floatRemaining(current.end - minute),
    );
  }

  final next = TimeMath.nextAfter(blocks, minute);
  return (
    title: '空档',
    sub: next == null
        ? ''
        : '${TimeMath.formatHm(next.start)} ${floatNextName(next.name)}',
  );
}
