package com.sshai.agent.ssh_ai_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Sticky foreground service: keeps process priority up and restarts Go backend if it dies.
 */
class BackendService : Service() {
    private val exec: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Derive package-specific port before any isHealthy() check.
        BackendRuntime.resolvePort(applicationContext)
        createChannel()
        startForeground(NOTIF_ID, buildNotification("后端启动中 :${BackendRuntime.PORT}"))
        exec.scheduleWithFixedDelay({
            try {
                if (!BackendRuntime.isHealthy()) {
                    Log.w(TAG, "backend unhealthy, restarting")
                    BackendRuntime.ensureStarted(applicationContext)
                    updateNotification("后端已恢复 :${BackendRuntime.PORT}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "watchdog: ${e.message}")
                updateNotification("后端异常: ${e.message?.take(40) ?: ""}")
            }
        }, 3, 8, TimeUnit.SECONDS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        exec.execute {
            try {
                BackendRuntime.ensureStarted(applicationContext)
                updateNotification("后端运行中 :${BackendRuntime.PORT}")
            } catch (e: Exception) {
                Log.e(TAG, "start: ${e.message}")
                updateNotification("启动失败")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        exec.shutdownNow()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java)
        val ch = NotificationChannel(CHANNEL, "SSH AI 后端", NotificationManager.IMPORTANCE_LOW)
        ch.description = "保持本地 Go 运维后端存活"
        mgr?.createNotificationChannel(ch)
    }

    private fun buildNotification(text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return b.setContentTitle("SSH AI Agent")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val mgr = getSystemService(NotificationManager::class.java)
        mgr?.notify(NOTIF_ID, buildNotification(text))
    }

    companion object {
        private const val TAG = "BackendService"
        private const val CHANNEL = "ssh_ai_backend"
        private const val NOTIF_ID = 17890

        fun start(ctx: Context) {
            val i = Intent(ctx, BackendService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }
    }
}
