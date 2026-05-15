package com.zarathu.seil

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zarathu.seil/session_retention",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val durationSeconds = call.argument<Int>("durationSeconds") ?: 600
                    val activeSessions = call.argument<Int>("activeSessions") ?: 0
                    val intent = Intent(this, SessionRetentionService::class.java).apply {
                        action = SessionRetentionService.ACTION_START
                        putExtra(
                            SessionRetentionService.EXTRA_DURATION_SECONDS,
                            durationSeconds,
                        )
                        putExtra(
                            SessionRetentionService.EXTRA_ACTIVE_SESSIONS,
                            activeSessions,
                        )
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, SessionRetentionService::class.java).apply {
                        action = SessionRetentionService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zarathu.seil/terminal_notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "show" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 4201
                    val title = call.argument<String>("title") ?: "Seil"
                    val body = call.argument<String>("body") ?: title
                    showTerminalNotification(notificationId, title, body)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.success(false)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    private fun showTerminalNotification(notificationId: Int, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureTerminalNotificationChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, TERMINAL_NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_seil_notification)
            .setContentTitle(title)
            .setContentText(body.lineSequence().firstOrNull() ?: body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(notificationId, notification)
    }

    private fun ensureTerminalNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            TERMINAL_NOTIFICATION_CHANNEL_ID,
            "Terminal attention",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Notifies when terminal work completes or needs action."
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 5101
        private const val TERMINAL_NOTIFICATION_CHANNEL_ID = "terminal_attention"
    }
}
