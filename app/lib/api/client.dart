import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

part 'client_settings.dart';
part 'client_hosts.dart';
part 'client_agent.dart';
part 'client_files.dart';
part 'client_admin.dart';

abstract class _ApiTransport {
  String get baseUrl;
  String get localToken;
  http.Client get _c;
  http.Client? get _streamClient;
  set _streamClient(http.Client? value);
  Map<String, String> get _headers;
  Uri _u(String path);
  void _ensureOk(http.Response response);
  Future<T> _withTimeout<T>(Future<T> request, Duration duration);
}

class ApiClient extends _ApiTransport
    with
        _ApiClientSettings,
        _ApiClientHosts,
        _ApiClientAgent,
        _ApiClientFiles,
        _ApiClientAdmin {
  /// Local Go backend (loopback only).
  @override
  String baseUrl;
  @override
  String localToken;

  /// Shared non-streaming client (connection reuse for health/probe/fs).
  @override
  final http.Client _c = http.Client();
  @override
  http.Client? _streamClient;

  ApiClient({
    this.baseUrl = 'http://127.0.0.1:17890',
    this.localToken = '',
  });

  void dispose() {
    try {
      _streamClient?.close();
    } catch (_) {}
    _streamClient = null;
    _c.close();
  }

  @override
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (localToken.isNotEmpty) 'X-Local-Token': localToken,
      };

  @override
  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<T> testTimeoutForTest<T>(Future<T> request, Duration duration) =>
      _withTimeout(request, duration);

  @override
  Future<T> _withTimeout<T>(Future<T> request, Duration duration) async {
    try {
      return await request.timeout(duration);
    } on TimeoutException {
      throw ApiTimeoutException(duration);
    }
  }

  @override
  void _ensureOk(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String msg = r.body;
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
      msg = (body['error'] ?? r.body).toString();
    } catch (_) {}
    throw ApiException(r.statusCode, msg, body: body);
  }
}

extension ApiFutureTimeout<T> on Future<T> {
  Future<T> apiTimeout(Duration duration) async {
    try {
      return await timeout(duration);
    } on TimeoutException {
      throw ApiTimeoutException(duration);
    }
  }
}

class ApiTimeoutException implements Exception {
  final Duration duration;
  ApiTimeoutException(this.duration);

  @override
  String toString() => '请求超时，请检查网络或主机连接';
}

class ApiException implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic>? body;
  ApiException(this.status, this.message, {this.body});
  @override
  String toString() => 'ApiException($status): $message';
}
