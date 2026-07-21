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
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kick backend as early as possible (also done in Application).
        executor.execute {
            try {
                BackendRuntime.ensureStarted(applicationContext)
            } catch (e: Exception) {
                Log.e(TAG, "early start failed", e)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureStarted" -> {
                        executor.execute {
                            try {
                                val info = BackendRuntime.ensureStarted(applicationContext)
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
                            BackendRuntime.stop()
                            mainHandler.post { result.success(null) }
                        }
                    }
                    "status" -> {
                        executor.execute {
                            mainHandler.post {
                                result.success(
                                    mapOf(
                                        "healthy" to BackendRuntime.isHealthy(),
                                        "port" to BackendRuntime.PORT,
                                        "running" to BackendRuntime.isProcessAlive(),
                                    ),
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val TAG = "SshAiBackend"
    }
}

/**
 * Process lifecycle for the embedded Go backend.
 * Prefer jniLibs `libssh_ai_agent.so` (Android-extracted, executable), fall back to assets.
 */
object BackendRuntime {
    const val PORT = 17890
    private const val TAG = "SshAiBackend"
    private val processRef = AtomicReference<Process?>(null)
    private val lock = Any()

    fun isProcessAlive(): Boolean {
        val p = processRef.get()
        return p != null && p.isAlive
    }

    fun isHealthy(): Boolean {
        return try {
            val url = URL("http://127.0.0.1:$PORT/v1/health")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 800
                readTimeout = 800
                requestMethod = "GET"
            }
            conn.responseCode == 200
        } catch (_: Exception) {
            false
        }
    }

    fun stop() {
        processRef.getAndSet(null)?.destroy()
    }

    fun ensureStarted(ctx: android.content.Context): Map<String, Any> {
        synchronized(lock) {
            val app = ctx.applicationContext
            val dataDir = File(app.filesDir, "backend-data").apply { mkdirs() }
            val tokenFile = File(dataDir, "local.token")
            val token = loadOrCreateToken(tokenFile)

            if (isHealthy()) {
                val existing = if (tokenFile.exists()) tokenFile.readText().trim() else token
                publishDebugToken(app, existing)
                Log.i(TAG, "backend already healthy")
                return resultMap(existing, already = true)
            }

            val bin = resolveBinary(app)
            Log.i(TAG, "starting backend bin=${bin.absolutePath} size=${bin.length()} exec=${bin.canExecute()}")

            // Best-effort stop previous handle (orphans may remain).
            stop()

            val logFile = File(dataDir, "backend.log")
            val pb = ProcessBuilder(bin.absolutePath).apply {
                directory(app.filesDir)
                redirectErrorStream(true)
                environment()["SSH_AI_DATA_DIR"] = dataDir.absolutePath
                environment()["SSH_AI_PORT"] = PORT.toString()
                environment()["SSH_AI_LOCAL_TOKEN"] = token
                environment()["HOME"] = app.filesDir.absolutePath
                environment()["TMPDIR"] = app.cacheDir.absolutePath
            }

            val proc = try {
                pb.start()
            } catch (e: Exception) {
                throw IllegalStateException("ProcessBuilder.start failed: ${e.message}", e)
            }
            processRef.set(proc)

            Thread {
                try {
                    BufferedReader(InputStreamReader(proc.inputStream)).use { br ->
                        val sink = StringBuilder()
                        var line: String?
                        while (br.readLine().also { line = it } != null) {
                            Log.i(TAG, "go: $line")
                            sink.append(line).append('\n')
                            if (sink.length > 32_000) sink.delete(0, sink.length - 16_000)
                            try {
                                logFile.writeText(sink.toString())
                            } catch (_: Exception) {
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "log drain: ${e.message}")
                }
            }.apply {
                isDaemon = true
                name = "go-backend-log"
                start()
            }

            val deadline = System.currentTimeMillis() + 15_000
            while (System.currentTimeMillis() < deadline) {
                if (!proc.isAlive) {
                    val code = try {
                        proc.exitValue()
                    } catch (_: Exception) {
                        -1
                    }
                    val tail = try {
                        logFile.readText().takeLast(800)
                    } catch (_: Exception) {
                        ""
                    }
                    throw IllegalStateException("backend exited early code=$code log=$tail")
                }
                if (isHealthy()) {
                    val finalTok = if (tokenFile.exists()) tokenFile.readText().trim() else token
                    publishDebugToken(app, finalTok)
                    Log.i(TAG, "backend healthy")
                    return resultMap(finalTok, already = false)
                }
                Thread.sleep(250)
            }
            val tail = try {
                logFile.readText().takeLast(800)
            } catch (_: Exception) {
                ""
            }
            throw IllegalStateException("backend health timeout on :$PORT log=$tail")
        }
    }

    private fun resultMap(token: String, already: Boolean): Map<String, Any> {
        return mapOf(
            "baseUrl" to "http://127.0.0.1:$PORT",
            "token" to token,
            "port" to PORT,
            "alreadyRunning" to already,
        )
    }

    private fun loadOrCreateToken(tokenFile: File): String {
        if (tokenFile.exists() && tokenFile.length() > 8) {
            return tokenFile.readText().trim()
        }
        val token = UUID.randomUUID().toString().replace("-", "") +
            UUID.randomUUID().toString().replace("-", "").take(16)
        tokenFile.writeText(token)
        return token
    }

    private fun resolveBinary(app: android.content.Context): File {
        // 1) jniLibs: Android extracts libssh_ai_agent.so into nativeLibraryDir
        try {
            val so = File(app.applicationInfo.nativeLibraryDir, "libssh_ai_agent.so")
            if (so.exists() && so.length() > 1024) {
                Log.i(TAG, "using jniLibs ${so.absolutePath}")
                return so
            }
        } catch (e: Exception) {
            Log.w(TAG, "nativeLibraryDir: ${e.message}")
        }

        // 2) extract from APK assets
        val outDir = File(app.filesDir, "bin").apply { mkdirs() }
        val out = File(outDir, "ssh-ai-agent")
        val names = listOf("go/ssh-ai-agent", "go/libssh_ai_agent.so")
        var opened = false
        for (name in names) {
            try {
                app.assets.open(name).use { input ->
                    FileOutputStream(out).use { output -> input.copyTo(output) }
                }
                opened = true
                Log.i(TAG, "extracted asset $name -> ${out.absolutePath}")
                break
            } catch (_: Exception) {
            }
        }
        if (!opened) {
            throw IllegalStateException("no go backend asset found (go/ssh-ai-agent)")
        }
        out.setReadable(true, true)
        out.setExecutable(true, true)
        out.setWritable(true, true)
        if (!out.canExecute()) {
            try {
                Runtime.getRuntime().exec(arrayOf("chmod", "700", out.absolutePath)).waitFor()
            } catch (_: Exception) {
            }
        }
        if (!out.canExecute()) {
            throw IllegalStateException("backend binary not executable: ${out.absolutePath}")
        }
        return out
    }

    private fun publishDebugToken(app: android.content.Context, token: String) {
        val debuggable =
            (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable || token.isEmpty()) return
        try {
            val ext = app.getExternalFilesDir(null) ?: return
            File(ext, "local.token").writeText(token)
            Log.i(TAG, "debug token -> ${ext.absolutePath}/local.token")
        } catch (e: Exception) {
            Log.w(TAG, "publishDebugToken: ${e.message}")
        }
    }
}
