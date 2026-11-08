import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../design/tokens.dart';
import '../domain/calendar_rules.dart';
import '../domain/plan.dart';
import '../domain/time_math.dart';
import '../platform/reminders.dart';

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

/// 计划表选择 + 单日指派 + 改表名。
class MobilePlanSheet extends StatefulWidget {
  const MobilePlanSheet({
    super.key,
    required this.data,
    required this.now,
    required this.onClose,
    required this.onAssign,
    required this.onEditPlan,
    required this.onRenamePlan,
  });

  final AppData data;
  final DateTime now;
  final VoidCallback onClose;
  final void Function(String dateKey, String? planId) onAssign;
  final ValueChanged<String> onEditPlan;
  final void Function(String planId, String name) onRenamePlan;

  @override
  State<MobilePlanSheet> createState() => _MobilePlanSheetState();
}

class _MobilePlanSheetState extends State<MobilePlanSheet> {
  /// 正在改名的表 id。改名是**就地编辑**，不弹第二个浮层：手机上叠两层
  /// 浮层很容易把「取消」按成「保存」，而且遮罩会盖住要对照的内容。
  String? _renamingId;
  TextEditingController? _nameCtrl;
  FocusNode? _nameFocus;

  @override
  void dispose() {
    _nameCtrl?.dispose();
    _nameFocus?.dispose();
    super.dispose();
  }

  void _startRename(Plan plan) {
    _nameCtrl?.dispose();
    _nameFocus?.dispose();
    setState(() {
      _renamingId = plan.id;
      _nameCtrl = TextEditingController(text: plan.name)
        ..selection = TextSelection.collapsed(offset: plan.name.length);
      _nameFocus = FocusNode();
    });
  }

  void _finishRename(Plan plan) {
    final ctrl = _nameCtrl;
    final name = ctrl?.text.trim() ?? '';
    if (name.isNotEmpty && name != plan.name) {
      widget.onRenamePlan(plan.id, name);
    }
    setState(() {
      _renamingId = null;
      _nameCtrl?.dispose();
      _nameCtrl = null;
      _nameFocus?.dispose();
      _nameFocus = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final todayKey = TimeMath.dateKey(widget.now);
    final active = data.forDate(widget.now);
    return MobileScrim(
      title: '计划表',
      onClose: widget.onClose,
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
              renaming: _renamingId == plan.id,
              nameController: _renamingId == plan.id ? _nameCtrl : null,
              nameFocus: _renamingId == plan.id ? _nameFocus : null,
              onStartRename: () => _startRename(plan),
              onFinishRename: () => _finishRename(plan),
              onUseToday: () => widget.onAssign(todayKey, plan.id),
              onEdit: () => widget.onEditPlan(plan.id),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onAssign(todayKey, null),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('今天恢复按规则自动'),
            ),
          ),
          const Divider(height: 24),
          Text('接下来 7 天', style: TypeScale.section),
          const SizedBox(height: 8),
          for (var i = 0; i < 7; i++)
            _DayAssignRow(
              date: DateTime(widget.now.year, widget.now.month, widget.now.day + i),
              data: data,
              onAssign: widget.onAssign,
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
    required this.renaming,
    required this.nameController,
    required this.nameFocus,
    required this.onStartRename,
    required this.onFinishRename,
    required this.onUseToday,
    required this.onEdit,
  });

  final Plan plan;
  final bool active;
  final bool overridden;
  final bool renaming;
  final TextEditingController? nameController;
  final FocusNode? nameFocus;
  final VoidCallback onStartRename;
  final VoidCallback onFinishRename;
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
          if (renaming)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    focusNode: nameFocus,
                    autofocus: true,
                    style: TypeScale.body.copyWith(color: Palette.text),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onFinishRename(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Palette.sunken,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.chip),
                        borderSide: BorderSide(color: Palette.accent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.chip),
                        borderSide: BorderSide(color: Palette.accent),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onFinishRename,
                  child: const Text('保存'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: Text(plan.name, style: TypeScale.title)),
                if (active)
                  Text(
                    overridden ? '今天·手动' : '今天·生效',
                    style: TypeScale.labelSmall,
                  ),
                IconButton(
                  onPressed: onStartRename,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  color: Palette.muted,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  tooltip: '改表名',
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

/// 数据页：导入导出、主题、到点提醒、云同步路线说明。
class MobileDataSheet extends StatelessWidget {
  const MobileDataSheet({
    super.key,
    required this.dataPath,
    required this.theme,
    required this.busy,
    required this.remindersEnabled,
    required this.access,
    required this.onClose,
    required this.onTheme,
    required this.onExport,
    required this.onImport,
    required this.onReminders,
    required this.onRequestAccess,
  });

  final String dataPath;
  final AppTheme theme;
  final bool busy;
  final bool remindersEnabled;
  final ReminderAccess access;
  final VoidCallback onClose;
  final ValueChanged<AppTheme> onTheme;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final ValueChanged<bool> onReminders;
  final VoidCallback onRequestAccess;

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
          Text('到点提醒', style: TypeScale.section),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('每段开始时弹一条通知', style: TypeScale.body),
                    Text(
                      remindersEnabled ? '按接下来 7 天的计划排程' : '关掉后不会推送任何通知',
                      style: TypeScale.labelSmall,
                    ),
                  ],
                ),
              ),
              Switch(value: remindersEnabled, onChanged: onReminders),
            ],
          ),
          if (remindersEnabled) ...[
            const SizedBox(height: 6),
            _AccessLine(access: access, onRequest: onRequestAccess),
            const SizedBox(height: 6),
            Text(
              'OPPO / 小米 / vivo 等系统默认会限制后台，'
              '请在「设置 → 应用 → 我的时间」里允许自启动、后台运行与通知；'
              '否则界面里开着开关也可能收不到。',
              style: TypeScale.labelSmall,
            ),
          ],
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

/// 权限状态提示。两项系统权限各自独立，缺哪个就单独说哪个，不要笼统
/// 说「权限不足」—— 用户去设置里根本不知道该开哪一项。
class _AccessLine extends StatelessWidget {
  const _AccessLine({required this.access, required this.onRequest});

  final ReminderAccess access;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    if (access.ready) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 15, color: Palette.study),
          const SizedBox(width: 5),
          Expanded(
            child: Text('通知与精确闹钟都已放行', style: TypeScale.labelSmall),
          ),
        ],
      );
    }
    final missing = [
      if (!access.notifications) '通知',
      if (!access.exact) '精确闹钟',
    ].join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 15, color: Palette.exercise),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '系统还没允许$missing，提醒可能不响或迟到几分钟',
                style: TypeScale.labelSmall,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRequest,
            child: const Text('去授权'),
          ),
        ),
      ],
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
