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

  Future<String> pingLlm() async {
    final h = await health();
    if (h['ok'] != true) throw ApiException(500, 'backend not ok');
    return 'backend ok · features=${h['features']}';
  }

  Future<Map<String, dynamic>> getLlm() async {
    final r = await http.get(_u('/v1/settings/llm'), headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> putLlm(Map<String, dynamic> body) async {
    final r = await http.put(
      _u('/v1/settings/llm'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listHosts() async {
    final r = await http.get(_u('/v1/hosts'), headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['hosts'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> createHost(Map<String, dynamic> body) async {
    final r = await http.post(
      _u('/v1/hosts'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteHost(String id) async {
    final r = await http.delete(_u('/v1/hosts/$id'), headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> updateHost(String id, Map<String, dynamic> body) async {
    final r = await http
        .put(_u('/v1/hosts/$id'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
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
    ).timeout(const Duration(seconds: 60));
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      throw ApiException(409, m['error']?.toString() ?? 'confirmation required', body: m);
    }
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> probe(String id) async {
    final r = await http.post(_u('/v1/hosts/$id/probe'), headers: _headers, body: '{}').timeout(const Duration(seconds: 45));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> agentPlan({
    required String hostId,
    required String goal,
    String? sessionId,
  }) async {
    final r = await http
        .post(
          _u('/v1/agent/plan'),
          headers: _headers,
          body: jsonEncode({
            'hostId': hostId,
            'goal': goal,
            if (sessionId != null) 'sessionId': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 120));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

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

  http.Client? _streamClient;

  void cancelAgentStream() {
    try {
      _streamClient?.close();
    } catch (_) {}
    _streamClient = null;
  }

  /// SSE progressive agent events (data: {...}\\n\\n).
  Future<void> agentChatStream({
    required String hostId,
    required String message,
    String? sessionId,
    required void Function(Map<String, dynamic> event) onEvent,
  }) async {
    cancelAgentStream();
    final client = http.Client();
    _streamClient = client;
    try {
      final req = http.Request('POST', _u('/v1/agent/chat/stream'));
      req.headers.addAll(_headers);
      req.body = jsonEncode({
        'hostId': hostId,
        'message': message,
        if (sessionId != null) 'sessionId': sessionId,
      });
      final res = await client.send(req).timeout(const Duration(seconds: 180));
      if (res.statusCode >= 400) {
        final body = await res.stream.bytesToString();
        throw ApiException(res.statusCode, body);
      }
      final buf = StringBuffer();
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buf.write(chunk);
        var s = buf.toString();
        while (true) {
          final idx = s.indexOf('\n\n');
          if (idx < 0) break;
          final block = s.substring(0, idx);
          s = s.substring(idx + 2);
          for (final line in block.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            final raw = line.substring(6).trim();
            if (raw.isEmpty) continue;
            try {
              final m = jsonDecode(raw);
              if (m is Map<String, dynamic>) {
                onEvent(m);
              } else if (m is Map) {
                onEvent(Map<String, dynamic>.from(m));
              }
            } catch (_) {}
          }
          buf
            ..clear()
            ..write(s);
        }
      }
    } finally {
      if (identical(_streamClient, client)) {
        _streamClient = null;
      }
      client.close();
    }
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
    final r = await http.get(_u('/v1/audit'), headers: _headers).timeout(const Duration(seconds: 15));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['entries'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> fsList(String hostId, String path) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/list'),
          headers: _headers,
          body: jsonEncode({'path': path}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsRead(String hostId, String path) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/read'),
          headers: _headers,
          body: jsonEncode({'path': path}),
        )
        .timeout(const Duration(seconds: 60));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsWrite(
    String hostId,
    String path,
    String content, {
    bool confirmed = false,
  }) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/write'),
          headers: _headers,
          body: jsonEncode({
            'path': path,
            'content': content,
            'confirmed': confirmed,
          }),
        )
        .timeout(const Duration(seconds: 60));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> fsMkdir(String hostId, String path, {bool confirmed = true}) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/mkdir'),
          headers: _headers,
          body: jsonEncode({'path': path, 'confirmed': confirmed}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  Future<void> fsRemove(String hostId, String path, {bool recursive = false, bool confirmed = true}) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/remove'),
          headers: _headers,
          body: jsonEncode({'path': path, 'recursive': recursive, 'confirmed': confirmed}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  Future<void> fsRename(String hostId, String oldPath, String newPath, {bool confirmed = true}) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/rename'),
          headers: _headers,
          body: jsonEncode({'oldPath': oldPath, 'newPath': newPath, 'confirmed': confirmed}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> fsDownload(String hostId, String path, {int maxBytes = 8 * 1024 * 1024}) async {
    final r = await http
        .post(
          _u('/v1/hosts/$hostId/fs/download'),
          headers: _headers,
          body: jsonEncode({'path': path, 'maxBytes': maxBytes}),
        )
        .timeout(const Duration(seconds: 120));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listKnownHosts() async {
    final r = await http.get(_u('/v1/known-hosts'), headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteKnownHost(String host, int port) async {
    final uri = Uri.parse('$baseUrl/v1/known-hosts').replace(queryParameters: {
      'host': host,
      'port': '$port',
    });
    final r = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
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
