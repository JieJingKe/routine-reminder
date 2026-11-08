package com.jason.routine_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 闹钟到点：只负责把标题与正文取出来交给 [ReminderScheduler.show]。 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val id = intent.getIntExtra(EXTRA_ID, 1)
        ReminderScheduler.show(context, id, title, body)
    }

    companion object {
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }
}
