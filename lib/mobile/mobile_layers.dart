import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../design/tokens.dart';
import '../domain/calendar_rules.dart';
import '../domain/plan.dart';
import '../domain/time_math.dart';

/// 移动端浮层种类。与桌面版一样，全部内嵌在主窗口 Stack 里，
/// 不走 showDialog / Navigator —— Palette 是静态门面，Overlay route
/// 不随父树 setState 重建，切主题会出现浮层不换色。
enum MobileLayer { none, plans, data, confirmImport }

/// 通用遮罩 + 底部卡片。点空白收起，卡片本身吸收点击。
class MobileScrim extends StatelessWidget {
  const MobileScrim({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Palette.scrim,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Palette.surface,
                  border: Border.all(color: Palette.border),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Radii.window),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: TypeScale.title)),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close, size: 20),
                          color: Palette.muted,
                          tooltip: '收起',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Flexible(child: SingleChildScrollView(child: child)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 计划表选择 + 单日指派。
class MobilePlanSheet extends StatelessWidget {
  const MobilePlanSheet({
    super.key,
    required this.data,
    required this.now,
    required this.onClose,
    required this.onAssign,
    required this.onEditPlan,
  });

  final AppData data;
  final DateTime now;
  final VoidCallback onClose;
  final void Function(String dateKey, String? planId) onAssign;
  final ValueChanged<String> onEditPlan;

  @override
  Widget build(BuildContext context) {
    final todayKey = TimeMath.dateKey(now);
    final active = data.forDate(now);
    return MobileScrim(
      title: '计划表',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: TypeScale.bodyMuted,
              children: [
                const TextSpan(text: '今天：'),
                TextSpan(
                  text: active.planName,
                  style: TextStyle(
                    color: Palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '（${active.source}）'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final plan in data.plans)
            _PlanRow(
              plan: plan,
              active: plan.id == active.planId,
              overridden: data.dayOverrides.containsKey(todayKey),
              onUseToday: () => onAssign(todayKey, plan.id),
              onEdit: () => onEditPlan(plan.id),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onAssign(todayKey, null),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('今天恢复按规则自动'),
            ),
          ),
          const Divider(height: 24),
          Text('接下来 7 天', style: TypeScale.section),
          const SizedBox(height: 8),
          for (var i = 0; i < 7; i++)
            _DayAssignRow(
              date: DateTime(now.year, now.month, now.day + i),
              data: data,
              onAssign: onAssign,
            ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.active,
    required this.overridden,
    required this.onUseToday,
    required this.onEdit,
  });

  final Plan plan;
  final bool active;
  final bool overridden;
  final VoidCallback onUseToday;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? Palette.sel : Palette.panel2,
        border: Border.all(color: active ? Palette.accent : Palette.border),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: TypeScale.title)),
              if (active)
                Text(
                  overridden ? '今天·手动' : '今天·生效',
                  style: TypeScale.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan.repeat.summary, style: TypeScale.bodyMuted),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onUseToday,
                  child: const Text('今天用这张'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onEdit,
                  child: const Text('编辑作息'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayAssignRow extends StatelessWidget {
  const _DayAssignRow({
    required this.date,
    required this.data,
    required this.onAssign,
  });

  final DateTime date;
  final AppData data;
  final void Function(String dateKey, String? planId) onAssign;

  @override
  Widget build(BuildContext context) {
    final key = CalendarRules.dateKey(date);
    final resolved = data.forDate(date);
    final overridden = data.dayOverrides.containsKey(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text('${date.month}/${date.day}', style: TypeScale.body),
          ),
          Expanded(
            child: Text(
              resolved.planName,
              style: overridden ? TypeScale.body : TypeScale.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<String?>(
            tooltip: '改判这一天',
            icon: const Icon(Icons.more_horiz, size: 18),
            color: Palette.surface,
            onSelected: (value) => onAssign(key, value),
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(value: null, child: Text('按规则自动')),
              ...data.plans.map(
                (p) => PopupMenuItem<String?>(value: p.id, child: Text(p.name)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 数据页：导入导出、主题、云同步路线说明。
class MobileDataSheet extends StatelessWidget {
  const MobileDataSheet({
    super.key,
    required this.dataPath,
    required this.theme,
    required this.busy,
    required this.onClose,
    required this.onTheme,
    required this.onExport,
    required this.onImport,
  });

  final String dataPath;
  final AppTheme theme;
  final bool busy;
  final VoidCallback onClose;
  final ValueChanged<AppTheme> onTheme;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return MobileScrim(
      title: '数据',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('本机数据文件', style: TypeScale.section),
          const SizedBox(height: 6),
          SelectableText(dataPath, style: TypeScale.labelSmall),
          const SizedBox(height: 16),
          Text('在手机和电脑之间搬运计划表', style: TypeScale.section),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onExport,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('导出备份'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onImport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('导入备份'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '导出的是一个 .json 文件；导入会整体覆盖本机数据，'
            '覆盖前自动留一份 .pre-import.bak。'
            '两端也可以直接互拷 data.json。',
            style: TypeScale.labelSmall,
          ),
          const Divider(height: 26),
          Text('主题', style: TypeScale.section),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final t in AppTheme.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.label),
                    selected: t == theme,
                    onSelected: (_) => onTheme(t),
                  ),
                ),
            ],
          ),
          const Divider(height: 26),
          Text('关于云同步', style: TypeScale.section),
          const SizedBox(height: 6),
          Text(
            '当前版本两端各自存一份数据，靠文件搬运。'
            '自动同步需要一个可被两端访问的服务器（账号、接口、冲突判定），'
            '数据层已抽出 PlanStore 接口，接后端时不用改界面。',
            style: TypeScale.bodyMuted,
          ),
        ],
      ),
    );
  }
}

/// 导入前的覆盖确认。
class MobileConfirmSheet extends StatelessWidget {
  const MobileConfirmSheet({
    super.key,
    required this.origin,
    required this.onCancel,
    required this.onConfirm,
  });

  final String origin;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return MobileScrim(
      title: '确认导入',
      onClose: onCancel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('来源：$origin', style: TypeScale.body),
          const SizedBox(height: 10),
          const Text(
            '导入会整体替换本机的计划表、历史与偏好。'
            '当前文件会先备份成 .pre-import.bak。',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text('确认覆盖'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
