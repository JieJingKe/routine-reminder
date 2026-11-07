import 'package:flutter/material.dart';

import '../widgets/hover_intent.dart';

import '../../data/app_data.dart';
import '../../design/tokens.dart';
import '../../domain/calendar_rules.dart';
import '../../domain/plan.dart';
import '../widgets/date_grid.dart';
import '../widgets/segmented.dart';
import 'plan_popover.dart';

/// 计划表管理浮层。挂在窗口外壳 Stack 里，宽 430。
class PlanManagerLayer extends StatelessWidget {
  const PlanManagerLayer({
    super.key,
    required this.data,
    required this.now,
    required this.onPlansChanged,
    required this.onEditBlocks,
    required this.onClose,
  });

  final AppData data;
  final DateTime now;
  final ValueChanged<List<Plan>> onPlansChanged;
  final ValueChanged<String> onEditBlocks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return PopoverLayer(
      width: 430,
      onClose: onClose,
      child: PlanManagerPanel(
        data: data,
        now: now,
        onPlansChanged: onPlansChanged,
        onEditBlocks: onEditBlocks,
        onClose: onClose,
      ),
    );
  }
}

/// 列表 / 编辑器二选一。展开编辑器时替换列表，不叠第二层浮层 ——
/// 面板高度有限，叠层会把「返回」挤到看不见的地方。
class PlanManagerPanel extends StatefulWidget {
  const PlanManagerPanel({
    super.key,
    required this.data,
    required this.now,
    required this.onPlansChanged,
    required this.onEditBlocks,
    required this.onClose,
  });

  final AppData data;
  final DateTime now;
  final ValueChanged<List<Plan>> onPlansChanged;
  final ValueChanged<String> onEditBlocks;
  final VoidCallback onClose;

  @override
  State<PlanManagerPanel> createState() => _PlanManagerPanelState();
}

class _PlanManagerPanelState extends State<PlanManagerPanel> {
  String? _editingId;

  String _newId() => 'plan_${DateTime.now().microsecondsSinceEpoch}';

  void _submit(List<Plan> next) => widget.onPlansChanged(next);

  void _add() {
    // 安全默认：新表是「仅指定日期」且未圈任何日子 —— matchesSpecial
    // 与 matchesRegular 都不命中，不会凭空抢走任何一天的判定。
    final plan = Plan(
      id: _newId(),
      name: '新计划表',
      repeat: const RepeatRule(kind: RepeatKind.dates),
    );
    _submit([...widget.data.plans, plan]);
    setState(() => _editingId = plan.id);
  }

  void _duplicate(Plan p) {
    // 显式构造而不是 copyWith：copyWith 没法把 legacyMode 清成 null，
    // 否则副本会被旧汇总入口当成「工作日 / 节假日」的第三份答案。
    final copy = Plan(
      id: _newId(),
      name: '${p.name} 副本',
      blocks: p.blocks,
      reminders: p.reminders,
      repeat: p.repeat,
    );
    final next = [...widget.data.plans];
    next.insert(widget.data.plans.indexOf(p) + 1, copy);
    _submit(next);
    setState(() => _editingId = copy.id);
  }

  void _remove(Plan p) {
    if (widget.data.plans.length <= 1) return;
    final next = [...widget.data.plans]..remove(p);
    _submit(next);
    if (_editingId == p.id) setState(() => _editingId = null);
  }

