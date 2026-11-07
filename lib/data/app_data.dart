import '../domain/calendar_rules.dart';
import '../domain/day_block.dart';
import '../domain/day_mode.dart';
import '../domain/plan.dart';
import '../domain/reminder.dart';
import 'seed_data.dart';

/// 某一天用的是哪张计划表，以及当时的来源。
///
/// 每天第一次启动时写一条。历史统计一律读快照，不重新跑规则 ——
/// 否则你今天把重复规则从「每天」改成「按星期」，上个月的统计会凭空变化。
/// v2 起以 [planId] 为准；[mode] 只为兼容旧的「工作日 / 节假日」汇总文案。
class DaySnapshot {
  const DaySnapshot({
    required this.planId,
    required this.mode,
    required this.source,
    this.autoPlanId,
    this.overriddenAt,
  });

  final String planId;
  final DayMode mode;
  final String source;

  /// 若这天被手动指派过，记下「按规则本来会用哪张表」和改判时刻。
  /// 这两项只用于界面解释，不参与判定 —— 判定永远读 [planId]。
  final String? autoPlanId;
  final String? overriddenAt;

  bool get isOverridden => overriddenAt != null;

  factory DaySnapshot.fromJson(Map<String, dynamic> json) {
    final mode = DayMode.tryFromKey(json['mode']) ?? DayMode.workday;
    final raw = json['planId'];
    return DaySnapshot(
      planId: (raw is String && raw.isNotEmpty)
          ? raw
          : AppData.defaultPlanId(mode),
      mode: mode,
      source: json['source'] as String? ?? '',
      autoPlanId: json['autoPlanId'] as String?,
      overriddenAt: json['overriddenAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'mode': mode.key,
    'source': source,
    if (autoPlanId != null) 'autoPlanId': autoPlanId,
    if (overriddenAt != null) 'overriddenAt': overriddenAt,
  };
}

class FloatWindowPrefs {
  const FloatWindowPrefs({this.enabled = true, this.x, this.y});

  final bool enabled;

  /// 上次的窗口位置。null 表示还没被用户拖过，用默认位置。
  final double? x;
  final double? y;

  FloatWindowPrefs copyWith({bool? enabled, double? x, double? y}) =>
      FloatWindowPrefs(
        enabled: enabled ?? this.enabled,
        x: x ?? this.x,
        y: y ?? this.y,
      );

  factory FloatWindowPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FloatWindowPrefs();
    return FloatWindowPrefs(
      enabled: json['enabled'] as bool? ?? true,
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };
}

class UiPrefs {
  const UiPrefs({
    this.floatWindow = const FloatWindowPrefs(),
    this.openAtLogin = false,
    this.theme,
  });

  final FloatWindowPrefs floatWindow;
  final bool openAtLogin;

  /// 主题偏好：`light` / `dark`。null = 还没选过，跟随系统亮度。
  /// 存的是用户**显式选过的**结果，不是当前系统状态 —— 否则下次开机
  /// 系统还没来得及报亮度就会先闪一下错的颜色。
  final String? theme;

  UiPrefs copyWith({
    FloatWindowPrefs? floatWindow,
    bool? openAtLogin,
    String? theme,
  }) => UiPrefs(
    floatWindow: floatWindow ?? this.floatWindow,
    openAtLogin: openAtLogin ?? this.openAtLogin,
    theme: theme ?? this.theme,
  );

  factory UiPrefs.fromJson(Map<String, dynamic>? json) => UiPrefs(
    floatWindow: FloatWindowPrefs.fromJson(
      json?['floatWindow'] as Map<String, dynamic>?,
    ),
    openAtLogin: json?['openAtLogin'] as bool? ?? false,
    theme: (json?['theme'] == 'light' || json?['theme'] == 'dark')
        ? json!['theme'] as String
        : null,
  );

  Map<String, dynamic> toJson() => {
    'floatWindow': floatWindow.toJson(),
    'openAtLogin': openAtLogin,
    if (theme != null) 'theme': theme,
  };
}

/// 整个数据文件。
///
/// v2 起 [plans] 是唯一真相源：「工作日 / 节假日」只是列表里前两张表，
/// 不再是写死的两个枚举键。[rules] 保留为**兼容镜像** —— 旧周期弹窗和
/// 顶栏「工作日/节假日」切换仍写它，[withRules] 会把改动同步回 plans，
/// 保证主流程 [forDate] 与镜像不会出现两套结论。
class AppData {
  AppData({
    required this.plans,
    required this.dayOverrides,
    required this.rules,
    required this.daySnapshots,
    required this.ui,
    required this.records,
    this.schemaVersion = schemaV2,
  });

  static const int schemaV1 = 1;
  static const int schemaV2 = 2;

  /// 计划表列表。**顺序 = 同日冲突优先级**（first match wins）。
  final List<Plan> plans;

  /// 单日例外：`YYYY-MM-DD → planId`。优先级高于一切重复规则。
  final Map<String, String> dayOverrides;

  /// v1 全局规则栈的兼容镜像，不再是主流程的判定依据。
  final CalendarRules rules;

  final Map<String, DaySnapshot> daySnapshots;

  final UiPrefs ui;

  /// 执行记录。V1 只做透传保存，不消费也不改写 ——
  /// 现在没有"实际做了什么"的采集入口，凭空生成记录就是造假。
  final Map<String, dynamic> records;

  final int schemaVersion;

  static String defaultPlanId(DayMode mode) =>
      mode == DayMode.holiday ? PlanDefaults.holidayId : PlanDefaults.workdayId;

  Plan? planById(String id) {
    for (final p in plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  String? planIdForMode(DayMode mode) {
    for (final p in plans) {
      if (p.legacyMode == mode) return p.id;
    }
    return null;
  }

  // ------------------------------------------------------------ 兼容旧入口

  /// 旧代码按 DayMode 取块。新建的表没有 legacyMode，不会被这里返回。
  List<DayBlock> blocksForMode(DayMode mode) {
    final id = planIdForMode(mode);
    return id == null ? const [] : (planById(id)?.blocks ?? const []);
  }

  List<Reminder> remindersForMode(DayMode mode) {
    final id = planIdForMode(mode);
    return id == null ? const [] : (planById(id)?.reminders ?? const []);
  }

  Map<DayMode, List<DayBlock>> get schedules => {
    for (final mode in DayMode.values) mode: blocksForMode(mode),
  };

  Map<DayMode, List<Reminder>> get reminders => {
    for (final mode in DayMode.values) mode: remindersForMode(mode),
  };

  // ------------------------------------------------------------ 写入口

  AppData _copy({
    List<Plan>? plans,
    Map<String, String>? dayOverrides,
    CalendarRules? rules,
    Map<String, DaySnapshot>? daySnapshots,
    UiPrefs? ui,
    Map<String, dynamic>? records,
  }) => AppData(
    plans: plans ?? this.plans,
    dayOverrides: dayOverrides ?? this.dayOverrides,
    rules: rules ?? this.rules,
    daySnapshots: daySnapshots ?? this.daySnapshots,
    ui: ui ?? this.ui,
    records: records ?? this.records,
    schemaVersion: schemaVersion,
  );

  /// 编辑后产出一份新 AppData。字段全是 final，避免界面层拿到半改的引用。
  /// 编辑只改**指定 id 的那张表**，其余表原样保留。
  AppData withPlanBlocks(String planId, List<DayBlock> blocks) => _copy(
    plans: [
      for (final p in plans) p.id == planId ? p.copyWith(blocks: blocks) : p,
    ],
  );

  /// 旧入口：按 legacyMode 找到对应表。找不到就退回固定 id。
  AppData withSchedule(DayMode mode, List<DayBlock> blocks) =>
      withPlanBlocks(planIdForMode(mode) ?? defaultPlanId(mode), blocks);

  /// #9 管理界面用：整列表替换（新建 / 重命名 / 排序 / 删除 / 改重复规则）。
  /// 删表时顺手清掉指向它的单日指派，否则 `forDate` 会命中不到任何表，
  /// 静默退回兜底第一张 —— 用户还以为那天是自动判定的。
  AppData withPlans(List<Plan> next) => _copy(
    plans: next,
    dayOverrides: {
      for (final e in dayOverrides.entries)
        if (next.any((p) => p.id == e.value)) e.key: e.value,
    },
  );

  /// 单日例外。传 null = 删除这条例外、回到重复规则。
  AppData withDayOverride(String dateKey, String? planId) {
    final next = <String, String>{...dayOverrides};
    if (planId == null) {
      next.remove(dateKey);
    } else {
      next[dateKey] = planId;
    }
    return _copy(dayOverrides: next);
  }

  /// 单日指派（顶栏切表 / 日历点选共用）的唯一入口。
  ///
  /// 一次做完三件事，杜绝「界面换了、汇总还按启动时那张快照算」：
  /// ① 写 / 删 dayOverrides；② 按新结果**覆盖当天快照**（中途改判也
  /// 立即反映到 L3）；③ 记下自动判定结果与改判时刻，供界面解释来源。
  /// 整天按改判后的表算，不引入半天分段。
  AppData assignDay(String dateKey, String? planId, {String? at}) {
    final overrides = <String, String>{...dayOverrides};
    if (planId == null) {
      overrides.remove(dateKey);
    } else {
      overrides[dateKey] = planId;
    }
    final base = _copy(dayOverrides: overrides);
    final date = DateTime.parse(dateKey);
    final auto = _copy(
      dayOverrides: <String, String>{...overrides}..remove(dateKey),
    ).forDate(date);
    final resolved = base.forDate(date);
    return base.withSnapshot(
      dateKey,
      DaySnapshot(
        planId: resolved.planId,
        mode: resolved.mode,
        source: planId == null ? resolved.source : '手动改判',
        autoPlanId: auto.planId,
        overriddenAt: planId == null ? null : (at ?? ''),
      ),
    );
  }

  AppData withRecords(Map<String, dynamic> next) => _copy(records: next);

  /// 只改界面偏好（主题、悬浮窗、开机自启），不碰作息数据。
  AppData withUi(UiPrefs next) => _copy(ui: next);

  /// 旧周期弹窗 / 顶栏「工作日 / 节假日」仍走这里。
  ///
  /// 镜像更新后必须把结果同步回 plans，否则 [forDate] 会继续按旧规则解析，
  /// 出现「界面说今天节假日、环上却是工作日」这种两套结论。
  /// 用户新建的表（legacyMode == null）不受影响。
  AppData withRules(CalendarRules next) {
    final overrides = <String, String>{...dayOverrides};
    // 「切回星期几默认」= 删掉例外；先把旧镜像里已消失的日期清掉。
    for (final key in rules.overrides.keys) {
      if (!next.overrides.containsKey(key)) overrides.remove(key);
    }
    next.overrides.forEach((key, mode) {
      overrides[key] = planIdForMode(mode) ?? defaultPlanId(mode);
    });

    return _copy(
      plans: [
        for (final p in plans)
          p.legacyMode == null ? p : _syncLegacyPlan(p, next),
      ],
      dayOverrides: overrides,
      rules: next,
    );
  }

  /// 每天启动时写一条快照，标记「这天有数据」。
  /// L3 的周/月视图靠它区分「无数据」和「真的是 0 分钟」。
  AppData withSnapshot(String key, DaySnapshot snapshot) =>
      _copy(daySnapshots: {...daySnapshots, key: snapshot});

  /// 恢复内置表。只重置 plans，规则镜像一并回默认，历史与偏好都留着 ——
  /// 「恢复默认」是恢复作息表，不是清空用户的历史。
  AppData restoredDefaults() => _copy(
    plans: SeedData.build().plans,
    rules: CalendarRules(),
    dayOverrides: const <String, String>{},
  );

  // ------------------------------------------------------------ 解析

  /// 按优先级解析某天该用哪张表：
  /// 单日例外 → 各表特殊日期 → 各表常规重复（列表顺序）→ 兜底第一张。
  ({
    String planId,
    String planName,
    DayMode mode,
    String source,
    String label,
    List<DayBlock> blocks,
    List<Reminder> reminders,
  })
  forDate(DateTime date) {
    final key = CalendarRules.dateKey(date);
    Plan? chosen;
    var source = '';

    final overrideId = dayOverrides[key];
    if (overrideId != null) {
      chosen = planById(overrideId);
      if (chosen != null) source = '单日例外';
    }
    if (chosen == null) {
      for (final p in plans) {
        if (p.repeat.matchesSpecial(date)) {
          chosen = p;
          source = '特殊日期';
          break;
        }
      }
    }
    if (chosen == null) {
      for (final p in plans) {
        if (p.repeat.matchesRegular(date)) {
          chosen = p;
          source = p.repeat.sourceLabel;
          break;
        }
      }
    }
    if (chosen == null && plans.isNotEmpty) {
      chosen = plans.first;
      source = '默认计划表';
    }
    if (chosen == null) {
      return (
        planId: '',
        planName: '—',
        mode: DayMode.workday,
        source: '无计划表',
        label: '—',
        blocks: const <DayBlock>[],
        reminders: const <Reminder>[],
      );
    }
    return (
      planId: chosen.id,
      planName: chosen.name,
      mode: chosen.displayMode,
      source: source,
      label: '${chosen.name}（$source）',
      blocks: chosen.blocks,
      reminders: chosen.reminders,
    );
  }

  // ------------------------------------------------------------ 序列化

  factory AppData.fromJson(Map<String, dynamic> json) {
    final rawPlans = json['plans'];
    if (rawPlans is List && rawPlans.isNotEmpty) {
      final parsed = rawPlans
          .whereType<Map>()
          .map((e) => Plan.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (parsed.isEmpty) return _migrateV1(json);
      return AppData(
        plans: parsed,
        dayOverrides: _parseOverrides(json['dayOverrides']),
        rules: CalendarRules.fromJson(json['rules'] as Map<String, dynamic>?),
        daySnapshots: _parseSnapshots(json['daySnapshots']),
        ui: UiPrefs.fromJson(json['ui'] as Map<String, dynamic>?),
        records: (json['records'] is Map)
            ? Map<String, dynamic>.from(json['records'] as Map)
            : <String, dynamic>{},
        schemaVersion: json['schemaVersion'] as int? ?? schemaV2,
      );
    }
    // 没有 plans = 11-07 之前的 v1 文件，触发迁移。
    return _migrateV1(json);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'plans': plans.map((p) => p.toJson()).toList(),
    // 键排序后落盘，保证 toJson → fromJson → toJson 幂等。
    'dayOverrides': {
      for (final k in (dayOverrides.keys.toList()..sort())) k: dayOverrides[k],
    },
    'rules': rules.toJson(),
    'daySnapshots': {
      for (final k in (daySnapshots.keys.toList()..sort()))
        k: daySnapshots[k]!.toJson(),
    },
    'ui': ui.toJson(),
    'records': records,
  };
}

// ---------------------------------------------------------------- 解析辅助

Map<String, String> _parseOverrides(Object? raw) {
  final out = <String, String>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v is String) out[k.toString()] = v;
    });
  }
  return out;
}

Map<String, DaySnapshot> _parseSnapshots(Object? raw) {
  final out = <String, DaySnapshot>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v is Map) {
        out[k.toString()] = DaySnapshot.fromJson(Map<String, dynamic>.from(v));
      }
    });
  }
  return out;
}

