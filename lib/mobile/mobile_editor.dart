import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../design/tokens.dart';
import '../domain/category.dart';
import '../domain/day_block.dart';
import '../domain/schedule_editor.dart';
import '../domain/time_math.dart';
import '../ui/widgets/app_card.dart';

/// 手机竖屏 L2：编辑某张计划表的作息块。
///
/// 桌面版的编辑层把 L1 原样放在顶部再叠时间轴，那是为「切视图不跳页」
/// 设计的；手机上改成一页清单，但写入仍走同一份 `ScheduleEditor` 与
/// `AppData.withPlanBlocks` —— 没有第二份 blocks 状态。
///
/// v0.11 起这一段能改的东西对齐了桌面端最常用的几项：**段名**（直接敲）、
/// **起止时刻**（5 分钟一档）**分类**、整段前后挪、删除、在空档新增。
class MobileEditor extends StatefulWidget {
  const MobileEditor({
    super.key,
    required this.data,
    required this.now,
    required this.onChanged,
    this.planIdOverride,
  });

  final AppData data;
  final DateTime now;
  final void Function(AppData next, {bool saveNow}) onChanged;

  /// 从计划表层进来的：编辑指定表，而不是「今天判到的那张」。
  final String? planIdOverride;

  @override
  State<MobileEditor> createState() => _MobileEditorState();
}

class _MobileEditorState extends State<MobileEditor> {
  int? _expanded;

  /// 名称输入框只在「当前展开的那一段」上存在。控制器与焦点节点挂在
  /// State 上（不在 `_BlockRow` 里），所以每次按键 commit 触发父级重建时
  /// 输入框不会被重建 —— 否则打一个字就掉焦点，等于没法用。
  TextEditingController? _nameCtrl;
  FocusNode? _nameFocus;

  String get _planId =>
      widget.planIdOverride ?? widget.data.forDate(widget.now).planId;

  List<DayBlock> get _blocks =>
      widget.data.planById(_planId)?.blocks ??
      widget.data.forDate(widget.now).blocks;

  String get _planName =>
      widget.data.planById(_planId)?.name ??
      widget.data.forDate(widget.now).planName;

  @override
  void dispose() {
    _nameCtrl?.dispose();
    _nameFocus?.dispose();
    super.dispose();
  }

  void _commit(List<DayBlock> next) {
    widget.onChanged(widget.data.withPlanBlocks(_planId, next), saveNow: true);
  }

