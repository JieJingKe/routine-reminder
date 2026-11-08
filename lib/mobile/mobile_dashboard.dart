import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../design/tokens.dart';
import '../domain/category.dart';
import '../domain/day_block.dart';
import '../domain/stats.dart';
import '../domain/time_math.dart';
import '../ui/ring/dual_ring.dart';
import '../ui/widgets/app_card.dart';

/// 手机竖屏 L1：把 24 小时摊开，一眼看到「现在该做什么 / 接着是什么」。
///
/// 桌面版是左环右三卡的横屏布局，这里改成单列滚动；环、卡片配色、
/// 时间判定全部复用同一套 domain / tokens，不另立一套口径。
class MobileDashboard extends StatelessWidget {
  const MobileDashboard({
    super.key,
    required this.data,
    required this.now,
    required this.onOpenPlans,
  });

  final AppData data;
  final DateTime now;
  final VoidCallback onOpenPlans;

  @override
  Widget build(BuildContext context) {
    final resolved = data.forDate(now);
    final blocks = resolved.blocks;
    final nowMinute = now.hour * 60 + now.minute;
    final totals = DayTotals.of(blocks);
    final current = TimeMath.blockAt(blocks, nowMinute);
    final next = TimeMath.nextAfter(blocks, nowMinute);
    final screenWidth = MediaQuery.of(context).size.width;
    final diameter = (screenWidth - 48).clamp(220.0, 340.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpenPlans,
            borderRadius: BorderRadius.circular(Radii.card),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resolved.planName, style: TypeScale.title),
                        const SizedBox(height: 2),
                        Text(
                          '${_dateLabel(now)} · ${resolved.source}',
                          style: TypeScale.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: DualRing(
              blocks: blocks,
              nowMinute: nowMinute,
              diameter: diameter,
              showCenter: true,
              centerTitle: TimeMath.formatDuration(totals.scheduled),
              centerSub: totals.unplanned > 0
                  ? '空档 ${TimeMath.formatDuration(totals.unplanned)}'
                  : '已排满',
              centerSubInteractive: totals.unplanned > 0,
            ),
          ),
          const SizedBox(height: 14),
          _NowCard(block: current, nowMinute: nowMinute),
          const SizedBox(height: 10),
          _NextCard(block: next, nowMinute: nowMinute),
          const SizedBox(height: 14),
          _MiniLegend(totals: totals),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${d.month}月${d.day}日 周${week[d.weekday - 1]}';
  }
}

/// 以 23:00 为一天起点的坐标换算，和 TimeMath.sortKey 保持同一口径。
int _shift(int minute) => minute >= TimeMath.dayStartMinute
    ? minute - TimeMath.minutesPerDay
    : minute;

int _remaining(DayBlock b, int nowMinute) {
  final elapsed = _shift(nowMinute) - _shift(b.start);
  final left = b.duration - elapsed;
  return left > 0 ? left : b.duration;
}

int _until(DayBlock b, int nowMinute) {
  final left = _shift(b.start) - _shift(nowMinute);
  return left > 0 ? left : left + TimeMath.minutesPerDay;
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.block, required this.nowMinute});

  final DayBlock? block;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final b = block;
    return AppCard(
      color: Palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('现在该做什么', style: TypeScale.cardLabel),
          const SizedBox(height: 8),
          if (b == null)
            Text('空档 · 未安排', style: TypeScale.hero)
          else
            Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Palette.of(b.category),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name, style: TypeScale.hero),
                      Text(
                        '${TimeMath.formatHm(b.start)} – ${TimeMath.formatHm(b.end)}'
                        ' · ${b.category.label}',
                        style: TypeScale.label,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            b == null
                ? '这一段没有安排具体的事'
                : '还剩 ${TimeMath.formatDuration(_remaining(b, nowMinute))}',
            style: TypeScale.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.block, required this.nowMinute});

  final DayBlock? block;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final b = block;
    return AppCard(
      color: Palette.panel2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('接着是', style: TypeScale.cardLabel),
          const SizedBox(height: 8),
          if (b == null)
            Text('今天没有后续安排', style: TypeScale.body)
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.name,
                    style: TypeScale.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${TimeMath.formatHm(b.start)} · '
                  '${TimeMath.formatDuration(_until(b, nowMinute))}后',
                  style: TypeScale.label,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MiniLegend extends StatelessWidget {
  const _MiniLegend({required this.totals});

  final DayTotals totals;

  @override
  Widget build(BuildContext context) {
    final items = Category.values
        .where((c) => totals.minutesOf(c) > 0)
        .toList();
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final c in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Palette.of(c),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${c.shortLabel} ${TimeMath.formatDuration(totals.minutesOf(c))}',
                style: TypeScale.labelSmall,
              ),
            ],
          ),
      ],
    );
  }
}