  void _move(Plan p, int delta) {
    final next = [...widget.data.plans];
    final i = next.indexOf(p);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= next.length) return;
    next.removeAt(i);
    next.insert(j, p);
    _submit(next);
  }

  void _updatePlan(Plan next) {
    _submit([for (final p in widget.data.plans) p.id == next.id ? next : p]);
  }

  @override
  Widget build(BuildContext context) {
    final plans = widget.data.plans;
    final editing = planById(plans, _editingId);
    return PopoverCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 430),
        child: SingleChildScrollView(
          child: editing == null
              ? _listBody(plans)
              : PlanEditor(
                  key: ValueKey(editing.id),
                  plan: editing,
                  now: widget.now,
                  onChanged: _updatePlan,
                  onEditBlocks: widget.onEditBlocks,
                  onBack: () => setState(() => _editingId = null),
                ),
        ),
      ),
    );
  }

  Widget _listBody(List<Plan> plans) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopoverHeader(
          title: '计划表',
          subtitle: '每张表自带任务与重复规则；序号越小，同日冲突时越优先。',
          onClose: widget.onClose,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '共 ${plans.length} 张',
                style: TypeScale.labelSmall.copyWith(color: Palette.muted),
              ),
            ),
            _MiniAction(icon: Icons.add, tooltip: '新建计划表', onTap: _add),
            const SizedBox(width: 6),
            BarButton(label: '新建', onTap: _add),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < plans.length; i++)
          _PlanRow(
            plan: plans[i],
            priority: i + 1,
            canDelete: plans.length > 1,
            isToday: widget.data.forDate(widget.now).planId == plans[i].id,
            onEdit: () => setState(() => _editingId = plans[i].id),
            onDuplicate: () => _duplicate(plans[i]),
            onUp: () => _move(plans[i], -1),
            onDown: () => _move(plans[i], 1),
            onDelete: () => _remove(plans[i]),
          ),
        const SizedBox(height: 10),
        Container(height: 1, color: Palette.rule),
        const SizedBox(height: 8),
        Text(
          '新建表默认是「仅指定日期」且不圈日期，不会抢走任何一天；'
          '进编辑器设好重复规则或圈好日期后才会生效。',
          style: TypeScale.labelSmall.copyWith(
            color: Palette.ghost,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.priority,
    required this.canDelete,
    required this.isToday,
    required this.onEdit,
    required this.onDuplicate,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final Plan plan;
  final int priority;
  final bool canDelete;
  final bool isToday;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.panel2,
        border: Border.all(color: isToday ? Palette.accent : Palette.rule),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$priority',
              style: TypeScale.labelSmall.copyWith(
                color: Palette.ghost,
                fontFeatures: TypeScale.tabular,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.label.copyWith(color: Palette.text),
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(Radii.chip),
                          ),
                          child: Text(
                            '今天',
                            style: TypeScale.labelSmall.copyWith(
                              color: Palette.accent,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${plan.repeat.summary} · ${plan.blocks.length} 项任务',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.labelSmall.copyWith(color: Palette.faint),
                  ),
                ],
              ),
            ),
          ),
          _MiniAction(icon: Icons.edit_outlined, tooltip: '编辑', onTap: onEdit),
          _MiniAction(
            icon: Icons.copy_all_outlined,
            tooltip: '复制',
            onTap: onDuplicate,
          ),
          _MiniAction(
            icon: Icons.arrow_upward,
            tooltip: '上移（提高优先级）',
            onTap: onUp,
          ),
          _MiniAction(
            icon: Icons.arrow_downward,
            tooltip: '下移（降低优先级）',
            onTap: onDown,
          ),
          _MiniAction(
            icon: Icons.delete_outline,
            tooltip: canDelete ? '删除' : '至少保留一张表',
            enabled: canDelete,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatefulWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_MiniAction> createState() => _MiniActionState();
}

class _MiniActionState extends State<_MiniAction> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.enabled ? widget.onTap : null,
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      tooltip: widget.tooltip,
      builder: (context, hover) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hover && widget.enabled ? Palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Icon(
          widget.icon,
          size: 14,
          color: !widget.enabled
              ? Palette.ghost
              : (hover ? Palette.text : Palette.muted),
        ),
      ),
    );
  }
}

/// 单张表的编辑器：名称 + 重复设置（四选一 + 特殊日期）+ 作息入口。
///
/// 改动即时写盘，没有「保存 / 取消」—— 和设置面板同一套交互纪律。
class PlanEditor extends StatefulWidget {
  const PlanEditor({
    super.key,
    required this.plan,
    required this.now,
    required this.onChanged,
    required this.onEditBlocks,
    required this.onBack,
  });

  final Plan plan;
  final DateTime now;
  final ValueChanged<Plan> onChanged;
  final ValueChanged<String> onEditBlocks;
  final VoidCallback onBack;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final TextEditingController _name;
  late DateTime _month;

  /// 月历按需展开。常驻展开会把底部的「编辑作息」入口挤出首屏，
  /// 而圈日期并不是每次编辑都要做的事。
  bool _showCalendar = false;

