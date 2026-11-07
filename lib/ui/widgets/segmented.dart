import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'hover_intent.dart';

/// 分段选择器。UI 稿 v2 的 `.seg`：底层 panel2 + 1px 边，选中项浮起带阴影。
///
/// 顶栏的「看板/编辑/汇总」「工作日/节假日」、周期规则面板、
/// 汇总页的「今天/本周/本月」全用它，保证三处点起来是同一种手感。
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.labelOf,
    this.compact = false,
    this.fillWidth = false,
  });

  final List<T> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T item) labelOf;

  /// 周期规则面板里三段文字较长，收紧横向 padding。
  final bool compact;

  /// 设置面板里的分段撑满容器宽度，每项等分（UI 稿 `.settings .seg button
  /// { flex: 1 }`）。顶栏仍按内容自适应。
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Palette.panel2,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(Radii.well),
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final item in items)
            fillWidth
                ? Expanded(
                    child: _SegItem<T>(
                      label: labelOf(item),
                      active: item == value,
                      compact: compact,
                      center: true,
                      onTap: () => onChanged(item),
                    ),
                  )
                : _SegItem<T>(
                    label: labelOf(item),
                    active: item == value,
                    compact: compact,
                    onTap: () => onChanged(item),
                  ),
        ],
      ),
    );
  }
}

class _SegItem<T> extends StatefulWidget {
  const _SegItem({
    required this.label,
    required this.active,
    required this.compact,
    required this.onTap,
    this.center = false,
  });

  final String label;
  final bool active;
  final bool compact;
  final bool center;
  final VoidCallback onTap;

  @override
  State<_SegItem<T>> createState() => _SegItemState<T>();
}

class _SegItemState<T> extends State<_SegItem<T>> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      builder: (context, hover) => AnimatedContainer(
        // 停留 110ms 才算 hover，且变色瞬时完成：横扫分段不留渐隐残影。
        duration: Duration.zero,
        alignment: widget.center ? Alignment.center : null,
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 8 : 13,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: widget.active
              ? (hover
                    ? Color.lerp(Palette.raised, Palette.accent, 0.16)!
                    : Palette.raised)
              : (hover ? Palette.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.chip),
          boxShadow: widget.active && Palette.isLight
              ? const [
                  BoxShadow(
                    color: Color(0x2123273A),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : widget.active
              ? const [
                  BoxShadow(
                    color: Color(0x47000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          widget.label,
          textAlign: widget.center ? TextAlign.center : null,
          style: TypeScale.label.copyWith(
            color: widget.active || hover ? Palette.text : Palette.faint,
          ),
        ),
      ),
    );
  }
}

/// 顶栏上的一个独立胶囊按钮（计划表 / 设置）。
class BarButton extends StatefulWidget {
  const BarButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// 设置面板打开、计划表管理展开之类，用强调色边框标出来。
  final bool active;
  final String? tooltip;

  @override
  State<BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<BarButton> {
  @override
  Widget build(BuildContext context) {
    return HoverIntent(
      onTap: widget.onTap,
      tooltip: widget.tooltip,
      builder: (context, hover) => AnimatedContainer(
        // hover 连底一起换，但只在鼠标真正停留后；duration 归零避免
        // 鼠标横扫顶栏时留下一串渐隐的深色方块。
        duration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: hover ? Palette.hover : Palette.panel2,
          border: Border.all(
            color: widget.active
                ? Palette.accent
                : (hover ? Palette.control : Palette.border),
          ),
          borderRadius: BorderRadius.circular(Radii.well),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: 13,
                color: widget.active
                    ? Palette.accent
                    : (hover ? Palette.text : Palette.muted),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              widget.label,
              style: TypeScale.label.copyWith(
                color: widget.active
                    ? Palette.accent
                    : (hover ? Palette.text : Palette.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
