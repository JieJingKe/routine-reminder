import '../domain/calendar_rules.dart';
import '../domain/category.dart';
import '../domain/day_block.dart';
import '../domain/day_mode.dart';
import '../domain/plan.dart';
import '../domain/reminder.dart';
import 'app_data.dart';

/// 内置数据。**必须与需求文档「内置数据」一字不差**，不要顺手"优化"。
///
/// 两套表都是排满的（从 07:00 连续排到次日 07:00），所以正常情况下未安排是 0。
/// 一旦你在界面上看到斜纹空档，说明数据被动过或者 gaps 算错了 —— 这就是自检点。
abstract final class SeedData {
  /// 跨零点的块（23:00–07:00）必须在这里就换算成 1860，
  /// 不能指望后面某个地方"记得"处理 —— 忘一处，时长就变成负数。
  static DayBlock _b(
    String start,
    String end,
    String name,
    Category cat, {
    bool remind = false,
  }) {
    final s = _hm(start);
    final rawEnd = _hm(end);
    return DayBlock(
      start: s,
      end: rawEnd <= s ? rawEnd + 1440 : rawEnd,
      name: name,
      category: cat,
      remind: remind,
    );
  }

  static int _hm(String hm) {
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  /// 工作日（周一至周五），14 块。
  ///
  /// `remind: true` 只给起点正好落在内置提醒表上的那几块，
  /// 其余全关 —— 需求明确要求别给每一行都默认开铃铛。
  static List<DayBlock> get workday => [
    _b('07:00', '07:30', '起床洗漱', Category.selfcare, remind: true),
    _b('07:30', '08:00', '早餐', Category.selfcare),
    _b('08:00', '08:30', '看书', Category.study),
    _b('08:30', '09:00', '通勤', Category.commute, remind: true),
    _b('09:00', '12:00', '工作', Category.work),
    _b('12:00', '13:00', '午餐休息', Category.leisure),
    _b('13:00', '18:00', '工作', Category.work, remind: true),
    _b('18:00', '18:30', '通勤', Category.commute, remind: true),
    _b('18:30', '19:00', '通勤看书', Category.study),
    _b('19:00', '20:00', '锻炼', Category.exercise, remind: true),
    _b('20:00', '20:30', '洗澡', Category.selfcare),
    _b('20:30', '21:30', '洗衣打扫', Category.selfcare),
    _b('21:30', '23:00', '自由', Category.leisure),
    _b('23:00', '07:00', '睡眠', Category.sleep),
  ];

  /// 节假日（周六、周日），15 块。
  static List<DayBlock> get holiday => [
    _b('07:00', '07:30', '起床洗漱', Category.selfcare, remind: true),
    _b('07:30', '08:30', '早餐', Category.selfcare),
    _b('08:30', '10:15', '学技能', Category.study, remind: true),
    _b('10:15', '11:45', '锻炼', Category.exercise, remind: true),
    _b('11:45', '12:15', '洗澡', Category.selfcare),
    _b('12:15', '13:15', '午餐', Category.selfcare),
    _b('13:15', '16:15', '自由', Category.leisure),
    _b('16:15', '17:15', '看书', Category.study),
    _b('17:15', '18:15', '自由', Category.leisure),
    _b('18:15', '19:15', '晚餐', Category.selfcare),
    _b('19:15', '20:15', '看书', Category.study),
    _b('20:15', '21:15', '家务', Category.selfcare),
    _b('21:15', '22:00', '自由', Category.leisure),
    _b('22:00', '23:00', '放松', Category.leisure),
    _b('23:00', '07:00', '睡眠', Category.sleep),
  ];

  /// 工作日 6 条提醒。文案是「该…啦」，动作必须是能立刻做出来的最小动作。
  static List<Reminder> get workdayReminders => const [
    Reminder(time: 7 * 60, text: '该起床啦'),
    Reminder(time: 8 * 60 + 30, text: '该出门上班啦'),
    Reminder(time: 13 * 60, text: '该回工位啦'),
    Reminder(time: 18 * 60, text: '该下班啦'),
    Reminder(time: 19 * 60, text: '该出门走 20 分钟啦'),
    Reminder(time: 22 * 60 + 30, text: '该收尾准备睡觉啦'),
  ];

  /// 节假日 4 条。
  static List<Reminder> get holidayReminders => const [
    Reminder(time: 7 * 60, text: '该起床啦'),
    Reminder(time: 8 * 60 + 30, text: '该打开课程学 25 分钟啦'),
    Reminder(time: 10 * 60 + 15, text: '该换运动服开始锻炼啦'),
    Reminder(time: 22 * 60 + 30, text: '该收尾准备睡觉啦'),
  ];

  /// v2 起内置数据也是「两张计划表」，不再有写死的 `Map<DayMode, ...>`。
  /// 顺序即优先级：工作日表在前，节假日表在后。
  static AppData build() => AppData(
    plans: [
      Plan(
        id: PlanDefaults.workdayId,
        name: PlanDefaults.workdayName,
        blocks: workday,
        reminders: workdayReminders,
        legacyMode: DayMode.workday,
        repeat: const RepeatRule(
          kind: RepeatKind.weekly,
          weekdays: {1, 2, 3, 4, 5},
        ),
      ),
      Plan(
        id: PlanDefaults.holidayId,
        name: PlanDefaults.holidayName,
        blocks: holiday,
        reminders: holidayReminders,
        legacyMode: DayMode.holiday,
        repeat: const RepeatRule(kind: RepeatKind.weekly, weekdays: {6, 7}),
      ),
    ],
    dayOverrides: const {},
    rules: CalendarRules(),
    daySnapshots: const {},
    ui: const UiPrefs(),
    records: const {},
  );
}
