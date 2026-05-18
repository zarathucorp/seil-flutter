package com.zarathu.seil

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        terminalNotificationsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zarathu.seil/terminal_notifications",
        )
        terminalNotificationsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "consumeLaunchTarget" -> {
                    result.success(consumeTerminalNotificationLaunchTarget())
                }
                "show" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 4201
                    val title = call.argument<String>("title") ?: "Seil"
                    val body = call.argument<String>("body") ?: title
                    val connectionFingerprint =
                        call.argument<String>("connectionFingerprint") ?: ""
                    val tmuxSessionName = call.argument<String>("tmuxSessionName") ?: ""
                    showTerminalNotification(
                        notificationId,
                        title,
                        body,
                        connectionFingerprint,
                        tmuxSessionName,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        handleTerminalNotificationIntent(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zarathu.seil/external_file",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> openExternalFile(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTerminalNotificationIntent(intent)
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

    private fun showTerminalNotification(
        notificationId: Int,
        title: String,
        body: String,
        connectionFingerprint: String,
        tmuxSessionName: String,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureTerminalNotificationChannel()
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_TERMINAL_NOTIFICATION
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_CONNECTION_FINGERPRINT, connectionFingerprint)
            putExtra(EXTRA_TMUX_SESSION_NAME, tmuxSessionName)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
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
            .addAction(terminalNotificationAction(notificationId, "1", ACTION_KEY_ONE, connectionFingerprint, tmuxSessionName))
            .addAction(terminalNotificationAction(notificationId, "2", ACTION_KEY_TWO, connectionFingerprint, tmuxSessionName))
            .addAction(terminalNotificationAction(notificationId, "Esc", ACTION_KEY_ESCAPE, connectionFingerprint, tmuxSessionName))
            .setAutoCancel(true)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(notificationId, notification)
    }

    private fun terminalNotificationAction(
        notificationId: Int,
        label: String,
        actionKey: String,
        connectionFingerprint: String,
        tmuxSessionName: String,
    ): Notification.Action {
        val requestCode = notificationId * 10 + when (actionKey) {
            ACTION_KEY_ONE -> 1
            ACTION_KEY_TWO -> 2
            ACTION_KEY_ESCAPE -> 3
            else -> 0
        }
        val intent = Intent(this, TerminalNotificationActionReceiver::class.java).apply {
            action = ACTION_TERMINAL_NOTIFICATION_ACTION
            putExtra(EXTRA_CONNECTION_FINGERPRINT, connectionFingerprint)
            putExtra(EXTRA_TMUX_SESSION_NAME, tmuxSessionName)
            putExtra(EXTRA_TERMINAL_ACTION, actionKey)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(
            R.drawable.ic_seil_notification,
            label,
            pendingIntent,
        ).build()
    }

    private fun handleTerminalNotificationIntent(intent: Intent?) {
        if (intent?.action != ACTION_TERMINAL_NOTIFICATION) {
            return
        }
        val connectionFingerprint =
            intent.getStringExtra(EXTRA_CONNECTION_FINGERPRINT)?.trim().orEmpty()
        val tmuxSessionName =
            intent.getStringExtra(EXTRA_TMUX_SESSION_NAME)?.trim().orEmpty()
        if (connectionFingerprint.isEmpty() || tmuxSessionName.isEmpty()) {
            return
        }
        val terminalAction = intent.getStringExtra(EXTRA_TERMINAL_ACTION)?.trim().orEmpty()
        dispatchTerminalNotificationTarget(connectionFingerprint, tmuxSessionName, terminalAction)
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

    private fun openExternalFile(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "File path is empty.", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "File does not exist.", null)
            return
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val mimeType = mimeTypeFor(file) ?: "*/*"
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addCategory(Intent.CATEGORY_DEFAULT)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(contentResolver, file.name, uri)
        }
        val chooser = Intent.createChooser(viewIntent, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(contentResolver, file.name, uri)
        }
        try {
            startActivity(chooser)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("no_viewer", "No app can open this file.", null)
        } catch (error: Exception) {
            result.error("open_failed", error.message, null)
        }
    }

    private fun mimeTypeFor(file: File): String? {
        val extension = file.extension.lowercase()
        if (extension.isBlank()) {
            return null
        }
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 5101
        private const val TERMINAL_NOTIFICATION_CHANNEL_ID = "terminal_attention"
        const val ACTION_TERMINAL_NOTIFICATION =
            "com.zarathu.seil.action.TERMINAL_NOTIFICATION"
        const val ACTION_TERMINAL_NOTIFICATION_ACTION =
            "com.zarathu.seil.action.TERMINAL_NOTIFICATION_ACTION"
        const val ACTION_KEY_ONE = "one"
        const val ACTION_KEY_TWO = "two"
        const val ACTION_KEY_ESCAPE = "escape"
        const val EXTRA_CONNECTION_FINGERPRINT = "connectionFingerprint"
        const val EXTRA_TMUX_SESSION_NAME = "tmuxSessionName"
        const val EXTRA_TERMINAL_ACTION = "terminalAction"
        const val EXTRA_NOTIFICATION_ID = "notificationId"

        private var terminalNotificationsChannel: MethodChannel? = null
        private var pendingTerminalNotificationLaunchTarget: HashMap<String, String>? = null

        fun consumeTerminalNotificationLaunchTarget(): HashMap<String, String>? {
            val target = pendingTerminalNotificationLaunchTarget
            pendingTerminalNotificationLaunchTarget = null
            return target
        }

        fun dispatchTerminalNotificationTarget(
            connectionFingerprint: String,
            tmuxSessionName: String,
            terminalAction: String = "",
        ) {
            if (connectionFingerprint.isBlank() || tmuxSessionName.isBlank()) {
                return
            }
            val target = hashMapOf(
                "connectionFingerprint" to connectionFingerprint.trim(),
                "tmuxSessionName" to tmuxSessionName.trim(),
            )
            if (terminalAction.isNotBlank()) {
                target["action"] = terminalAction.trim()
            }
            pendingTerminalNotificationLaunchTarget = target
            terminalNotificationsChannel?.invokeMethod("notificationTapped", target)
        }
    }
}
