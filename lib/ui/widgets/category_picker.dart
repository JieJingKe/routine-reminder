import 'package:flutter/material.dart';

import 'hover_intent.dart';

import '../../design/tokens.dart';
import '../../domain/category.dart';

/// 七个分类的快选浮层。
///
/// 看板的「我实际在做…」和编辑层的「这块算哪一类？」共用它。
/// 两处都是**单选、选完立刻关闭、不做二次确认** —— 这种高频小操作
/// 多一步确认就会让人放弃，数据也就采集不到了。
Future<Category?> showCategoryPicker(
  BuildContext context, {
  Category? initial,
  String title = '这块算哪一类？',
}) {
  return showDialog<Category>(
    context: context,
    builder: (_) => _CategoryPicker(initial: initial, title: title),
  );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.initial, required this.title});

  final Category? initial;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.raised,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: TypeScale.section),
      content: SizedBox(
        width: 340,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in Category.values)
              _Choice(
                category: c,
                highlighted: c == initial,
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatefulWidget {
  const _Choice({
    required this.category,
    required this.highlighted,
    required this.onTap,
  });

  final Category category;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return HoverIntent(
      onTap: widget.onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: hover || widget.highlighted
              ? Palette.control.withValues(alpha: 0.55)
              : Palette.sunken,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: hover ? Palette.of(c) : Palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Palette.of(c),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(c.label, style: TypeScale.label),
          ],
        ),
      ),
    );
  }
}
