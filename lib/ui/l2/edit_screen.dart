import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_data.dart';
import '../../design/tokens.dart';
import '../../domain/category.dart';
import '../../domain/day_block.dart';
import '../../domain/schedule_editor.dart';
import '../l1/dashboard_screen.dart';
import '../widgets/category_picker.dart';
import 'day_timeline.dart';
import 'task_list.dart';

/// L2 编辑层。
///
/// 需求 #21：看板内容**仍在原位置、原布局**，只是在它下面追加时间轴和清单。
/// 所以这里是一个竖向滚动容器，第一屏严格等于 L1，往下滚才看到新增的两块 ——
/// 不是跳页，也不是把环重排到别处。
///
/// 三个视图（看板里的环、时间轴、清单）读的是**同一份 blocks**。
/// 任何一处改动都走 `_commit`，没有第二份状态需要同步。
class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.data,
    required this.now,
    required this.onChanged,
    required this.onRestoreDefault,
    this.onOverride,
    this.planIdOverride,
  });

  final AppData data;
  final DateTime now;
  final void Function(AppData next, {bool saveNow}) onChanged;
  final VoidCallback onRestoreDefault;
  final ValueChanged<Category>? onOverride;

  /// 从计划表编辑器进来的：编辑指定表，而不是「今天判到的那张」。
  /// 不传时保持原行为 —— 顶栏切到编辑视图就是编辑当天生效的表。
  final String? planIdOverride;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  int? _selectedIndex;
  Category _lastCategory = Category.work;

  String get _targetPlanId =>
      widget.planIdOverride ?? widget.data.forDate(widget.now).planId;

  List<DayBlock> get _blocks =>
      widget.data.planById(_targetPlanId)?.blocks ??
      widget.data.forDate(widget.now).blocks;

  void _commit(List<DayBlock> next, {bool saveNow = false}) {
    // 只改目标表的 blocks。多计划表之后不能再用 DayMode 反查，
    // 否则新建的表会被误写成工作日表。
    widget.onChanged(
      widget.data.withPlanBlocks(_targetPlanId, next),
      saveNow: saveNow,
    );
  }

  Future<void> _pickCategory({int? createAt, int? changeIndex}) async {
    final picked = await showCategoryPicker(context, initial: _lastCategory);
    if (picked == null) return;
    _lastCategory = picked;

    if (createAt != null) {
      final hit = ScheduleEditor.createAt(_blocks, createAt, picked);
      if (hit == null) return;
      _commit(hit.blocks, saveNow: true);
      setState(() => _selectedIndex = hit.createdIndex);
    } else if (changeIndex != null && changeIndex < _blocks.length) {
      _commit(
        ScheduleEditor.replaceAt(
          _blocks,
          changeIndex,
          _blocks[changeIndex].copyWith(category: picked),
        ),
        saveNow: true,
      );
    }
  }

  void _delete(int index) {
    if (index >= _blocks.length) return;
    _commit(ScheduleEditor.removeAt(_blocks, index), saveNow: true);
    setState(() => _selectedIndex = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final i = _selectedIndex;
    if (i == null || i >= _blocks.length) return KeyEventResult.ignored;

    final shift = HardwareKeyboard.instance.isShiftPressed;
    int? dir;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) dir = 1;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) dir = -1;

    if (dir != null) {
      final next = ScheduleEditor.nudge(
        _blocks,
        i,
        direction: dir,
        shift: shift,
      );
      _commit(ScheduleEditor.replaceAt(_blocks, i, next), saveNow: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _delete(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    final nowMinute = widget.now.hour * 60 + widget.now.minute;
    final selected = _selectedIndex != null && _selectedIndex! < blocks.length
        ? _selectedIndex
        : null;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        // 第一屏严格等于当前视口高度：L1 在同样窗口尺寸下就是铺满这一块，
        // 所以切到编辑时环、图例的位置一像素都不动，往下滚才露出时间轴。
        // 窗口由用户自己拉大，不再靠切视图时 setSize 撑高。
        builder: (context, viewport) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 第一屏 = 看板原样，一像素都不改。
                SizedBox(
                  height: viewport.maxHeight,
                  child: DashboardScreen(
                    data: widget.data,
                    now: widget.now,
                    blocksOverride: widget.planIdOverride == null
                        ? null
                        : blocks,
                    editing: true,
                    selectedIndex: selected,
                    onSelect: (i) => setState(() => _selectedIndex = i),
                    onBlocksChanged: (next) => _commit(next),
                    onOverride: widget.onOverride,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DayTimeline(
                        blocks: blocks,
                        nowMinute: nowMinute,
                        selectedIndex: selected,
                        onSelect: (i) => setState(() => _selectedIndex = i),
                        onBlocksChanged: _commit,
                        onCreateRequest: (m) => _pickCategory(createAt: m),
                        onCategoryRequest: (i) => _pickCategory(changeIndex: i),
                        onDeleteRequest: _delete,
                      ),
                      const SizedBox(height: 12),
                      TaskList(
                        blocks: blocks,
                        selectedIndex: selected,
                        onSelect: (i) => setState(() => _selectedIndex = i),
                        onBlocksChanged: (next) => _commit(next, saveNow: true),
                        onRestoreDefault: () {
                          widget.onRestoreDefault();
                          setState(() => _selectedIndex = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '环上：拖色块中间平移，拖两端改起止；选中一行后：← / → 把结束时间 ±5 分钟，'
                          'Shift + ← / → 改开始时间，Delete 删除。'
                          '所有改动都吸附到 5 分钟，撞到相邻任务会停住，不会推开或覆盖。',
                          style: TypeScale.labelSmall.copyWith(
                            color: Palette.ghost,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