  @override
  void initState() {
    super.initState();
    // 只在首次创建时灌值。父级每次改动都会重建 widget，若在这里重新
    // 赋值 controller，打字会被逐字符打断。
    _name = TextEditingController(text: widget.plan.name);
    _month = DateTime(widget.now.year, widget.now.month, 1);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _emit(Plan next) => widget.onChanged(next);

  void _setKind(RepeatKind kind) {
    _emit(
      widget.plan.copyWith(repeat: widget.plan.repeat.copyWith(kind: kind)),
    );
  }

  void _toggleWeekday(int day) {
    final wd = {...widget.plan.repeat.weekdays};
    if (!wd.remove(day)) wd.add(day);
    _emit(
      widget.plan.copyWith(repeat: widget.plan.repeat.copyWith(weekdays: wd)),
    );
  }

  void _setCycle(CycleType type) {
    final current = widget.plan.repeat;
    // 大小周锚点存绝对日期，不能存「本周是大周」这种相对说法。
    final monday = DateTime(
      widget.now.year,
      widget.now.month,
      widget.now.day,
    ).subtract(Duration(days: widget.now.weekday - 1));
    _emit(
      widget.plan.copyWith(
        repeat: current.copyWith(
          kind: RepeatKind.cycle,
          cycle: CycleRule(
            type: type,
            anchorDate: type == CycleType.bigSmallWeek
                ? (current.cycle.anchorDate ?? monday)
                : current.cycle.anchorDate,
            anchorIsBig: current.cycle.anchorIsBig,
          ),
        ),
      ),
    );
  }

  /// 「本表在大周还是小周生效」——只改 cycleBigWeek，锚点不动。
  void _setBigWeek(bool big) {
    _emit(
      widget.plan.copyWith(
        repeat: widget.plan.repeat.copyWith(cycleBigWeek: big),
      ),
    );
  }

  /// 「本周是大周还是小周」——把锚点重设成本周一，存绝对日期。
  /// 存相对说法的话，下周打开时「本周」已经变了，会永远返回大周。
  void _setThisWeek(bool big) {
    final monday = DateTime(
      widget.now.year,
      widget.now.month,
      widget.now.day,
    ).subtract(Duration(days: widget.now.weekday - 1));
    final current = widget.plan.repeat;
    _emit(
      widget.plan.copyWith(
        repeat: current.copyWith(
          cycle: CycleRule(
            type: CycleType.bigSmallWeek,
            anchorDate: monday,
            anchorIsBig: big,
          ),
        ),
      ),
    );
  }

  void _toggleDate(String key) {
    final dates = {...widget.plan.repeat.dates};
    if (!dates.remove(key)) dates.add(key);
    _emit(
      widget.plan.copyWith(repeat: widget.plan.repeat.copyWith(dates: dates)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final r = p.repeat;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _MiniAction(
              icon: Icons.arrow_back,
              tooltip: '返回列表',
              onTap: widget.onBack,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text('编辑计划表', style: TypeScale.section)),
          ],
        ),
        const SizedBox(height: 10),
        Text('名称', style: TypeScale.labelSmall.copyWith(color: Palette.muted)),
        const SizedBox(height: 5),
        TextField(
          controller: _name,
          style: TypeScale.body.copyWith(color: Palette.text),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Palette.panel2,
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
          onChanged: (v) => _emit(p.copyWith(name: v)),
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: Palette.rule),
        const SizedBox(height: 12),
        Text(
          '重复设置',
          style: TypeScale.labelSmall.copyWith(color: Palette.muted),
        ),
        const SizedBox(height: 6),
        Segmented<RepeatKind>(
          items: RepeatKind.values,
          value: r.kind,
          onChanged: _setKind,
          compact: true,
          labelOf: (k) => switch (k) {
            RepeatKind.daily => '每天',
            RepeatKind.weekly => '按星期',
            RepeatKind.cycle => '周期',
            RepeatKind.dates => '指定日期',
          },
        ),
        const SizedBox(height: 8),
        Text(
          switch (r.kind) {
            RepeatKind.daily => '每天都按这张表，除非下面圈了特殊日期。',
            RepeatKind.weekly => '只在勾选的星期几按这张表。',
            RepeatKind.cycle => '大小周 / 单休：按锚点周隔周交替。',
            RepeatKind.dates => '常规层不生效，只有下面圈定的日期才用这张表。',
          },
          style: TypeScale.labelSmall.copyWith(
            color: Palette.ghost,
            height: 1.6,
          ),
        ),
        if (r.kind == RepeatKind.weekly || r.kind == RepeatKind.cycle) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 5,
            children: [
              for (var d = 1; d <= 7; d++)
                _WeekdayChip(
                  label: ['一', '二', '三', '四', '五', '六', '日'][d - 1],
                  active: r.weekdays.contains(d),
                  onTap: () => _toggleWeekday(d),
                ),
            ],
          ),
        ],
        if (r.kind == RepeatKind.cycle) ...[
          const SizedBox(height: 12),
          Segmented<CycleType>(
            items: CycleType.values,
            value: r.cycle.type,
            onChanged: _setCycle,
            compact: true,
            labelOf: (t) => switch (t) {
              CycleType.none => '不设置',
              CycleType.bigSmallWeek => '大小周',
              CycleType.singleDayOff => '单休',
            },
          ),
          if (r.cycle.type == CycleType.bigSmallWeek) ...[
            const SizedBox(height: 8),
            Segmented<bool>(
              items: const [true, false],
              value: r.cycleBigWeek,
              onChanged: _setBigWeek,
              compact: true,
              labelOf: (big) => big ? '大周生效' : '小周生效',
            ),
            const SizedBox(height: 6),
            Segmented<bool>(
              items: const [true, false],
              value: r.cycle.anchorIsBig,
              onChanged: _setThisWeek,
              compact: true,
              labelOf: (big) => big ? '本周是大周' : '本周是小周',
            ),
          ],
        ],
        const SizedBox(height: 14),
        Container(height: 1, color: Palette.rule),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '特殊日期（${r.dates.length}）',
              style: TypeScale.labelSmall.copyWith(color: Palette.muted),
            ),
            const Spacer(),
            BarButton(
              label: _showCalendar ? '收起日历' : '选择日期',
              icon: Icons.calendar_month_outlined,
              onTap: () => setState(() => _showCalendar = !_showCalendar),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '圈定的日期优先于常规重复；设为「指定日期」时，它就是唯一生效日。',
          style: TypeScale.labelSmall.copyWith(
            color: Palette.ghost,
            height: 1.6,
          ),
        ),
        if (r.dates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              for (final d in (r.dates.toList()..sort()))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: Text(
                    d,
                    style: TypeScale.labelSmall.copyWith(color: Palette.accent),
                  ),
                ),
            ],
          ),
        ],
        if (_showCalendar) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              _MiniAction(
                icon: Icons.chevron_left,
                tooltip: '上个月',
                onTap: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1, 1),
                ),
              ),
              SizedBox(
                width: 68,
                child: Text(
                  '${_month.year}/${_month.month.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: TypeScale.labelSmall.copyWith(
                    fontFeatures: TypeScale.tabular,
                  ),
                ),
              ),
              _MiniAction(
                icon: Icons.chevron_right,
                tooltip: '下个月',
                onTap: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1, 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MonthGrid(
            month: _month,
            selected: r.dates,
            today: widget.now,
            onToggle: _toggleDate,
          ),
        ],
        const SizedBox(height: 14),
        Container(height: 1, color: Palette.rule),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '任务：${p.blocks.length} 项',
                style: TypeScale.labelSmall.copyWith(color: Palette.muted),
              ),
            ),
            BarButton(
              label: '编辑这张表的作息',
              icon: Icons.edit_outlined,
              onTap: () => widget.onEditBlocks(p.id),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '会切到编辑视图，改动只落在这一张表上。',
          style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
        ),
      ],
    );
  }
}

class _WeekdayChip extends StatefulWidget {
  const _WeekdayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_WeekdayChip> createState() => _WeekdayChipState();
}

class _WeekdayChipState extends State<_WeekdayChip> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        width: 34,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active
              ? (hover ? Palette.hiStroke(Palette.accent) : Palette.accent)
              : (hover ? Palette.hover : Palette.panel2),
          border: Border.all(
            color: widget.active ? Palette.accent : Palette.control,
          ),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Text(
          widget.label,
          style: TypeScale.labelSmall.copyWith(
            color: widget.active ? Colors.white : Palette.muted,
          ),
        ),
      ),
    );
  }
}
