package com.zarathu.seil

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TerminalNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != MainActivity.ACTION_TERMINAL_NOTIFICATION_ACTION) {
            return
        }
        val connectionFingerprint =
            intent.getStringExtra(MainActivity.EXTRA_CONNECTION_FINGERPRINT)
                ?.trim()
                .orEmpty()
        val tmuxSessionName =
            intent.getStringExtra(MainActivity.EXTRA_TMUX_SESSION_NAME)
                ?.trim()
                .orEmpty()
        val terminalAction =
            intent.getStringExtra(MainActivity.EXTRA_TERMINAL_ACTION)
                ?.trim()
                .orEmpty()
        val notificationId = intent.getIntExtra(MainActivity.EXTRA_NOTIFICATION_ID, -1)
        if (notificationId >= 0) {
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(notificationId)
        }
        MainActivity.dispatchTerminalNotificationTarget(
            connectionFingerprint,
            tmuxSessionName,
            terminalAction,
        )
    }
}
