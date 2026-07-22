package com.sshai.agent.ssh_ai_agent

import android.app.Application
import android.util.Log

class SshAiApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Pre-start backend + sticky FGS watchdog
        Thread {
            try {
                BackendRuntime.ensureStarted(this)
            } catch (e: Exception) {
                Log.e("SshAiBackend", "Application pre-start failed: ${e.message}", e)
            }
            try {
                BackendService.start(this)
            } catch (e: Exception) {
                Log.e("SshAiBackend", "FGS start failed: ${e.message}", e)
            }
        }.apply {
            name = "backend-prestart"
            isDaemon = true
            start()
        }
    }
}
