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

  static Future<Map<String, dynamic>?> status() async {
    if (!isAndroidNative) return null;
    final raw = await _channel.invokeMethod<dynamic>('status');
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isAndroidNative) return true;
    final v = await _channel.invokeMethod<dynamic>('isIgnoringBatteryOptimizations');
    return v == true;
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroidNative) return;
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  static Future<void> openBatterySettings() async {
    if (!isAndroidNative) return;
    await _channel.invokeMethod('openBatterySettings');
  }

  static Future<String> exportBackendLog() async {
    if (!isAndroidNative) return '';
    final v = await _channel.invokeMethod<dynamic>('exportBackendLog');
    return v?.toString() ?? '';
  }

  /// Save raw base64 bytes into system Downloads. Returns path/uri string.
  static Future<String> saveBytesToDownloads({
    required String name,
    required String b64,
  }) async {
    if (!isAndroidNative) {
      throw PlatformException(code: 'UNSUPPORTED', message: 'only Android');
    }
    final v = await _channel.invokeMethod<dynamic>('saveBytesToDownloads', {
      'name': name,
      'b64': b64,
    });
    return v?.toString() ?? '';
  }
}
