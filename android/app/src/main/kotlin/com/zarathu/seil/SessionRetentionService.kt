package com.zarathu.seil

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class SessionRetentionService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val durationSeconds = intent?.getIntExtra(EXTRA_DURATION_SECONDS, 600) ?: 600
                val activeSessions = intent?.getIntExtra(EXTRA_ACTIVE_SESSIONS, 0) ?: 0
                startForegroundCompat(buildNotification(durationSeconds, activeSessions))
                handler.removeCallbacks(stopRunnable)
                handler.postDelayed(stopRunnable, durationSeconds.coerceAtLeast(1) * 1000L)
                return START_NOT_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(durationSeconds: Int, activeSessions: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, SessionRetentionService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val minutes = (durationSeconds + 59) / 60
        val sessionLabel = if (activeSessions == 1) "1 session" else "$activeSessions sessions"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_seil_notification)
            .setContentTitle("Seil session active")
            .setContentText("Keeping $sessionLabel alive for up to $minutes min.")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Session retention",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps active SSH sessions available briefly in the background."
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.zarathu.seil.session_retention.START"
        const val ACTION_STOP = "com.zarathu.seil.session_retention.STOP"
        const val EXTRA_DURATION_SECONDS = "durationSeconds"
        const val EXTRA_ACTIVE_SESSIONS = "activeSessions"
        private const val CHANNEL_ID = "session_retention"
        private const val NOTIFICATION_ID = 4101
    }
}
