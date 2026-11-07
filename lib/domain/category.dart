/// 七类作息分类。
///
/// 「未安排」故意不在这里 —— 它不是第八个分类，而是"没有任何块"的状态。
/// 一旦做成 Category.unplanned，代码里就会出现"给未安排分配颜色/时长/统计"这种
/// 本来不该存在的逻辑。见需求文档「分类体系」与交接文档硬规则 #9。
enum Category {
  sleep('sleep', '睡眠'),
  selfcare('selfcare', '生活自理'),
  commute('commute', '通勤'),
  work('work', '工作'),
  study('study', '学习'),
  exercise('exercise', '锻炼'),
  leisure('leisure', '娱乐 / 自由');

  const Category(this.key, this.label);

  /// JSON 里存的值，与需求文档的键名一一对应，不可改。
  final String key;

  /// 界面上显示的中文名。
  final String label;

  /// 图例等窄位用的短名。UI 稿 v2 里这一类就叫「娱乐」，
  /// 清单/统计表仍用全称「娱乐 / 自由」，免得把「自由时段」这层意思丢掉。
  String get shortLabel => this == Category.leisure ? '娱乐' : label;

  static Category fromKey(String key) {
    for (final c in Category.values) {
      if (c.key == key) return c;
    }
    throw ArgumentError.value(key, 'key', '未知分类，必须是 7 类之一');
  }

  static Category? tryFromKey(Object? key) {
    if (key is! String) return null;
    for (final c in Category.values) {
      if (c.key == key) return c;
    }
    return null;
  }
}
