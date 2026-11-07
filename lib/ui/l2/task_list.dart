import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/category.dart';
import '../../domain/day_block.dart';
import '../../domain/schedule_editor.dart';
import '../../domain/time_math.dart';
import '../widgets/app_card.dart';

/// L2 任务清单。
///
/// 排序键是 **23:00**，不是 00:00（验收 #22）：睡眠 23:00–07:00 排第一行，
/// 名字后面标「次日」，跨零点块**合并成一行**，不拆成两条。
/// 环形图的起点仍是 00:00，两处对不上是设计上接受的，靠顶部一行小字说明。
class TaskList extends StatelessWidget {
  const TaskList({
    super.key,
    required this.blocks,
    required this.selectedIndex,
    required this.onSelect,
    required this.onBlocksChanged,
    required this.onRestoreDefault,
  });

  final List<DayBlock> blocks;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  /// 清单里的改动也走同一个回调，环形图和时间轴立即同步。
  final ValueChanged<List<DayBlock>> onBlocksChanged;
  final VoidCallback onRestoreDefault;

  @override
  Widget build(BuildContext context) {
    // 排序只排"显示顺序"，所有回传的索引都是原数组下标 ——
    // 不这么做的话，在时间轴上选中的块会和清单里点中的行对不上。
    final order = List<int>.generate(blocks.length, (i) => i)
      ..sort(
        (a, b) =>
            TimeMath.sortKey(blocks[a]).compareTo(TimeMath.sortKey(blocks[b])),
      );

    final scheduled = TimeMath.scheduledMinutes(blocks);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('任务清单', style: TypeScale.section),
              const Spacer(),
              Text(
                '${blocks.length} 项 · 合计 ${TimeMath.formatDurationCn(scheduled)}',
                style: TypeScale.labelSmall,
              ),
              const SizedBox(width: 16),
              _TextAction(
                label: '清空重排',
                onTap: () => onBlocksChanged(const []),
              ),
              const SizedBox(width: 12),
              _TextAction(label: '恢复默认', onTap: onRestoreDefault),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '从今晚 23:00 开始 · 环形图以 00:00 为起点，两处第一格不同',
            style: TypeScale.labelSmall.copyWith(color: Palette.faint),
          ),
          const SizedBox(height: 14),
          const _Header(),
          Divider(color: Palette.rule, height: 1),
          for (final i in order)
            _TaskRow(
              key: ValueKey('row_${i}_${blocks[i].start}_${blocks[i].end}'),
              index: i,
              blocks: blocks,
              selected: selectedIndex == i,
              onSelect: () => onSelect(selectedIndex == i ? null : i),
              onReplace: (next) =>
                  onBlocksChanged(ScheduleEditor.replaceAt(blocks, i, next)),
              onDelete: () =>
                  onBlocksChanged(ScheduleEditor.removeAt(blocks, i)),
            ),
          if (blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  '全天都空着 · 在上方 24 小时条上点一下就能新建',
                  style: TypeScale.bodyMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text(
        widget.label,
        style: TypeScale.labelSmall.copyWith(
          color: _hover ? Palette.text : Palette.faint,
          decoration: _hover ? TextDecoration.underline : null,
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Palette.faint, height: 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: [
          SizedBox(width: 62, child: Text('开始', style: style)),
          SizedBox(width: 62, child: Text('结束', style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Text('名称', style: style)),
          const SizedBox(width: 16),
          SizedBox(width: 118, child: Text('分类', style: style)),
          SizedBox(width: 34, child: Text('提醒', style: style)),
          SizedBox(width: 30, child: Text('', style: style)),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    super.key,
    required this.index,
    required this.blocks,
    required this.selected,
    required this.onSelect,
    required this.onReplace,
    required this.onDelete,
  });

  final int index;
  final List<DayBlock> blocks;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<DayBlock> onReplace;
  final VoidCallback onDelete;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _name;
  late final FocusNode _startFocus;
  late final FocusNode _endFocus;
  late final FocusNode _nameFocus;
  bool _hover = false;

  DayBlock get block => widget.blocks[widget.index];

  @override
  void initState() {
    super.initState();
    _start = TextEditingController(text: TimeMath.formatHm(block.start));
    _end = TextEditingController(text: TimeMath.formatHm(block.end));
    _name = TextEditingController(text: block.name);
    _startFocus = FocusNode()..addListener(_onStartFocusLost);
    _endFocus = FocusNode()..addListener(_onEndFocusLost);
    _nameFocus = FocusNode()
      ..addListener(() {
        _onNameFocusLost();
        if (mounted) setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant _TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 拖拽会实时改数据。用户没在这个输入框里打字时才同步，
    // 否则他刚输到一半就被覆盖。
    if (!_startFocus.hasFocus) _setText(_start, TimeMath.formatHm(block.start));
    if (!_endFocus.hasFocus) _setText(_end, TimeMath.formatHm(block.end));
    if (!_nameFocus.hasFocus) _setText(_name, block.name);
  }

  void _setText(TextEditingController c, String text) {
    if (c.text != text) c.text = text;
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _name.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onStartFocusLost() {
    if (!_startFocus.hasFocus) _commitTime(isStart: true);
  }

  void _onEndFocusLost() {
    if (!_endFocus.hasFocus) _commitTime(isStart: false);
  }

  void _onNameFocusLost() {
    if (!_nameFocus.hasFocus) _commitName();
  }

  /// 非法值**回退到修改前的值**，不弹错误框、不让任务消失（验收 #25）。
  void _commitTime({required bool isStart}) {
    final c = isStart ? _start : _end;
    final result = ScheduleEditor.parseTimeEdit(
      widget.blocks,
      widget.index,
      c.text,
      isStart: isStart,
    );
    if (result == null) {
      _setText(c, TimeMath.formatHm(isStart ? block.start : block.end));
      return;
    }
    widget.onReplace(result);
    _setText(c, TimeMath.formatHm(isStart ? result.start : result.end));
  }

  void _commitName() {
    final text = _name.text.trim().isEmpty ? '未命名' : _name.text.trim();
    if (text != block.name) widget.onReplace(block.copyWith(name: text));
    _setText(_name, text);
  }

  @override
  Widget build(BuildContext context) {
    final b = block;
    // DropdownButton 会拿显式 style 当最终样式，不会从 DefaultTextStyle 继承
    // 字体族。生产环境是系统默认字体（null），测试里才是显式字体。
    final ff = DefaultTextStyle.of(context).style.fontFamily;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.selected ? Palette.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Row(
            children: [
              _timeField(_start, _startFocus, () => _commitTime(isStart: true)),
              const SizedBox(width: 4),
              _timeField(_end, _endFocus, () => _commitTime(isStart: false)),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _dot(Palette.of(b.category)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        focusNode: _nameFocus,
                        maxLines: 1,
                        style: TypeScale.body,
                        decoration: _nameInput(_hover || _nameFocus.hasFocus),
                        onEditingComplete: _commitName,
                      ),
                    ),
                    if (b.crossesMidnight) ...[
                      const SizedBox(width: 6),
                      Text(
                        '次日',
                        style: TypeScale.labelSmall.copyWith(
                          color: Palette.faint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 118,
                child: DropdownButton<Category>(
                  value: b.category,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: Palette.raised,
                  borderRadius: BorderRadius.circular(Radii.chip),
                  icon: Icon(Icons.expand_more, size: 13, color: Palette.faint),
                  style: TypeScale.label.copyWith(
                    color: Palette.text,
                    fontFamily: ff,
                  ),
                  items: [
                    for (final c in Category.values)
                      DropdownMenuItem<Category>(
                        value: c,
                        child: Row(
                          children: [
                            _dot(Palette.of(c)),
                            const SizedBox(width: 7),
                            Text(
                              c.label,
                              style: TypeScale.labelSmall.copyWith(
                                fontFamily: ff,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (c) {
                    if (c != null) widget.onReplace(b.copyWith(category: c));
                  },
                ),
              ),
              SizedBox(
                width: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: b.remind ? '关掉这条提醒' : '打开这条提醒',
                  icon: Icon(
                    b.remind
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: b.remind ? Palette.commute : Palette.ghost,
                  ),
                  onPressed: () =>
                      widget.onReplace(b.copyWith(remind: !b.remind)),
                ),
              ),
              SizedBox(
                width: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: '删除这一块',
                  icon: Icon(Icons.delete_outline, color: Palette.ghost),
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeField(
    TextEditingController controller,
    FocusNode focus,
    VoidCallback submit,
  ) {
    return SizedBox(
      width: 62,
      child: TextField(
        controller: controller,
        focusNode: focus,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TypeScale.label.copyWith(
          color: Palette.text,
          fontFeatures: TypeScale.tabular,
        ),
        decoration: _plainInput,
        onEditingComplete: submit,
      ),
    );
  }

  static InputDecoration get _plainInput => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Palette.sunken,
    border: const OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
  );

  /// 名称列比时间列宽得多，常驻深色底会把整行变成一条粗黑带。
  /// 只在悬停或聚焦时浮出底色，提示"这里能改"。
  static InputDecoration _nameInput(bool active) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: active ? Palette.sunken : Colors.transparent,
    border: const OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
  );

  Widget _dot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
