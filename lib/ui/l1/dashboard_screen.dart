import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../design/tokens.dart';
import '../../domain/actual_records.dart';
import '../../domain/category.dart';
import '../../domain/day_block.dart';
import '../../domain/stats.dart';
import '../../domain/time_math.dart';
import '../ring/dual_ring.dart';
import '../widgets/app_card.dart';
import '../widgets/category_picker.dart';

/// L1 看板：三秒能读完的那一屏。
///
/// UI 稿 v2 的布局：左边环 + 图例**直接放在窗口底上**（不套卡片），
/// 右边 384 宽一列三张卡。环是唯一的主角，其余只做明度分层。
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.data,
    required this.now,
    this.editing = false,
    this.onBlocksChanged,
    this.selectedIndex,
    this.onSelect,
    this.onOverride,
    this.blocksOverride,
  });

  final AppData data;
  final DateTime now;

  /// 从计划表编辑器进 L2 时，环要显示**被编辑的那张表**，
  /// 而不是「今天判到的那张」。不传时保持看板原行为。
  final List<DayBlock>? blocksOverride;

  /// L2 把这一屏原样放在滚动区顶部，只把环切成可编辑。
  final bool editing;
  final ValueChanged<List<DayBlock>>? onBlocksChanged;
  final int? selectedIndex;
  final ValueChanged<int?>? onSelect;

  /// 「我实际在做…」的唯一入口。null 时按钮不显示（测试里可以关掉）。
  final ValueChanged<Category>? onOverride;

  @override
  Widget build(BuildContext context) {
    final nowMinute = now.hour * 60 + now.minute;
    final blocks = blocksOverride ?? data.forDate(now).blocks;
    final totals = DayTotals.of(blocks);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pad,
        4,
        Spacing.pad,
        Spacing.pad,
      ),
      child: LayoutBuilder(
        builder: (context, panel) {
          // 窗口拉宽时右栏跟着长一点，但环不被挤；最大 520 免得卡片拉成一条。
          final rightWidth = (panel.maxWidth * 0.32).clamp(384.0, 520.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左列：环 + 图例。刻意不包卡片，让彩色弧直接压在窗口底色上。
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DualRing(
                          blocks: blocks,
                          nowMinute: nowMinute,
                          diameter: _ringDiameter(box.maxHeight),
                          showCenter: true,
                          centerTitle: TimeMath.formatDuration(
                            totals.scheduled,
                          ),
                          centerSub: totals.unplanned > 0
                              ? '空档 ${TimeMath.formatDuration(totals.unplanned)}'
                              : '已排满',
                          // 有空档才让中心那行可悬停；「已排满」时没有可高亮的对象。
                          centerSubInteractive: totals.unplanned > 0,
                          editing: editing,
                          onBlocksChanged: onBlocksChanged,
                          selectedIndex: selectedIndex,
                          onSelect: onSelect,
                        ),
                        const SizedBox(height: 10),
                        _Legend(blocks: blocks, unplanned: totals.unplanned),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: rightWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NowCard(
                      blocks: blocks,
                      nowMinute: nowMinute,
                      actual: TimeMath.blockAt(blocks, nowMinute) == null
                          ? null
                          : ActualRecords.overrideOf(
                              data.records,
                              TimeMath.dateKey(now),
                              TimeMath.blockAt(blocks, nowMinute)!.start,
                            ),
                      onOverride: onOverride == null
                          ? null
                          : () async {
                              final picked = await showCategoryPicker(
                                context,
                                title: '我现在实际在做…',
                              );
                              if (picked != null) onOverride!(picked);
                            },
                    ),
                    const SizedBox(height: 10),
                    _NextCard(blocks: blocks, nowMinute: nowMinute),
                    const SizedBox(height: 10),
                    _GoalsRow(
                      study: _actualMinutes(data, now, blocks, Category.study),
                      exercise: _actualMinutes(
                        data,
                        now,
                        blocks,
                        Category.exercise,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 累计数按「实际分类」算：纠偏过的段落要算到纠偏后的类里，
  /// 否则「我实际在做…」点了以后数字不动，等于没采到数据。
  static int _actualMinutes(
    AppData data,
    DateTime now,
    List<DayBlock> blocks,
    Category target,
  ) {
    final key = TimeMath.dateKey(now);
    var sum = 0;
    for (final b in blocks) {
      final cat =
          ActualRecords.overrideOf(data.records, key, b.start) ?? b.category;
      if (cat == target) sum += b.duration;
    }
    return sum;
  }
}

/// 默认窗口下保持设计稿的 336；窗口被拉高才跟着长，最多 560。
/// 最大化时环还缩在中间会显得整屏是空的，但也不该无限放大。
double _ringDiameter(double bodyHeight) {
  const base = 336.0;
  const max = 560.0;
  final room = bodyHeight - 10 - 46;
  return room <= base ? base : room.clamp(base, max);
}

/// UI 稿的紧凑时长：120 → `2h`，90 → `1h30`，45 → `45m`。
String compactDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- 图例

class _Legend extends StatelessWidget {
  const _Legend({required this.blocks, required this.unplanned});

  final List<DayBlock> blocks;
  final int unplanned;

  @override
  Widget build(BuildContext context) {
    final byCat = <Category, int>{};
    for (final b in blocks) {
      byCat[b.category] = (byCat[b.category] ?? 0) + b.duration;
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) {
        final byMinutes = b.value.compareTo(a.value);
        // 时长相同时按枚举顺序，保证「睡眠 8h」永远排在「工作 8h」前面，
        // 和 UI 稿一致；Dart 的 List.sort 不稳定，不写这个会来回跳。
        return byMinutes != 0 ? byMinutes : a.key.index.compareTo(b.key.index);
      });

    final items = <({String label, Color color, int minutes})>[
      for (final e in entries)
        (label: e.key.shortLabel, color: Palette.of(e.key), minutes: e.value),
      if (unplanned > 0)
        (label: '未安排', color: Palette.track, minutes: unplanned),
    ];

    // 四列两行。固定列宽，时长/百分比才不会左右跳动；
    // 窗口窄到放不下四列时自动折行，而不是把最后一项挤出边界。
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 5,
      children: [
        for (final item in items)
          SizedBox(width: 132, child: _LegendItem(item: item)),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.item});

  final ({String label, Color color, int minutes}) item;

  @override
  Widget build(BuildContext context) {
    final v = item.minutes;
    final hours = (v / 60).toStringAsFixed(v % 60 == 0 ? 0 : 1);
    final pct = (v / TimeMath.minutesPerDay * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LegendDot(color: item.color, size: 8),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            item.label,
            style: TypeScale.labelSmall.copyWith(
              fontSize: 10.5,
              color: Palette.muted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${hours}h · $pct%',
          style: TypeScale.labelSmall.copyWith(
            fontSize: 10.5,
            color: Palette.faint,
            fontFeatures: TypeScale.tabular,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 现在

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.blocks,
    required this.nowMinute,
    this.actual,
    this.onOverride,
  });

  final List<DayBlock> blocks;
  final int nowMinute;
  final Category? actual;
  final VoidCallback? onOverride;

  @override
  Widget build(BuildContext context) {
    final cur = TimeMath.blockAt(blocks, nowMinute);
    final color = cur == null ? Palette.track : Palette.of(cur.category);

    // 跨零点的块（睡眠）里，"现在"是凌晨而块的起点是昨晚 23:00，
    // 所以要把当前时间搬到同一根轴上再减，否则会算出还剩 1740 分钟。
    final nowExt = cur == null
        ? nowMinute
        : (nowMinute < cur.start
              ? nowMinute + TimeMath.minutesPerDay
              : nowMinute);
    final elapsed = cur == null
        ? 0
        : (nowExt - cur.start).clamp(0, cur.duration);
    final progress = cur == null || cur.duration == 0
        ? 0.0
        : (elapsed / cur.duration).clamp(0.0, 1.0);
    final left = cur == null ? 0 : (cur.end - nowExt).clamp(0, cur.duration);

    final sub = cur == null
        ? '这段时间空着 — 切到编辑模式可以安排'
        : '${cur.category.label} · ${TimeMath.formatHm(cur.start)}–'
              '${TimeMath.formatHm(cur.end)} · 还剩 ${compactDuration(left)}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('现在该做什么', style: TypeScale.cardLabel),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  cur?.name ?? '未安排',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.hero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            sub,
            style: TypeScale.label.copyWith(fontFeatures: TypeScale.tabular),
          ),
          const SizedBox(height: 12),
          _Meter(progress: progress, color: color),
          const SizedBox(height: 10),
          Row(
            children: [
              if (actual != null) ...[
                LegendDot(color: Palette.of(actual!), size: 7),
                const SizedBox(width: 6),
                Text('实际：${actual!.label}', style: TypeScale.labelSmall),
              ],
              const Spacer(),
              if (onOverride != null)
                _SmallAction(label: '我实际在做…', onTap: onOverride!),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一行小文字按钮。不抢视觉：没有底色、没有边框，只有 hover 时变亮。
class _SmallAction extends StatefulWidget {
  const _SmallAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_SmallAction> createState() => _SmallActionState();
}

class _SmallActionState extends State<_SmallAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TypeScale.labelSmall.copyWith(
            color: _hover ? Palette.text : Palette.faint,
          ),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: Palette.track),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 接着是

class _NextCard extends StatelessWidget {
  const _NextCard({required this.blocks, required this.nowMinute});

  final List<DayBlock> blocks;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final next = TimeMath.nextAfter(blocks, nowMinute);
    if (next == null) return const SizedBox.shrink();

    var delta = next.start - nowMinute;
    if (delta <= 0) delta += TimeMath.minutesPerDay;

    return AppCard(
      color: Palette.panel2,
      padding: const EdgeInsets.fromLTRB(17, 12, 17, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('接着是', style: TypeScale.cardLabel),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                TimeMath.formatHm(next.start),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Palette.muted,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  next.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Palette.text,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '还有 ${compactDuration(delta)}',
                style: TypeScale.labelSmall.copyWith(
                  color: Palette.ghost,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 两个累计

class _GoalsRow extends StatelessWidget {
  const _GoalsRow({required this.study, required this.exercise});

  final int study;
  final int exercise;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Goal(label: '今天学习', minutes: study),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _Goal(label: '今天锻炼', minutes: exercise),
        ),
      ],
    );
  }
}

class _Goal extends StatelessWidget {
  const _Goal({required this.label, required this.minutes});

  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Palette.panel2,
      radius: Radii.smallCard,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TypeScale.labelSmall.copyWith(color: Palette.faint),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$minutes',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: Palette.text,
                  fontFeatures: TypeScale.tabular,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '分钟',
                style: TypeScale.labelSmall.copyWith(color: Palette.faint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
