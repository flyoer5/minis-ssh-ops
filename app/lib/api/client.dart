import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Local Go backend (loopback only).
  String baseUrl;
  String localToken;

  ApiClient({
    this.baseUrl = 'http://127.0.0.1:17890',
    this.localToken = '',
  });

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (localToken.isNotEmpty) 'X-Local-Token': localToken,
      };

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> health() async {
    final r = await http.get(_u('/v1/health')).timeout(const Duration(seconds: 3));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLlm() async {
    final r = await http.get(_u('/v1/settings/llm'), headers: _headers);
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> putLlm(Map<String, dynamic> body) async {
    final r = await http.put(
      _u('/v1/settings/llm'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listHosts() async {
    final r = await http.get(_u('/v1/hosts'), headers: _headers);
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['hosts'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> createHost(Map<String, dynamic> body) async {
    final r = await http.post(
      _u('/v1/hosts'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteHost(String id) async {
    final r = await http.delete(_u('/v1/hosts/$id'), headers: _headers);
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> exec(
    String id,
    String command, {
    bool confirmed = false,
    String sessionId = 'manual',
  }) async {
    final r = await http.post(
      _u('/v1/hosts/$id/exec'),
      headers: _headers,
      body: jsonEncode({
        'command': command,
        'confirmed': confirmed,
        'sessionId': sessionId,
      }),
    );
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      throw ApiException(409, m['error']?.toString() ?? 'confirmation required', body: m);
    }
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> probe(String id) async {
    final r = await http.post(_u('/v1/hosts/$id/probe'), headers: _headers, body: '{}');
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> agentPlan({
    required String hostId,
    required String goal,
    String? sessionId,
  }) async {
    final r = await http.post(
      _u('/v1/agent/plan'),
      headers: _headers,
      body: jsonEncode({
        'hostId': hostId,
        'goal': goal,
        if (sessionId != null) 'sessionId': sessionId,
      }),
    ).timeout(const Duration(seconds: 120));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// OpenClaw-style multi-turn tool loop.
  Future<Map<String, dynamic>> agentChat({
    required String hostId,
    required String message,
    String? sessionId,
  }) async {
    final r = await http
        .post(
          _u('/v1/agent/chat'),
          headers: _headers,
          body: jsonEncode({
            'hostId': hostId,
            'message': message,
            if (sessionId != null) 'sessionId': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 180));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> agentExecStep({
    required String hostId,
    required String command,
    required bool confirmed,
    String sessionId = 'agent',
    int stepId = 0,
  }) async {
    final r = await http.post(
      _u('/v1/agent/exec-step'),
      headers: _headers,
      body: jsonEncode({
        'hostId': hostId,
        'command': command,
        'confirmed': confirmed,
        'sessionId': sessionId,
        'stepId': stepId,
      }),
    );
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      throw ApiException(409, m['error']?.toString() ?? 'confirmation required', body: m);
    }
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listAudit() async {
    final r = await http.get(_u('/v1/audit'), headers: _headers);
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['entries'] as List<dynamic>? ?? []);
  }

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
