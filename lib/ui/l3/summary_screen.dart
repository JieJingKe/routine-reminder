import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/app_data.dart';
import '../../data/summary.dart';
import '../../design/tokens.dart';
import '../../domain/category.dart';
import '../../domain/time_math.dart';
import '../widgets/app_card.dart';
import '../widgets/segmented.dart';
import 'summary_charts.dart';

/// L3 汇总层：独立视图，替换整个内容区（与 L2 的「叠加」不同）。
///
/// 三种周期三种图形，绝不复用同一张环；没有数据的日子画空心格，
/// 不画成 0，也不用计划值填充（验收 #26 / #30）。
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.data,
    required this.now,
    this.downloadDirOverride,
    this.onExported,
    this.onDayTap,
  });

  final AppData data;
  final DateTime now;

  /// 测试时把文件写到临时目录，不碰用户真实的下载文件夹。
  final Directory? downloadDirOverride;

  /// 测试里拿到导出结果用；正式运行不需要。
  final void Function(File file)? onExported;

  /// 本月日历点某一天 → 由外壳弹出单日指派浮层。
  final ValueChanged<DateTime>? onDayTap;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  SummaryPeriod _period = SummaryPeriod.day;
  bool _exporting = false;

  Future<Directory> _downloadsDir() async {
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } on Object {
      // 测试环境没有注册平台通道，走下面的环境变量兜底。
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return Directory('$home${Platform.pathSeparator}Downloads');
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = widget.downloadDirOverride ?? await _downloadsDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final name = reportFileName(widget.now, _period);
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      // 同步写：文件只有几 KB，没必要为它引入一层异步。
      // 顺带避开 flutter_test 的假异步环境里 dart:io 回调不回来的坑。
      file.writeAsStringSync(
        buildMarkdown(data: widget.data, now: widget.now, period: _period),
        flush: true,
      );
      widget.onExported?.call(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到下载文件夹：$name'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            width: 340,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pad,
        16,
        Spacing.pad,
        Spacing.pad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('时间统计', style: TypeScale.section),
              const SizedBox(width: 20),
              Segmented<SummaryPeriod>(
                items: SummaryPeriod.values,
                value: _period,
                onChanged: (p) => setState(() => _period = p),
                labelOf: (p) => p.label,
              ),
              const Spacer(),
              _RangeTag(period: _period, now: widget.now),
              const SizedBox(width: 10),
              BarButton(
                label: _exporting ? '导出中…' : '导出 MD',
                onTap: _exporting ? () {} : _export,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: switch (_period) {
              SummaryPeriod.day => _TodayView(
                data: widget.data,
                now: widget.now,
              ),
              SummaryPeriod.week => _WeekView(
                data: widget.data,
                now: widget.now,
              ),
              SummaryPeriod.month => _MonthView(
                data: widget.data,
                now: widget.now,
                onDayTap: widget.onDayTap,
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// 当前统计范围。稿子里它是标题行右侧的一枚小标签。
class _RangeTag extends StatelessWidget {
  const _RangeTag({required this.period, required this.now});

  final SummaryPeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final dates = SummaryModel.datesOf(period, now);
    final text = switch (period) {
      SummaryPeriod.day => '${now.month}月${now.day}日',
      SummaryPeriod.week =>
        dates.isEmpty
            ? '—'
            : '${dates.first.month}/${dates.first.day} – '
                  '${dates.last.month}/${dates.last.day}',
      SummaryPeriod.month => '${now.year}年${now.month}月',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Palette.panel2,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TypeScale.labelSmall.copyWith(fontFeatures: TypeScale.tabular),
      ),
    );
  }
}

// ---------------------------------------------------------------- 今天

class _TodayView extends StatelessWidget {
  const _TodayView({required this.data, required this.now});

  final AppData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final day = SummaryModel.forDay(data, now, now);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${TimeMath.dateKey(now)} · ${day.planName}',
                style: TypeScale.section,
              ),
              const SizedBox(height: 2),
              // 这列只有 320 宽，说明写长了会折出一个孤零零的「00」。
              Text('外环 计划 · 内环 实际', style: TypeScale.labelSmall),
              Expanded(
                child: Center(child: CompareRing(day: day, diameter: 290)),
              ),
              Text(
                day.overrideCount == 0
                    ? '两环重合：今天没有纠偏。'
                    : '今天纠偏 ${day.overrideCount} 段，错开处就是偏差。',
                style: TypeScale.labelSmall.copyWith(color: Palette.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final c in Category.values)
                    if ((day.planMinutes[c] ?? 0) > 0 ||
                        (day.actualMinutes[c] ?? 0) > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LegendDot(color: Palette.of(c), size: 7),
                          const SizedBox(width: 5),
                          Text(c.shortLabel, style: TypeScale.labelSmall),
                        ],
                      ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: AppCard(
            // 窗口按稿子压到 600 高后，明细表 + 偏差集中会超出一屏。
            // 可滚动而不是裁掉，也不会在内容少时让卡片缩成一小条。
            child: _FillingScroll(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('计划 / 实际 / 偏差', style: TypeScale.section),
                  const SizedBox(height: 2),
                  Text(
                    '偏差 = 实际 − 计划，单位分钟；绿 / 橙只表示多或少，不表示好坏',
                    style: TypeScale.labelSmall,
                  ),
                  const SizedBox(height: 14),
                  const _TableHead(),
                  Divider(color: Palette.rule, height: 1),
                  for (final c in Category.values)
                    _TableRow(
                      label: c.label,
                      color: Palette.of(c),
                      plan: day.planMinutes[c] ?? 0,
                      actual: day.actualMinutes[c] ?? 0,
                    ),
                  Divider(color: Palette.rule, height: 1),
                  _TableRow(
                    label: '未安排',
                    color: Palette.unplanned,
                    plan: day.unplannedMinutes,
                    actual: day.unplannedMinutes,
                  ),
                  const SizedBox(height: 16),
                  Text('偏差集中', style: TypeScale.labelSmall),
                  const SizedBox(height: 8),
                  for (final c in _deviations(day))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          LegendDot(color: Palette.of(c), size: 7),
                          const SizedBox(width: 8),
                          Text(c.label, style: TypeScale.label),
                          const Spacer(),
                          Text(
                            '${day.deviation(c) > 0 ? '+' : ''}${day.deviation(c)} 分钟',
                            style: TypeScale.label.copyWith(
                              color: deviationColor(day.deviation(c)),
                              fontFeatures: TypeScale.tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_deviations(day).isEmpty)
                    Text(
                      '今天没有偏差，实际和计划完全一致。',
                      style: TypeScale.labelSmall.copyWith(
                        color: Palette.ghost,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    '学习 + 锻炼（实际）：${TimeMath.formatDurationCn(day.focusMinutes)}',
                    style: TypeScale.label.copyWith(color: Palette.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    SummaryModel.historicalCaveat,
                    style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<Category> _deviations(DaySummary day) {
  final out = Category.values
      .where((c) => day.deviation(c) != 0)
      .toList(growable: false);
  out.sort((a, b) => day.deviation(b).abs().compareTo(day.deviation(a).abs()));
  return out;
}

class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text('分类', style: TypeScale.labelSmall)),
          for (final t in const ['计划', '实际', '偏差'])
            SizedBox(
              width: 76,
              child: Text(
                t,
                textAlign: TextAlign.right,
                style: TypeScale.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.label,
    required this.color,
    required this.plan,
    required this.actual,
  });

  final String label;
  final Color color;
  final int plan;
  final int actual;

  @override
  Widget build(BuildContext context) {
    final diff = actual - plan;
    final diffText = diff == 0 ? '—' : (diff > 0 ? '+$diff' : '$diff');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                LegendDot(color: color, size: 7),
                const SizedBox(width: 8),
                Text(label, style: TypeScale.body),
              ],
            ),
          ),
          for (final t in <(String, Color?)>[
            ('$plan', null),
            ('$actual', null),
            (diffText, deviationColor(diff)),
          ])
            SizedBox(
              width: 76,
              child: Text(
                t.$1,
                textAlign: TextAlign.right,
                style: TypeScale.body.copyWith(
                  color: t.$2 ?? Palette.text,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 本周

/// 内容少时卡片撑满可视高度，内容多时仍然可滚。
/// 少了这个 minHeight，周/月卡片会在屏幕下半截留一大片空地，像是没画完。
class _FillingScroll extends StatelessWidget {
  const _FillingScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: child,
      ),
    ),
  );
}

class _WeekView extends StatelessWidget {
  const _WeekView({required this.data, required this.now});

  final AppData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = SummaryModel.range(data, SummaryPeriod.week, now);
    return _FillingScroll(
      child: AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('本周', style: TypeScale.section),
                const Spacer(),
                Text('每根柱固定 24 小时', style: TypeScale.labelSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '看的是每天按重复规则判到了哪张表：'
              '柱子下方写着那天的表名，若相邻几天该换表却长得一样，'
              '说明重复规则没配好。',
              style: TypeScale.labelSmall.copyWith(color: Palette.muted),
            ),
            const SizedBox(height: 16),
            WeekBars(days: days),
            const SizedBox(height: 14),
            Text(
              '浅灰实心 = 还没到的日子；空心 = 安装之前，无数据。'
              '两者都不是 0 分钟，也不拿计划值填充。',
              style: TypeScale.labelSmall.copyWith(color: Palette.ghost),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 本月

class _MonthView extends StatelessWidget {
  const _MonthView({required this.data, required this.now, this.onDayTap});

  final AppData data;
  final DateTime now;
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final days = SummaryModel.range(data, SummaryPeriod.month, now);
    final withData = days.where((d) => d.hasData).toList();
    final focus = withData.fold(0, (s, d) => s + d.focusMinutes);
    final avg = withData.isEmpty ? 0 : focus ~/ withData.length;

    return _FillingScroll(
      child: AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${now.year} 年 ${now.month} 月', style: TypeScale.section),
                const Spacer(),
                Text(
                  '有数据 ${withData.length} 天 · 学习+锻炼日均 '
                  '${TimeMath.formatDurationCn(avg)}',
                  style: TypeScale.labelSmall.copyWith(
                    fontFeatures: TypeScale.tabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '格子亮度 = 当天「学习 + 锻炼」的实际分钟数。'
              '点击任意一天可指派那天用哪张计划表。',
              style: TypeScale.labelSmall.copyWith(color: Palette.muted),
            ),
            const SizedBox(height: 16),
            MonthHeatmap(days: days, onDayTap: onDayTap),
          ],
        ),
      ),
    );
  }
}
