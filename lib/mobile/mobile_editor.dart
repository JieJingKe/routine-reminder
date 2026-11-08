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

  String get _planId =>
      widget.planIdOverride ?? widget.data.forDate(widget.now).planId;

  List<DayBlock> get _blocks =>
      widget.data.planById(_planId)?.blocks ??
      widget.data.forDate(widget.now).blocks;

  String get _planName =>
      widget.data.planById(_planId)?.name ??
      widget.data.forDate(widget.now).planName;

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
    setState(() => _expanded = hit.createdIndex);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 展示顺序必须与写入时用的下标一致，不能在这里按 23:00 起点重排，
    // 否则 replaceAt / removeAt 会改错另一段。
    final blocks = _blocks;
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
          Text('点开一段可改分类、前后挪 15 分钟或删除', style: TypeScale.labelSmall),
          const SizedBox(height: 12),
          for (var i = 0; i < blocks.length; i++)
            _BlockRow(
              block: blocks[i],
              expanded: _expanded == i,
              onTap: () =>
                  setState(() => _expanded = _expanded == i ? null : i),
              onCategory: (c) => _replaceAt(i, blocks[i].copyWith(category: c)),
              onShift: (dir) => _shiftAt(i, dir),
              onDelete: () {
                _commit(ScheduleEditor.removeAt(_blocks, i));
                setState(() => _expanded = null);
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
    required this.onTap,
    required this.onCategory,
    required this.onShift,
    required this.onDelete,
  });

  final DayBlock block;
  final bool expanded;
  final VoidCallback onTap;
  final ValueChanged<Category> onCategory;
  final ValueChanged<int> onShift;
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
                          block.name,
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
                  IconButton(
                    onPressed: () => onShift(-1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: '提前 15 分钟',
                  ),
                  IconButton(
                    onPressed: () => onShift(1),
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: '推后 15 分钟',
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
}
