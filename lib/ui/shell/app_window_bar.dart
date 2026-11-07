import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_view.dart';
import '../../design/tokens.dart';
import '../widgets/hover_intent.dart';
import '../widgets/segmented.dart';

/// 顶栏。#9 之后右侧是「今天：表名（来源）⌄ / 看板编辑汇总 / 计划表 /
/// 设置」，最右三个窗口按钮按 Windows 习惯排「最小化 → 最大化 → 关闭」。
///
/// 「工作日 / 节假日」二选一与全局周期弹窗已下线：日期归属由每张表自己的
/// 重复规则自动判定，顶栏只负责显示结论和允许改判当天。
/// 主题、悬浮窗、开机自启在齿轮设置面板里。
class AppWindowBar extends StatelessWidget {
  const AppWindowBar({
    super.key,
    required this.dateLabel,
    required this.planLabel,
    required this.view,
    required this.onViewChanged,
    required this.planPickerOpen,
    required this.onPlanPicker,
    required this.planManagerOpen,
    required this.onPlanManager,
    required this.settingsOpen,
    required this.onSettings,
    required this.maximized,
    required this.onToggleMaximize,
    required this.onClose,
    required this.onMinimize,
  });

  /// 例如「11月5日 周四」。
  final String dateLabel;

  /// 例如「工作日（按星期几）」/「出差（特殊日期）」/「备考（手动改判）」。
  /// 来源必须可见，否则「今天为什么是这张表」就成黑盒了。
  final String planLabel;

  final AppView view;
  final ValueChanged<AppView> onViewChanged;

  final bool planPickerOpen;
  final VoidCallback onPlanPicker;

  final bool planManagerOpen;
  final VoidCallback onPlanManager;

  /// 设置面板是否展开。展开时齿轮按钮用强调色描边。
  final bool settingsOpen;
  final VoidCallback onSettings;

  /// 最大化时窗口按钮换成「还原」，双击顶栏空白也走同一个动作。
  final bool maximized;
  final VoidCallback onToggleMaximize;

  final VoidCallback onClose;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 8);
    return SizedBox(
      height: Spacing.barHeight,
      child: Stack(
        children: [
          // 整条顶栏都能拖动，不只左边那块标题区；双击空白 = 最大化/还原。
          // 这里刻意不挂 move 光标：顶栏右侧全是按钮，底层再压一层
          // MouseRegion(move) 会和按钮的 click 光标在 2px 缝隙里来回抢，
          // 鼠标扫过最小化/最大化时就表现为闪烁。拖动功能不变，
          // move 光标由外围 18px 边圈提供。
          Positioned.fill(
            child: WindowDragArea(
              onToggleMaximize: onToggleMaximize,
              showMoveCursor: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.pad),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '我的时间',
                          style: TypeScale.section.copyWith(letterSpacing: 0.3),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateLabel,
                          style: TypeScale.labelSmall.copyWith(
                            color: Palette.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _PlanTag(
                  label: planLabel,
                  active: planPickerOpen,
                  onTap: onPlanPicker,
                ),
                gap,
                Segmented<AppView>(
                  items: AppView.values,
                  value: view,
                  onChanged: onViewChanged,
                  labelOf: (v) => v.label,
                ),
                gap,
                BarButton(
                  label: '计划表',
                  icon: Icons.layers_outlined,
                  onTap: onPlanManager,
                  active: planManagerOpen,
                  tooltip: '新建 / 编辑 / 排序计划表',
                ),
                gap,
                BarButton(
                  label: '设置',
                  icon: Icons.settings_outlined,
                  onTap: onSettings,
                  active: settingsOpen,
                  tooltip: settingsOpen ? '收起设置面板' : '打开设置面板',
                ),
                const SizedBox(width: 6),
                // 三个窗口按钮按 Windows 习惯排：最小化 → 最大化/还原 → 关闭。
                // 整组包一层 MouseRegion，让按钮之间的 2px 缝隙也归按钮区：
                // 鼠标在按钮之间移动时不会再落到下面的拖动层上，光标不打架。
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WindowButton(
                        icon: Icons.remove,
                        onTap: onMinimize,
                        semanticLabel: '最小化到托盘',
                      ),
                      const SizedBox(width: 2),
                      WindowButton(
                        icon: maximized ? Icons.filter_none : Icons.crop_square,
                        onTap: onToggleMaximize,
                        semanticLabel: maximized ? '还原窗口' : '最大化',
                      ),
                      const SizedBox(width: 2),
                      WindowButton(
                        icon: Icons.close,
                        onTap: onClose,
                        semanticLabel: '关闭窗口',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 窗口拖动区，顶栏和外围 18px 灰紫地面共用一份实现。
///
/// [showMoveCursor] 决定是否显示四向箭头。顶栏那一份传 false：它的右侧
/// 全是按钮，move 光标会和按钮的 click 光标在缝隙里反复切换，看起来就是
/// 鼠标扫过按钮时闪一下。外围边圈没有按钮，传 true 正常给拖动提示。
///
/// 注意 GestureDetector 用 opaque：它要能接住那些没有被按钮/分段控件
/// 命中的空白区域，否则「整条顶栏可拖」就只剩标题那一小块。
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({
    super.key,
    required this.onToggleMaximize,
    this.showMoveCursor = true,
  });

  final VoidCallback onToggleMaximize;
  final bool showMoveCursor;

  @override
  Widget build(BuildContext context) {
    final detector = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: onToggleMaximize,
      child: const SizedBox.expand(),
    );
    return showMoveCursor
        ? MouseRegion(cursor: SystemMouseCursors.move, child: detector)
        : detector;
  }
}

/// 「今天：工作日（按星期几）⌄」。表名加粗、来源弱一级，点一下展开选表浮层。
class _PlanTag extends StatefulWidget {
  const _PlanTag({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PlanTag> createState() => _PlanTagState();
}

class _PlanTagState extends State<_PlanTag> {
  @override
  Widget build(BuildContext context) {
    final i = widget.label.indexOf('（');
    final name = i < 0 ? widget.label : widget.label.substring(0, i);
    final source = i < 0 ? '' : widget.label.substring(i);
    return HoverIntent(
      onTap: widget.onTap,
      tooltip: '点一下切换今天使用的计划表',
      builder: (context, hover) {
        final border = widget.active
            ? Palette.accent
            : (hover ? Palette.control : Palette.border);
        return AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: hover ? Palette.hover : Palette.surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  style: TypeScale.labelSmall,
                  children: [
                    TextSpan(
                      text: '今天：',
                      style: TextStyle(color: Palette.muted),
                    ),
                    TextSpan(
                      text: name,
                      style: TextStyle(
                        color: Palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (source.isNotEmpty)
                      TextSpan(
                        text: source,
                        style: TextStyle(color: Palette.faint),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.expand_more,
                size: 13,
                color: widget.active ? Palette.accent : Palette.faint,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 顶栏右侧的窗口按钮（最小化 / 最大化 / 关闭）。
///
/// v0.9.2：Jason 反馈「鼠标经过最小化 / 关闭按钮时会有深色显示」。
/// 这里不挂 Tooltip（窗口按钮语义众所周知，浮层反而是 hover 状态被
/// 打回的干扰源），只用 Semantics 保留朗读标签；命中区域由 HoverIntent
/// 的 opaque 层严格锁在 26x26 的按钮块内，停留 110ms 才亮起。
class WindowButton extends StatelessWidget {
  const WindowButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: hover ? Palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Icon(
          icon,
          size: 15,
          color: hover ? Palette.text : Palette.faint,
        ),
      ),
    );
  }
}
