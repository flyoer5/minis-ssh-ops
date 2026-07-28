import 'dart:convert';

import 'package:http/http.dart' as http;

part 'client_settings.dart';
part 'client_hosts.dart';
part 'client_agent.dart';
part 'client_files.dart';
part 'client_admin.dart';

class ApiClient {
  /// Local Go backend (loopback only).
  String baseUrl;
  String localToken;

  /// Shared non-streaming client (connection reuse for health/probe/fs).
  final http.Client _c = http.Client();
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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (localToken.isNotEmpty) 'X-Local-Token': localToken,
      };

  Uri _u(String path) => Uri.parse('$baseUrl$path');

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

class ApiException implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic>? body;
  ApiException(this.status, this.message, {this.body});
  @override
  String toString() => 'ApiException($status): $message';
}
