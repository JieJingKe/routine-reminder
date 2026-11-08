package com.jason.routine_reminder

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * 排程与通知的落地实现。
 *
 * 口径：Dart 侧把「接下来 7 天每段开始时该弹什么」算好，这里只管把绝对时刻
 * 交给 AlarmManager。日历判定不在这里重复一遍 —— 否则单日改判、特殊日期就
 * 会和看板出现两套结论。
 *
 * 排过的清单会同时写进 SharedPreferences：手机重启会把所有闹钟清掉，
 * [BootReceiver] 靠这份清单把它们重新登记回来。
 */
object ReminderScheduler {

    private const val PREFS = "routine_reminders"
    private const val KEY_SLOTS = "slots"
    private const val CHANNEL_ID = "routine_blocks"
    private const val CHANNEL_NAME = "到点提醒"
    private const val CHANNEL_DESCRIPTION = "每段作息开始时提醒一次"

    /** 整体替换：先撤掉旧的，再按新清单排。（清单为空 = 全部取消） */
    fun sync(context: Context, rawSlots: List<Any?>) {
        cancelAll(context)
        val now = System.currentTimeMillis()
        val slots = rawSlots.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val at = (map["at"] as? Number)?.toLong() ?: return@mapNotNull null
            val title = map["title"] as? String ?: return@mapNotNull null
            if (title.isBlank() || at <= now) return@mapNotNull null
            Slot(at, title, (map["body"] as? String).orEmpty())
        }
        if (slots.isEmpty()) return

        ensureChannel(context)
        writeSlots(context, slots)
        slots.forEachIndexed { index, slot -> schedule(context, index + 1, slot) }
    }

    /** 关掉开关 / 重排前清理：撤销所有闹钟、清掉已显示的通知、清空清单。 */
    fun cancelAll(context: Context) {
        val stored = readSlots(context)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (alarmManager != null) {
            stored.forEachIndexed { index, slot ->
                alarmManager.cancel(pendingIntent(context, index + 1, slot))
            }
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_SLOTS)
            .apply()
        context.getSystemService(NotificationManager::class.java)?.cancelAll()
    }

    /** 开机 / 应用升级后重新登记还没到点的那些。 */
    fun restore(context: Context) {
        val slots = readSlots(context).filter { it.at > System.currentTimeMillis() }
        if (slots.isEmpty()) return
        ensureChannel(context)
        slots.forEachIndexed { index, slot -> schedule(context, index + 1, slot) }
    }

    /** 闹钟到点 → 发通知。入口是 [ReminderReceiver]。 */
    fun show(context: Context, id: Int, title: String, body: String) {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val icon = context.applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.ic_dialog_info
        builder
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(icon)
            .setAutoCancel(true)
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        try {
            manager.notify(id, builder.build())
        } catch (_: SecurityException) {
            // 通知权限被撤销：静默失败，界面里的权限提示会告诉用户。
        }
    }

    private fun schedule(context: Context, id: Int, slot: Slot) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = pendingIntent(context, id, slot)
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        try {
            if (canExact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    slot.at,
                    intent,
                )
            } else {
                // 没有精确闹钟权限时退化成窗口闹钟：可能晚几分钟，但不会不响。
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.at, intent)
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.at, intent)
        }
    }

    private fun pendingIntent(context: Context, id: Int, slot: Slot): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(ReminderReceiver.EXTRA_ID, id)
            putExtra(ReminderReceiver.EXTRA_TITLE, slot.title)
            putExtra(ReminderReceiver.EXTRA_BODY, slot.body)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESCRIPTION
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun writeSlots(context: Context, slots: List<Slot>) {
        val array = JSONArray()
        slots.forEach { slot ->
            array.put(
                JSONObject()
                    .put("at", slot.at)
                    .put("title", slot.title)
                    .put("body", slot.body),
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SLOTS, array.toString())
            .apply()
    }

    private fun readSlots(context: Context): List<Slot> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SLOTS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                Slot(
                    item.optLong("at"),
                    item.optString("title"),
                    item.optString("body"),
                )
            }
        } catch (_: Exception) {
            // 清单损坏就当没有：宁可少一排提醒，也不要开机崩在解析上。
            emptyList()
        }
    }

    private data class Slot(val at: Long, val title: String, val body: String)
}