Map<DayMode, List<DayBlock>> _parseSchedules(Object? raw) {
  final out = <DayMode, List<DayBlock>>{
    DayMode.workday: <DayBlock>[],
    DayMode.holiday: <DayBlock>[],
  };
  if (raw is Map) {
    for (final mode in DayMode.values) {
      final list = raw[mode.key];
      if (list is List) {
        out[mode] = list
            .whereType<Map>()
            .map((e) => DayBlock.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
  }
  return out;
}

Map<DayMode, List<Reminder>> _parseReminders(Object? raw) {
  final out = <DayMode, List<Reminder>>{
    DayMode.workday: <Reminder>[],
    DayMode.holiday: <Reminder>[],
  };
  if (raw is Map) {
    for (final mode in DayMode.values) {
      final list = raw[mode.key];
      if (list is List) {
        out[mode] = list
            .whereType<Map>()
            .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
  }
  return out;
}

/// 把 v1 的全局规则映射进一张 legacy 表的重复规则。
/// 迁移与 `withRules` 共用这一份，避免两处判定漂移。
Plan _syncLegacyPlan(Plan p, CalendarRules rules) {
  final isWorkday = p.legacyMode == DayMode.workday;
  final wd = <int>{};
  for (final e in rules.weekdayDefault.entries) {
    if (e.value == p.legacyMode) wd.add(e.key);
  }

  // 单休：旧 _cycleMode 对周日返回节假日、其余返回工作日，
  // 完全压过 weekdayDefault，所以直接用固定集合表达。
  if (rules.cycle.type == CycleType.singleDayOff) {
    return p.copyWith(
      repeat: p.repeat.copyWith(
        kind: RepeatKind.weekly,
        weekdays: isWorkday ? const {1, 2, 3, 4, 5, 6} : const {7},
        cycle: rules.cycle,
      ),
    );
  }

  // 大小周：旧 _cycleMode 对周六一定给确定答案（不看 weekdayDefault），
  // 所以两张表都要含周六，再靠 cycleBigWeek 分工。
  if (rules.cycle.type == CycleType.bigSmallWeek) {
    wd.add(DateTime.saturday);
    return p.copyWith(
      repeat: p.repeat.copyWith(
        kind: RepeatKind.cycle,
        weekdays: wd,
        cycle: rules.cycle,
        cycleBigWeek: isWorkday,
      ),
    );
  }

  return p.copyWith(
    repeat: p.repeat.copyWith(
      kind: RepeatKind.weekly,
      weekdays: wd,
      cycle: rules.cycle,
    ),
  );
}

/// v1 → v2：两套 Map 变成两张计划表，全局规则拆进各自的 repeat。
AppData _migrateV1(Map<String, dynamic> json) {
  final schedules = _parseSchedules(json['schedules']);
  final reminderMap = _parseReminders(json['reminders']);
  final rules = CalendarRules.fromJson(json['rules'] as Map<String, dynamic>?);

  Plan legacy(DayMode mode) {
    final base = Plan(
      id: AppData.defaultPlanId(mode),
      name: mode.label,
      blocks: schedules[mode] ?? const <DayBlock>[],
      reminders: reminderMap[mode] ?? const <Reminder>[],
      legacyMode: mode,
    );
    final synced = _syncLegacyPlan(base, rules);
    // 旧全局 specialDates 按目标表拆开，从此每张表自己维护、互不共享。
    final dates = <String>{};
    rules.specialDates.forEach((key, target) {
      if (target == mode) dates.add(key);
    });
    return synced.copyWith(repeat: synced.repeat.copyWith(dates: dates));
  }

  final plans = [legacy(DayMode.workday), legacy(DayMode.holiday)];

  final overrides = <String, String>{};
  rules.overrides.forEach((key, mode) {
    overrides[key] = AppData.defaultPlanId(mode);
  });

  return AppData(
    plans: plans,
    dayOverrides: overrides,
    rules: rules,
    daySnapshots: _parseSnapshots(json['daySnapshots']),
    ui: UiPrefs.fromJson(json['ui'] as Map<String, dynamic>?),
    records: (json['records'] is Map)
        ? Map<String, dynamic>.from(json['records'] as Map)
        : <String, dynamic>{},
    schemaVersion: AppData.schemaV2,
  );
}
