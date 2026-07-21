import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the embedded Go `opsd` process on device.
class OpsdService {
  OpsdService._();
  static final OpsdService instance = OpsdService._();

  static const _channel = MethodChannel('minis.sshops/native');
  static const _assetBin = 'assets/opsd/opsd_arm64';
  static const _prefToken = 'opsd_token';
  static const _prefPort = 'opsd_port';

  Process? _proc;
  String _token = 'devtoken123';
  int _port = 18765;
  Directory? _dataDir;
  File? _binFile;

  String get token => _token;
  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';
  Uri api(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'X-Ops-Token': _token,
      };

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefToken) ?? _generateToken();
    await prefs.setString(_prefToken, _token);
    _port = prefs.getInt(_prefPort) ?? 18765;

    final support = await getApplicationSupportDirectory();
    _dataDir = Directory('${support.path}/opsd-data');
    await _dataDir!.create(recursive: true);

    await _prepareWebUi(support);
    _binFile = await _resolveBinary(support);

    if (await _healthOk()) {
      return;
    }

    await _killStale();
    await _spawn();
    await _waitHealthy(timeout: const Duration(seconds: 25));
  }

  Future<void> ensureRunning() async {
    if (await _healthOk()) return;
    await start();
  }

  Future<void> stop() async {
    _proc?.kill(ProcessSignal.sigterm);
    _proc = null;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final res = await http.get(api(path), headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}', uri: api(path));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(api(path), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    // 409 confirmation etc — still return body for caller if JSON
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300 && res.statusCode != 409) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}', uri: api(path));
    }
    map['_status'] = res.statusCode;
    return map;
  }

  Future<File> _resolveBinary(Directory support) async {
    // 1) Prefer jniLibs-packaged libopsd.so (executable, extracted by Android)
    try {
      final nativeDir = await _channel.invokeMethod<String>('nativeLibDir');
      if (nativeDir != null) {
        final so = File('$nativeDir/libopsd.so');
        if (await so.exists()) {
          return so;
        }
      }
    } catch (_) {}

    // 2) Fallback: extract Flutter asset
    final bin = File('${support.path}/opsd');
    final data = await rootBundle.load(_assetBin);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final needWrite = !await bin.exists() || await bin.length() != bytes.length;
    if (needWrite) {
      await bin.writeAsBytes(bytes, flush: true);
      await Process.run('chmod', ['755', bin.path]);
    }
    return bin;
  }

  /// Copy bundled web UI from Flutter assets if present under assets/web/.
  Future<void> _prepareWebUi(Directory support) async {
    final webRoot = Directory('${support.path}/opsd-web');
    // Single-page UI (prepare_assets.sh copies web/static → assets/web/)
    const files = ['index.html'];
    for (final name in files) {
      try {
        final data = await rootBundle.load('assets/web/$name');
        await webRoot.create(recursive: true);
        final out = File('${webRoot.path}/$name');
        await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } catch (_) {
        // asset not packaged — WebView may 404; native pages still work
      }
    }
  }

  Future<void> _spawn() async {
    final bin = _binFile!;
    final data = _dataDir!;
    final webDir = Directory('${data.parent.path}/opsd-web');
    final args = <String>[
      '-addr',
      '127.0.0.1:$_port',
      '-data',
      data.path,
    ];
    if (await webDir.exists()) {
      args.addAll(['-web', webDir.path]);
    }

    _proc = await Process.start(
      bin.path,
      args,
      environment: {'OPSD_TOKEN': _token},
      workingDirectory: data.parent.path,
      mode: ProcessStartMode.detachedWithStdio,
    );
    unawaited(_proc!.stdout.transform(utf8.decoder).forEach((_) {}));
    unawaited(_proc!.stderr.transform(utf8.decoder).forEach((line) {
      print('[opsd] $line');
    }));
  }

  Future<bool> _healthOk() async {
    try {
      final res = await http
          .get(api('/api/health'), headers: headers)
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _waitHealthy({required Duration timeout}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await _healthOk()) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('opsd health check timeout on $baseUrl (bin=${_binFile?.path})');
  }

  Future<void> _killStale() async {
    try {
      await Process.run('sh', ['-c', 'pkill -f "opsd -addr 127.0.0.1:$_port" || true']);
    } catch (_) {}
  }

  String _generateToken() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'ops_${r}_${r.hashCode.abs().toRadixString(16)}';
  }
}
