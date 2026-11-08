package com.jason.routine_reminder

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 到点提醒的原生一侧。
 *
 * 只做四件事：查权限、要权限、按清单排闹钟、全部取消。**刻意不引第三方通知
 * 插件** —— 那些插件要么把 Gradle 钉在旧版本、要么 Windows 端要 ATL，
 * 而这里真正需要的只是 AlarmManager + Notification，两百行以内能写完，
 * 桌面构建完全不受影响。
 */
class MainActivity : FlutterActivity() {

    private val notificationsRequestCode = 4101

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "check" -> result.success(accessState())
                    "request" -> {
                        askForPermissions()
                        result.success(accessState())
                    }
                    "sync" -> {
                        val slots = call.argument<List<Any?>>("slots").orEmpty()
                        ReminderScheduler.sync(this, slots)
                        result.success(true)
                    }
                    "cancelAll" -> {
                        ReminderScheduler.cancelAll(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 通知开关与精确闹钟是两个独立的系统开关，必须分别查。 */
    private fun accessState(): Map<String, Boolean> {
        val notificationManager = getSystemService(NotificationManager::class.java)
        val notifications = notificationManager?.areNotificationsEnabled() ?: true
        val exact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
        } else {
            true
        }
        return mapOf("notifications" to notifications, "exact" to exact)
    }

    private fun askForPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationsRequestCode,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(AlarmManager::class.java)
            if (alarmManager != null && !alarmManager.canScheduleExactAlarms()) {
                try {
                    startActivity(
                        Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                } catch (_: Exception) {
                    // 个别 ROM 没有这个页面，退回到应用详情，不额外打扰用户。
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                }
            }
        }
    }

    companion object {
        const val CHANNEL = "routine_reminder/reminders"
    }
}