  void _add() {
    final gaps = TimeMath.gaps(_blocks);
    if (gaps.isEmpty) {
      _toast('这一天已经排满了，先删掉一段再新增');
      return;
    }
    final at = ScheduleEditor.snapUp(gaps.first.start);
    final hit = ScheduleEditor.createAt(_blocks, at, Category.work);
    if (hit == null) {
      _toast('这里放不下新的一段');
      return;
    }
    _commit(hit.blocks);
    _expand(hit.createdIndex);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------ 展开与改名

  void _expand(int index) {
    setState(() => _expanded = index);
    _bindName(index);
  }

  void _collapse() {
    setState(() => _expanded = null);
    _unbindName();
  }

  void _bindName(int index) {
    final blocks = _blocks;
    if (index < 0 || index >= blocks.length) return;
    final name = blocks[index].name;
    final previous = _nameCtrl;
    final previousFocus = _nameFocus;
    _nameCtrl = TextEditingController(text: name)
      ..selection = TextSelection.collapsed(offset: name.length);
    _nameFocus = FocusNode()..addListener(_onNameFocusChanged);
    previous?.dispose();
    previousFocus?.dispose();
  }

  void _unbindName() {
    _nameCtrl?.dispose();
    _nameFocus?.dispose();
    _nameCtrl = null;
    _nameFocus = null;
  }

  /// 名字被清空后离开输入框 → 恢复原名。空名字在时间轴上是一条没有
  /// 标签的色块，等于把这一段弄丢了，不能就这么存下去。
  void _onNameFocusChanged() {
    final focus = _nameFocus;
    final ctrl = _nameCtrl;
    final index = _expanded;
    if (focus == null || ctrl == null || index == null) return;
    if (focus.hasFocus) return;
    final blocks = _blocks;
    if (index >= blocks.length) return;
    if (ctrl.text.trim().isEmpty) {
      ctrl.text = blocks[index].name;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 展示顺序必须与写入时用的下标一致，不能在这里按 23:00 起点重排，
    // 否则 replaceAt / removeAt 会改错另一段。
    final blocks = _blocks;
    // 删段之后展开下标可能越界，这里统一收敛。
    final expanded = _expanded != null && _expanded! < blocks.length
        ? _expanded
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('$_planName · 作息', style: TypeScale.title)),
              Text('${blocks.length} 段', style: TypeScale.labelSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '点开一段可改名称、起止时刻、分类，或整段挪动、删除',
            style: TypeScale.labelSmall,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < blocks.length; i++)
            _BlockRow(
              // 按下标 + 段名做 key 是不够的：改名会让 key 变化，输入框
              // 被重建。这里只用下标定位，控制器由 State 持有。
              block: blocks[i],
              expanded: expanded == i,
              nameController: expanded == i ? _nameCtrl : null,
              nameFocus: expanded == i ? _nameFocus : null,
              onTap: () => expanded == i ? _collapse() : _expand(i),
              onName: (v) => _replaceAt(i, blocks[i].copyWith(name: v)),
              onCategory: (c) => _replaceAt(i, blocks[i].copyWith(category: c)),
              onShift: (dir) => _shiftAt(i, dir),
              onStartStep: (dir) => _stepEdge(i, dir, start: true),
              onEndStep: (dir) => _stepEdge(i, dir, start: false),
              onDelete: () {
                _commit(ScheduleEditor.removeAt(_blocks, i));
                _collapse();
              },
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('在第一个空档新增一段'),
          ),
        ],
      ),
    );
  }

  void _replaceAt(int index, DayBlock next) {
    _commit(ScheduleEditor.replaceAt(_blocks, index, next));
  }

  /// 改开始 / 改结束：一次 5 分钟，撞到邻居或时长下限就原地不动。
  /// 与拖动时间轴走的是同一组钳制函数，不会出现「手机上能改出重叠」。
  void _stepEdge(int index, int direction, {required bool start}) {
    final blocks = _blocks;
    final block = blocks[index];
    final delta = direction.sign * ScheduleEditor.step;
    final next = start
        ? ScheduleEditor.withStart(blocks, index, block.start + delta)
        : ScheduleEditor.withEnd(blocks, index, block.end + delta);
    // DayBlock 没有实现 `==`，只能比时间：撞到邻居被钳住时不必再存一次。
    if (next.start == block.start && next.end == block.end) return;
    _commit(ScheduleEditor.replaceAt(blocks, index, next));
  }

  void _shiftAt(int index, int direction) {
    // nudge 的步长是 5 分钟；手机上按 15 分钟一档更顺手，连挪三次。
    var updated = _blocks;
    var block = updated[index];
    for (var n = 0; n < 3; n++) {
      block = ScheduleEditor.nudge(
        updated,
        index,
        direction: direction,
        shift: false,
      );
      updated = ScheduleEditor.replaceAt(updated, index, block);
    }
    _commit(updated);
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.expanded,
    required this.nameController,
    required this.nameFocus,
    required this.onTap,
    required this.onName,
    required this.onCategory,
    required this.onShift,
    required this.onStartStep,
    required this.onEndStep,
    required this.onDelete,
  });

  final DayBlock block;
  final bool expanded;
  final TextEditingController? nameController;
  final FocusNode? nameFocus;
  final VoidCallback onTap;
  final ValueChanged<String> onName;
  final ValueChanged<Category> onCategory;
  final ValueChanged<int> onShift;
  final ValueChanged<int> onStartStep;
  final ValueChanged<int> onEndStep;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        color: Palette.panel2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Palette.of(block.category),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block.name.isEmpty ? '（未命名）' : block.name,
                          style: TypeScale.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${TimeMath.formatHm(block.start)} – '
                          '${TimeMath.formatHm(block.end)} · '
                          '${block.category.label}',
                          style: TypeScale.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    TimeMath.formatDuration(block.duration),
                    style: TypeScale.label,
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Palette.muted,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const Divider(height: 18),
              Text('名称', style: _fieldLabel),
              const SizedBox(height: 4),
              TextField(
                controller: nameController,
                focusNode: nameFocus,
                style: TypeScale.body.copyWith(color: Palette.text),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Palette.sunken,
                  hintText: '这一段做什么',
                  hintStyle: TypeScale.bodyMuted,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.chip),
                    borderSide: BorderSide(color: Palette.control),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.chip),
                    borderSide: BorderSide(color: Palette.control),
                  ),
                ),
                onChanged: (v) {
                  // 清空过程中不写入空名字，等失焦时再恢复原名。
                  if (v.trim().isEmpty) return;
                  onName(v.trim());
                },
              ),
              const SizedBox(height: 10),
              Text('起止时刻', style: _fieldLabel),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: _TimeStepper(
                      label: '开始',
                      text: TimeMath.formatHm(block.start),
                      onStep: onStartStep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TimeStepper(
                      label: '结束',
                      text: TimeMath.formatHm(block.end),
                      onStep: onEndStep,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('分类', style: _fieldLabel),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in Category.values)
                    GestureDetector(
                      onTap: () => onCategory(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c == block.category
                              ? Palette.sel
                              : Palette.sunken,
                          border: Border.all(
                            color: c == block.category
                                ? Palette.accent
                                : Palette.border,
                          ),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Text(c.shortLabel, style: TypeScale.labelSmall),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => onShift(-1),
                    child: const Text('整段 −15'),
                  ),
                  TextButton(
                    onPressed: () => onShift(1),
                    child: const Text('整段 +15'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static TextStyle get _fieldLabel =>
      TypeScale.labelSmall.copyWith(color: Palette.muted);
}

/// 一个「−  07:30  +」的小步进器。一次 5 分钟，长按不加速 —— 手机上
/// 连点比长按更可控，长按容易一下跑过头。
class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.label,
    required this.text,
    required this.onStep,
  });

  final String label;
  final String text;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.sunken,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove, onTap: () => onStep(-1)),
          Expanded(
            child: Column(
              children: [
                Text(label, style: TypeScale.labelSmall),
                Text(
                  text,
                  style: TypeScale.label.copyWith(color: Palette.text),
                ),
              ],
            ),
          ),
          _StepButton(icon: Icons.add, onTap: () => onStep(1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: SizedBox(
        width: 30,
        height: 34,
        child: Icon(icon, size: 18, color: Palette.muted),
      ),
    );
  }
}
