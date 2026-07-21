package com.minis.sshops

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "minis.sshops/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibDir" -> {
                        result.success(applicationInfo.nativeLibraryDir)
                    }
                    "filesDir" -> {
                        result.success(filesDir.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
