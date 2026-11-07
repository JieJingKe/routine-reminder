import 'package:flutter/material.dart';

import '../widgets/hover_intent.dart';

import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../design/tokens.dart';
import '../../domain/plan.dart';

/// 浮层骨架。所有计划表相关浮层都挂在主窗口 `Stack` 里，**不走
/// showDialog**：Navigator 的 Overlay route 不会随父树 setState 重建，
/// 而 Palette 是静态门面，切主题时会出现「窗口换了色、浮层还是旧配色」。
///
/// 压暗遮罩同时挡住外围 18px 拖动带，避免点浮层时把窗口拖跑；
/// 底下内容退一档，浮层卡片才有明确的「焦点」。
class PopoverLayer extends StatelessWidget {
  const PopoverLayer({
    super.key,
    required this.child,
    required this.onClose,
    this.width = 300,
    this.top = Spacing.pad + Spacing.barHeight + 4,
    this.right = 22,
  });

  final Widget child;
  final VoidCallback onClose;
  final double width;
  final double top;
  final double right;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: ColoredBox(
                color: Palette.scrim,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: top,
            right: right,
            width: width,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: Focus(autofocus: true, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// 与设置面板同一套卡片外观：surface 底 + control 边 + 窗口阴影。
class PopoverCard extends StatelessWidget {
  const PopoverCard({super.key, required this.child, this.padding = 14});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 13),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.control),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: Palette.windowShadow,
      ),
      child: child,
    );
  }
}

class PopoverHeader extends StatelessWidget {
  const PopoverHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: TypeScale.section),
            const Spacer(),
            _PopoverClose(onTap: onClose),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TypeScale.labelSmall.copyWith(
            color: Palette.faint,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _PopoverClose extends StatefulWidget {
  const _PopoverClose({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PopoverClose> createState() => _PopoverCloseState();
}

class _PopoverCloseState extends State<_PopoverClose> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      tooltip: '关闭',
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: hover ? Palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Icon(
          Icons.close,
          size: 14,
          color: hover ? Palette.text : Palette.faint,
        ),
      ),
    );
  }
}

/// 「一张表」的可点行。表选择器与日历指派共用，保证两处看起来是同一种东西。
class PlanChoiceList extends StatelessWidget {
  const PlanChoiceList({
    super.key,
    required this.plans,
    required this.currentPlanId,
    required this.onSelect,
  });

  final List<Plan> plans;
  final String? currentPlanId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < plans.length; i++)
          _PlanChoiceRow(
            plan: plans[i],
            priority: i + 1,
            active: plans[i].id == currentPlanId,
            onTap: () => onSelect(plans[i].id),
          ),
      ],
    );
  }
}

class _PlanChoiceRow extends StatefulWidget {
  const _PlanChoiceRow({
    required this.plan,
    required this.priority,
    required this.active,
    required this.onTap,
  });

  final Plan plan;
  final int priority;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PlanChoiceRow> createState() => _PlanChoiceRowState();
}

class _PlanChoiceRowState extends State<_PlanChoiceRow> {
  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return HoverIntent(
      onTap: widget.onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: widget.active
              ? Palette.accent.withValues(alpha: hover ? 0.22 : 0.12)
              : (hover ? Palette.hover : Colors.transparent),
          border: Border.all(
            color: widget.active ? Palette.accent : Palette.rule,
          ),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '${widget.priority}',
                style: TypeScale.labelSmall.copyWith(
                  color: Palette.ghost,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.label.copyWith(
                      color: widget.active ? Palette.accent : Palette.text,
                      fontWeight: widget.active
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.repeat.summary} · ${p.blocks.length} 项任务',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.labelSmall.copyWith(color: Palette.faint),
                  ),
                ],
              ),
            ),
            if (widget.active)
              Icon(Icons.check, size: 14, color: Palette.accent),
          ],
        ),
      ),
    );
  }
}

/// 顶栏「今天：X」点开的表选择器。
class PlanPickerPanel extends StatelessWidget {
  const PlanPickerPanel({
    super.key,
    required this.plans,
    required this.currentPlanId,
    required this.currentSource,
    required this.autoPlanName,
    required this.overriddenAt,
    required this.onSelect,
    required this.onClose,
  });

  final List<Plan> plans;
  final String currentPlanId;
  final String currentSource;
  final String? autoPlanName;
  final String? overriddenAt;
  final ValueChanged<String?> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final current = planById(plans, currentPlanId);
    return PopoverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopoverHeader(
            title: '今天用哪张表',
            subtitle: '点一张即改判今天；明天仍按各表的重复规则自动判定。',
            onClose: onClose,
          ),
          const SizedBox(height: 10),
          _StatusLine(
            label: '今天',
            value: '${current?.name ?? '—'}（$currentSource）',
          ),
          if (overriddenAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '按规则本应是 ${autoPlanName ?? '—'} · ${_hhmm(overriddenAt!)} 手动改判',
              style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
            ),
          ],
          const SizedBox(height: 10),
          Container(height: 1, color: Palette.rule),
          const SizedBox(height: 10),
          PlanChoiceList(
            plans: plans,
            currentPlanId: currentPlanId,
            onSelect: onSelect,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _TextAction(
              label: '恢复自动判定',
              enabled: overriddenAt != null,
              onTap: () => onSelect(null),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '序号 = 同日多张表都命中时的优先级。',
            style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
          ),
        ],
      ),
    );
  }
}

/// L3 日历点某一天后弹出的单日指派。
class DayAssignPanel extends StatelessWidget {
  const DayAssignPanel({
    super.key,
    required this.date,
    required this.plans,
    required this.assignedPlanId,
    required this.autoPlanName,
    required this.onSelect,
    required this.onClose,
  });

  final DateTime date;
  final List<Plan> plans;
  final String? assignedPlanId;
  final String autoPlanName;
  final ValueChanged<String?> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return PopoverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopoverHeader(
            title: '$label 用哪张表',
            subtitle: '只影响这一天，汇总与看板会一起按这张表算。',
            onClose: onClose,
          ),
          const SizedBox(height: 10),
          _StatusLine(
            label: assignedPlanId == null ? '自动' : '已指派',
            value: assignedPlanId == null
                ? '$autoPlanName（按重复规则）'
                : (planById(plans, assignedPlanId)?.name ?? '—'),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Palette.rule),
          const SizedBox(height: 10),
          PlanChoiceList(
            plans: plans,
            currentPlanId: assignedPlanId,
            onSelect: onSelect,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _TextAction(
              label: '恢复自动判定',
              enabled: assignedPlanId != null,
              onTap: () => onSelect(null),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TypeScale.labelSmall.copyWith(color: Palette.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TypeScale.label.copyWith(color: Palette.text),
          ),
        ),
      ],
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.enabled ? widget.onTap : null,
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      builder: (context, hover) {
        final color = !widget.enabled
            ? Palette.ghost
            : (hover ? Palette.text : Palette.accent);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: hover && widget.enabled ? Palette.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Text(
            widget.label,
            style: TypeScale.label.copyWith(color: color),
          ),
        );
      },
    );
  }
}

String _hhmm(String iso) {
  if (iso.length >= 16) return iso.substring(11, 16);
  return iso;
}

/// 不引 `package:collection` 的 `firstOrNull`，纯 Dart 里更省心。
Plan? planById(List<Plan> plans, String? id) {
  if (id == null) return null;
  for (final p in plans) {
    if (p.id == id) return p;
  }
  return null;
}
