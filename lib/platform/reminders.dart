import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/reminder_slot.dart';

/// 系统提醒通道。
///
/// 桌面端**故意不实现**：Windows 版的设计是「常驻托盘 + 168px 悬浮环」，
/// 下一个动作一直在屏幕角上，不靠弹窗把人叫回来。所以 [instance] 默认是
/// [NoopReminders]，只有 Android 入口才换成真实现 —— Windows 构建与 widget
/// 测试都不会碰到平台通道。
abstract interface class Reminders {
  static Reminders instance = const NoopReminders();

  /// 幂等初始化。失败不应挡住启动，调用方自己 try。
  Future<void> init();

  /// 当前系统是否放行。`ready` 为 false 时提醒可能不响或迟到。
  Future<ReminderAccess> check();

  /// 申请通知权限与精确闹钟权限。Android 13+ 会弹系统授权框。
  Future<ReminderAccess> request();

  /// 用给定清单整体替换已排程提醒（先清空再排）。
  Future<void> sync(List<ReminderSlot> slots);

  /// 清空全部已排程提醒（关闭开关、或数据被清空时）。
  Future<void> cancelAll();
}

/// 通知权限 + 精确闹钟权限。两个是独立的系统开关，缺一个都会掉链子：
/// 没有通知权限 = 一条都不显示；没有精确闹钟 = 到点可能晚几分钟。
class ReminderAccess {
  const ReminderAccess({required this.notifications, required this.exact});

  final bool notifications;
  final bool exact;

  bool get ready => notifications && exact;

  static const granted = ReminderAccess(notifications: true, exact: true);
}

/// 什么都不做的实现：Windows 与测试环境走这条。
class NoopReminders implements Reminders {
  const NoopReminders();

  @override
  Future<void> init() async {}

  @override
  Future<ReminderAccess> check() async => ReminderAccess.granted;

  @override
  Future<ReminderAccess> request() async => ReminderAccess.granted;

  @override
  Future<void> sync(List<ReminderSlot> slots) async {}

  @override
  Future<void> cancelAll() async {}
}

/// Android 实现：走自己写的通道（`MainActivity` 里的 MethodChannel）。
///
/// 为什么不用现成插件：`flutter_local_notifications` 17.x 把 Gradle 钉在
/// AGP 7.3，和本仓库的 Gradle 9 冲突；23.x 的 Windows 实现又依赖 ATL，
/// 让桌面构建直接编不过。真正需要的只有 AlarmManager + Notification，
/// 自己写两百行 Kotlin 反而把双平台都保住了。
class LocalNotificationReminders implements Reminders {
  const LocalNotificationReminders();

  static const MethodChannel _channel = MethodChannel('routine_reminder/reminders');

  @override
  Future<void> init() async {
    // 原生侧不需要初始化动作，通道调用时自会建好通知渠道。
  }

  @override
  Future<ReminderAccess> check() async => _parse(await _invoke('check'));

  @override
  Future<ReminderAccess> request() async => _parse(await _invoke('request'));

  @override
  Future<void> sync(List<ReminderSlot> slots) async {
    await _invoke('sync', {
      'slots': [
        for (final slot in slots)
          {
            // 绝对时刻：本地时间转 epoch 毫秒，跨时区/夏令时都不会偏。
            'at': slot.at.millisecondsSinceEpoch,
            'title': slot.title,
            'body': slot.body,
          },
      ],
    });
  }

  @override
  Future<void> cancelAll() async {
    await _invoke('cancelAll');
  }

  Future<Object?> _invoke(String method, [Object? args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 通道不可用时按「放行」处理：宁可界面不弹警告，也不要因为读不到状态
  /// 就把开关一律显示成红的。
  ReminderAccess _parse(Object? raw) {
    if (raw is Map) {
      return ReminderAccess(
        notifications: raw['notifications'] as bool? ?? true,
        exact: raw['exact'] as bool? ?? false,
      );
    }
    return ReminderAccess.granted;
  }
}
