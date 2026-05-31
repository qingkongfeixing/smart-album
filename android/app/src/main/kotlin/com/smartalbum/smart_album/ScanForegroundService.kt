package com.smartalbum.smart_album

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ScanForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "foreground_scan"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_NAME = "后台扫描"

        var instance: ScanForegroundService? = null

        // 缓存的进度，防止更新在 onStartCommand 之前到达
        private var pendingTitle: String? = null
        private var pendingBody: String? = null
        private var pendingProgress: Int = 0
        private var pendingMaxProgress: Int = 0

        fun updateProgress(
            context: Context,
            title: String,
            body: String,
            progress: Int,
            maxProgress: Int
        ) {
            instance?.applyProgress(title, body, progress, maxProgress) ?: run {
                pendingTitle = title
                pendingBody = body
                pendingProgress = progress
                pendingMaxProgress = maxProgress
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "相册扫描/云端解析后台进度"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title")
            ?: pendingTitle ?: "扫描中..."
        val body = intent?.getStringExtra("body")
            ?: pendingBody ?: "准备中..."
        val progress = intent?.getIntExtra("progress", 0)
            ?: pendingProgress
        val maxProgress = intent?.getIntExtra("maxProgress", 0)
            ?: pendingMaxProgress

        val notification = buildNotification(title, body, progress, maxProgress)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // 如果有比 intent extras 更新的缓冲进度，应用之
        pendingTitle?.let { t -> pendingBody?.let { b ->
            if (t != title || b != body) {
                applyProgress(t, b, pendingProgress, pendingMaxProgress)
            }
        }}
        pendingTitle = null
        pendingBody = null

        return START_STICKY
    }

    private fun buildNotification(
        title: String, body: String, progress: Int, maxProgress: Int
    ): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)

        if (maxProgress > 0) {
            builder.setProgress(maxProgress, progress, false)
        } else {
            builder.setProgress(0, 0, true) // 不确定进度
        }

        return builder.build()
    }

    internal fun applyProgress(
        title: String, body: String, progress: Int, maxProgress: Int
    ) {
        val notification = buildNotification(title, body, progress, maxProgress)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
