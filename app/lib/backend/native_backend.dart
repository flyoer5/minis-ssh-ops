import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Starts the embedded Go backend on Android (no-op on web/desktop).
class NativeBackend {
  static const _channel = MethodChannel('com.sshai.agent/backend');

  static bool get isAndroidNative => !kIsWeb && Platform.isAndroid;

  /// Returns `{baseUrl, token, port, alreadyRunning}` or null if not Android.
  static Future<Map<String, dynamic>?> ensureStarted() async {
    if (!isAndroidNative) return null;
    final raw = await _channel.invokeMethod<dynamic>('ensureStarted');
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
