package com.sshai.agent.ssh_ai_agent

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
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
        // Kick backend + FGS as early as possible
        executor.execute {
            try {
                BackendRuntime.ensureStarted(applicationContext)
                BackendService.start(applicationContext)
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
                                try {
                                    BackendService.start(applicationContext)
                                } catch (_: Exception) {
                                }
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
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBattery())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            requestIgnoreBattery()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BATTERY", e.message, null)
                        }
                    }
                    "openBatterySettings" -> {
                        try {
                            openBatterySettings()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BATTERY", e.message, null)
                        }
                    }
                    "exportBackendLog" -> {
                        executor.execute {
                            try {
                                val dataDir = File(applicationContext.filesDir, "backend-data")
                                val log = File(dataDir, "backend.log")
                                val text = if (log.exists()) log.readText() else ""
                                mainHandler.post { result.success(text) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("LOG", e.message, null) }
                            }
                        }
                    }
                    "saveBytesToDownloads" -> {
                        executor.execute {
                            try {
                                val name = call.argument<String>("name") ?: "download.bin"
                                val b64 = call.argument<String>("b64") ?: ""
                                val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
                                val path = saveToDownloads(name, bytes)
                                mainHandler.post { result.success(path) }
                            } catch (e: Exception) {
                                Log.e(TAG, "saveBytesToDownloads failed", e)
                                mainHandler.post { result.error("SAVE", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(name: String, bytes: ByteArray): String {
        val safe = name.replace(Regex("[\\\\/]+"), "_").ifEmpty { "download.bin" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, safe)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("openOutputStream failed")
            values.clear()
            values.put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        }
        @Suppress("DEPRECATION")
        val dir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        var out = File(dir, safe)
        var i = 1
        val dot = safe.lastIndexOf('.')
        val base = if (dot > 0) safe.substring(0, dot) else safe
        val ext = if (dot > 0) safe.substring(dot) else ""
        while (out.exists()) {
            out = File(dir, "${base}_$i$ext")
            i++
        }
        FileOutputStream(out).use { it.write(bytes) }
        return out.absolutePath
    }

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(PowerManager::class.java) ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBattery()) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun openBatterySettings() {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(intent)
        } catch (_: Exception) {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
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
    /**
     * Base listen port. Real port is derived from package name so sibling
     * installs (old / next) do not share one :17890 and steal each other's backend.
     * Range: 17890 + (hash % 1024) → 17890..18913
     */
    private const val PORT_BASE = 17890
    private const val PORT_SPAN = 1024
    @Volatile
    private var resolvedPort: Int = PORT_BASE

    /** Current derived port (valid after resolvePort / ensureStarted). */
    val PORT: Int
        get() = resolvedPort

    private const val TAG = "SshAiBackend"
    private val processRef = AtomicReference<Process?>(null)
    private val lock = Any()

    fun resolvePort(ctx: android.content.Context): Int {
        val pkg = ctx.applicationContext.packageName
        val offset = (pkg.hashCode() and 0x7fffffff) % PORT_SPAN
        resolvedPort = PORT_BASE + offset
        Log.i(TAG, "resolvePort pkg=$pkg → $resolvedPort")
        return resolvedPort
    }

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
            resolvePort(app)
            val dataDir = File(app.filesDir, "backend-data").apply { mkdirs() }
            val tokenFile = File(dataDir, "local.token")
            val token = loadOrCreateToken(tokenFile)

            if (isHealthy()) {
                val existing = if (tokenFile.exists()) tokenFile.readText().trim() else token
                publishDebugToken(app, existing)
                Log.i(TAG, "backend already healthy on :$PORT")
                return resultMap(existing, already = true)
            }

            val bin = resolveBinary(app)
            Log.i(TAG, "starting backend bin=${bin.absolutePath} size=${bin.length()} exec=${bin.canExecute()} port=$PORT")

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
                Thread.sleep(100)
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
