import 'package:flutter/material.dart';

import '../widgets/hover_intent.dart';

import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../design/tokens.dart';
import '../widgets/segmented.dart';

/// 设置浮层。挂在窗口外壳 `Stack` 的最后一层，直接作为 `Stack.children`
/// 的一员（内部返回 `Positioned.fill`）。
///
/// 刻意**不走 Navigator / showDialog**：那会另起一条 Overlay route，父树
/// setState 时它不跟着重建，而 `Palette` 是静态门面 —— 在面板里切主题会
/// 出现「窗口变色了、面板还是旧配色」。放在主树里，一次 setState 整窗
/// 一起换，主题、开关状态都是即时反馈，也不用手动同步两份状态。
///
/// 几何沿用 UI 稿 v2 的 `.settings`：上 74、右 22、宽 296，卡片圆角 +
/// 浮层阴影，`surface` 底 + `control` 边。
class SettingsLayer extends StatelessWidget {
  const SettingsLayer({
    super.key,
    required this.theme,
    required this.onThemeChanged,
    required this.floatEnabled,
    required this.onFloatChanged,
    required this.openAtLogin,
    required this.onAutostartChanged,
    required this.onManagePlans,
    required this.onClose,
  });

  final AppTheme theme;
  final ValueChanged<AppTheme> onThemeChanged;

  final bool floatEnabled;
  final VoidCallback onFloatChanged;

  final bool openAtLogin;
  final VoidCallback onAutostartChanged;

  final VoidCallback onManagePlans;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // 压暗遮罩：单击面板外任意位置收起。也挡住打开设置时的窗口拖动，
          // 免得误把面板当成标题栏拖走。底下内容必须明显退到后面，
          // 否则窗口底色和 surface 卡片是相邻色，浮层读不出「在最前面」。
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
            top: Spacing.pad + Spacing.barHeight + 4,
            right: 22,
            width: 296,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: Focus(
                autofocus: true,
                child: SettingsPanel(
                  theme: theme,
                  onThemeChanged: onThemeChanged,
                  floatEnabled: floatEnabled,
                  onFloatChanged: onFloatChanged,
                  openAtLogin: openAtLogin,
                  onAutostartChanged: onAutostartChanged,
                  onManagePlans: onManagePlans,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置面板本体。也可单独 pump 做截图 / 交互测试。
///
/// 三项都是「二级配置」：改完立刻生效并写进 `data.json`，不需要「保存 /
/// 取消」—— 面板上没有待提交状态，多一个确定按钮只会让人以为还要点一下。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.theme,
    required this.onThemeChanged,
    required this.floatEnabled,
    required this.onFloatChanged,
    required this.openAtLogin,
    required this.onAutostartChanged,
    required this.onManagePlans,
    required this.onClose,
  });

  final AppTheme theme;
  final ValueChanged<AppTheme> onThemeChanged;

  final bool floatEnabled;
  final VoidCallback onFloatChanged;

  final bool openAtLogin;
  final VoidCallback onAutostartChanged;

  final VoidCallback onManagePlans;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.control),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: Palette.windowShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('设置', style: TypeScale.section),
              const Spacer(),
              _PanelClose(onTap: onClose),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '改动立即生效，并记住选择。',
            style: TypeScale.labelSmall.copyWith(color: Palette.faint),
          ),
          const SizedBox(height: 14),

          const _SectionLabel('外观'),
          const SizedBox(height: 6),
          Segmented<AppTheme>(
            items: AppTheme.values,
            value: theme,
            onChanged: onThemeChanged,
            labelOf: (t) => t.label,
            fillWidth: true,
          ),
          const SizedBox(height: 6),
          Text(
            '切换整套窗口配色；下次启动沿用这次选择。',
            style: TypeScale.labelSmall.copyWith(
              color: Palette.faint,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Palette.rule),
          const SizedBox(height: 14),

          const _SectionLabel('常驻'),
          const SizedBox(height: 4),
          _SettingRow(
            label: '桌面悬浮窗',
            detail: '在桌面右下角显示 168px 悬浮环',
            value: floatEnabled,
            onChanged: onFloatChanged,
          ),
          const SizedBox(height: 4),
          _SettingRow(
            label: '开机自启',
            detail: '开机只启动托盘与悬浮窗，不弹主窗口',
            value: openAtLogin,
            onChanged: onAutostartChanged,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Palette.rule),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: BarButton(
              label: '计划表管理',
              icon: Icons.layers_outlined,
              onTap: onManagePlans,
              tooltip: '新建 / 编辑 / 排序 / 设置重复规则',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '单击空白处或按 Esc 收起设置',
            style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TypeScale.labelSmall.copyWith(
        color: Palette.muted,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _PanelClose extends StatefulWidget {
  const _PanelClose({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PanelClose> createState() => _PanelCloseState();
}

class _PanelCloseState extends State<_PanelClose> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      tooltip: '收起设置',
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

/// 一整行都能点，不只那个小开关 —— 目标区越大越不容易点空。
class _SettingRow extends StatefulWidget {
  const _SettingRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final VoidCallback onChanged;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onChanged,
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: hover ? Palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TypeScale.label.copyWith(color: Palette.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.detail,
                    style: TypeScale.labelSmall.copyWith(color: Palette.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _SettingSwitch(value: widget.value),
          ],
        ),
      ),
    );
  }
}

/// 自己画开关，不用 Material `Switch`：那套默认配色不认 tokens，
/// 在深色主题下轨道会亮得突兀。
class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.fast,
      width: 34,
      height: 18,
      decoration: BoxDecoration(
        color: value ? Palette.accent : Palette.control,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: AnimatedAlign(
        duration: Motion.fast,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
