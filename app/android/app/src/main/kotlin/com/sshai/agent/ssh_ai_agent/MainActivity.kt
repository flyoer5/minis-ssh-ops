package com.sshai.agent.ssh_ai_agent

import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    private val channelName = "com.sshai.agent/backend"
    private val port = 17890
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processRef = AtomicReference<Process?>(null)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureStarted" -> {
                        executor.execute {
                            try {
                                val info = ensureBackendLocked()
                                mainHandler.post { result.success(info) }
                            } catch (e: Exception) {
                                Log.e(TAG, "ensureStarted failed", e)
                                mainHandler.post {
                                    result.error("BACKEND", e.message, null)
                                }
                            }
                        }
                    }
                    "stop" -> {
                        executor.execute {
                            stopBackend()
                            mainHandler.post { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Keep backend running for now across activity recreations;
        // only stop if process is finishing entirely.
        if (isFinishing) {
            // Do not kill on rotate; user may background app.
        }
        super.onDestroy()
    }

    private fun ensureBackendLocked(): Map<String, Any> {
        val dataDir = File(filesDir, "backend-data").apply { mkdirs() }
        val tokenFile = File(dataDir, "local.token")
        val token = if (tokenFile.exists() && tokenFile.length() > 8) {
            tokenFile.readText().trim()
        } else {
            UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "").take(16)
        }

        if (isHealthy()) {
            val existing = if (tokenFile.exists()) tokenFile.readText().trim() else token
            publishDebugToken(existing)
            return mapOf(
                "baseUrl" to "http://127.0.0.1:$port",
                "token" to existing,
                "port" to port,
                "alreadyRunning" to true,
            )
        }

        val bin = extractBinary()
        stopBackend()

        val pb = ProcessBuilder(bin.absolutePath).apply {
            directory(filesDir)
            redirectErrorStream(true)
            environment()["SSH_AI_DATA_DIR"] = dataDir.absolutePath
            environment()["SSH_AI_PORT"] = port.toString()
            environment()["SSH_AI_LOCAL_TOKEN"] = token
            // Restrict bind (server also enforces)
            environment()["HOME"] = filesDir.absolutePath
        }
        val proc = pb.start()
        processRef.set(proc)

        // Drain logs so pipe doesn't block
        Thread {
            try {
                BufferedReader(InputStreamReader(proc.inputStream)).use { br ->
                    var line: String?
                    while (br.readLine().also { line = it } != null) {
                        Log.i(TAG, "go: $line")
                    }
                }
            } catch (_: Exception) {
            }
        }.apply { isDaemon = true; name = "go-backend-log"; start() }

        val deadline = System.currentTimeMillis() + 8_000
        while (System.currentTimeMillis() < deadline) {
            if (!proc.isAlive) {
                throw IllegalStateException("backend process exited early (code=${proc.exitValue()})")
            }
            if (isHealthy()) {
                // Prefer token file written by server if present
                val finalTok = if (tokenFile.exists()) tokenFile.readText().trim() else token
                publishDebugToken(finalTok)
                return mapOf(
                    "baseUrl" to "http://127.0.0.1:$port",
                    "token" to finalTok,
                    "port" to port,
                    "alreadyRunning" to false,
                )
            }
            Thread.sleep(200)
        }
        throw IllegalStateException("backend health check timeout on port $port")
    }

    private fun extractBinary(): File {
        val outDir = File(filesDir, "bin").apply { mkdirs() }
        val out = File(outDir, "ssh-ai-agent")
        // Always refresh from assets so updates replace binary
        assets.open("go/ssh-ai-agent").use { input ->
            FileOutputStream(out).use { output -> input.copyTo(output) }
        }
        out.setReadable(true, true)
        out.setExecutable(true, true)
        out.setWritable(true, true)
        if (!out.canExecute()) {
            Runtime.getRuntime().exec(arrayOf("chmod", "700", out.absolutePath)).waitFor()
        }
        return out
    }

    private fun isHealthy(): Boolean {
        return try {
            val url = URL("http://127.0.0.1:$port/v1/health")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 500
                readTimeout = 500
                requestMethod = "GET"
            }
            conn.responseCode == 200
        } catch (_: Exception) {
            false
        }
    }

    private fun stopBackend() {
        processRef.getAndSet(null)?.destroy()
        // Best-effort kill by port listeners is hard; leave orphan if needed.
    }

    /** Debug builds: write token where adb shell can read (run-as often blocked on MIUI). */
    private fun publishDebugToken(token: String) {
        val debuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable || token.isEmpty()) return
        try {
            val ext = getExternalFilesDir(null) ?: return
            File(ext, "local.token").writeText(token)
            Log.i(TAG, "debug token published to ${ext.absolutePath}/local.token")
        } catch (e: Exception) {
            Log.w(TAG, "publishDebugToken failed", e)
        }
    }

    companion object {
        private const val TAG = "SshAiBackend"
    }
}
