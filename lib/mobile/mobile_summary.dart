import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../data/summary.dart';
import '../design/tokens.dart';
import '../domain/category.dart';
import '../domain/time_math.dart';
import '../ui/widgets/app_card.dart';

/// 手机竖屏 L3：按今天 / 本周 / 本月回看。
///
/// 计算直接走 `SummaryModel.range`（与桌面版、Markdown 导出同一口径），
/// 只是把桌面三张图改成单列数字条 —— 竖屏放不下 1060px 宽的图表。
class MobileSummary extends StatefulWidget {
  const MobileSummary({
    super.key,
    required this.data,
    required this.now,
    required this.onExportReport,
  });

  final AppData data;
  final DateTime now;
  final void Function(String fileName, String content) onExportReport;

  @override
  State<MobileSummary> createState() => _MobileSummaryState();
}

class _MobileSummaryState extends State<MobileSummary> {
  SummaryPeriod _period = SummaryPeriod.day;

  @override
  Widget build(BuildContext context) {
    final days = SummaryModel.range(widget.data, _period, widget.now);
    final withData = days.where((d) => d.hasData).toList();
    var planned = 0;
    var actual = 0;
    var unplanned = 0;
    final planByCat = <Category, int>{for (final c in Category.values) c: 0};
    final actualByCat = <Category, int>{for (final c in Category.values) c: 0};
    for (final d in withData) {
      planned += d.planMinutes.values.fold(0, (a, b) => a + b);
      actual += d.actualMinutes.values.fold(0, (a, b) => a + b);
      unplanned += d.unplannedMinutes;
      for (final c in Category.values) {
        planByCat[c] = (planByCat[c] ?? 0) + (d.planMinutes[c] ?? 0);
        actualByCat[c] = (actualByCat[c] ?? 0) + (d.actualMinutes[c] ?? 0);
      }
    }
    final maxMinutes = [
      1,
      ...Category.values.map(
        (c) => (planByCat[c] ?? 0) > (actualByCat[c] ?? 0)
            ? (planByCat[c] ?? 0)
            : (actualByCat[c] ?? 0),
      ),
    ].reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final p in SummaryPeriod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: p == _period,
                    onSelected: (_) => setState(() => _period = p),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('共 ${withData.length} 天有数据', style: TypeScale.section),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Kpi(
                        label: '计划',
                        value: TimeMath.formatDuration(planned),
                      ),
                    ),
                    Expanded(
                      child: _Kpi(
                        label: '实际',
                        value: TimeMath.formatDuration(actual),
                      ),
                    ),
                    Expanded(
                      child: _Kpi(
                        label: '空档',
                        value: TimeMath.formatDuration(unplanned),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('各分类 · 计划 / 实际', style: TypeScale.section),
                const SizedBox(height: 12),
                for (final c in Category.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CategoryBar(
                      category: c,
                      planned: planByCat[c] ?? 0,
                      actual: actualByCat[c] ?? 0,
                      maxMinutes: maxMinutes,
                    ),
                  ),
                Text(
                  SummaryModel.historicalCaveat,
                  style: TypeScale.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => widget.onExportReport(
              reportFileName(widget.now, _period),
              buildMarkdown(
                data: widget.data,
                now: widget.now,
                period: _period,
              ),
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('导出这一期的 Markdown 报告'),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TypeScale.cardLabel),
        const SizedBox(height: 4),
        Text(value, style: TypeScale.kpi),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.category,
    required this.planned,
    required this.actual,
    required this.maxMinutes,
  });

  final Category category;
  final int planned;
  final int actual;
  final int maxMinutes;

  @override
  Widget build(BuildContext context) {
    final color = Palette.of(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(category.label, style: TypeScale.body)),
            Text(
              '${TimeMath.formatDuration(planned)} / '
              '${TimeMath.formatDuration(actual)}',
              style: TypeScale.label,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: planned / maxMinutes,
                  minHeight: 5,
                  backgroundColor: Palette.sunken,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: actual / maxMinutes,
                  minHeight: 5,
                  backgroundColor: Palette.sunken,
                  color: color.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
