package com.jason.routine_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 重启 / 应用升级后重排。
 *
 * AlarmManager 里排好的闹钟在关机后全部丢失，系统不会替你恢复；
 * 这是「装了提醒但重启后就不响了」最常见的原因。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_QUICKBOOT_POWERON -> ReminderScheduler.restore(context)
        }
    }

    companion object {
        /** 部分国产 ROM 用自己的开机广播，多接一个不吃亏。 */
        private const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
    }
}
