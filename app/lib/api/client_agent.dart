part of 'client.dart';

mixin _ApiClientAgent on _ApiTransport {
  Future<Map<String, dynamic>> agentPlan({
    required String hostId,
    required String goal,
    String? sessionId,
  }) async {
    final r = await _c
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
    bool confirmWrites = false,
    int maxRounds = 12,
    double temperature = 0,
    String customPrompt = '',
  }) async {
    final r = await _c
        .post(
          _u('/v1/agent/chat'),
          headers: _headers,
          body: jsonEncode({
            'hostId': hostId,
            'message': message,
            if (sessionId != null) 'sessionId': sessionId,
            'confirmWrites': confirmWrites,
            'maxRounds': maxRounds,
            if (temperature > 0) 'temperature': temperature,
            if (customPrompt.isNotEmpty) 'customPrompt': customPrompt,
          }),
        )
        .timeout(const Duration(seconds: 180));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

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
    bool confirmWrites = false,
    int maxRounds = 12,
    double temperature = 0,
    String customPrompt = '',
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
        'confirmWrites': confirmWrites,
        'maxRounds': maxRounds,
        if (temperature > 0) 'temperature': temperature,
        if (customPrompt.isNotEmpty) 'customPrompt': customPrompt,
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

  Future<List<Map<String, dynamic>>> reorderHosts(List<String> ids) async {
    final r = await _c
        .put(
          _u('/v1/hosts/reorder'),
          headers: _headers,
          body: jsonEncode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 20));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = m['hosts'];
    if (list is! List) return [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<List<Map<String, dynamic>>> listAgentSessions({
    String? hostId,
    String? q,
    int limit = 50,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    if (hostId != null && hostId.isNotEmpty) qp['hostId'] = hostId;
    if (q != null && q.trim().isNotEmpty) qp['q'] = q.trim();
    final uri = Uri.parse('$baseUrl/v1/agent/sessions').replace(queryParameters: qp);
    final r = await _c.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = m['sessions'];
    if (list is! List) return [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<Map<String, dynamic>> createAgentSession({String? hostId, String? title}) async {
    final r = await _c
        .post(
          _u('/v1/agent/sessions'),
          headers: _headers,
          body: jsonEncode({
            if (hostId != null && hostId.isNotEmpty) 'hostId': hostId,
            if (title != null && title.isNotEmpty) 'title': title,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getAgentSessionMessages(String id, {int limit = 500}) async {
    final uri = Uri.parse('$baseUrl/v1/agent/sessions/$id/messages')
        .replace(queryParameters: {'limit': '$limit'});
    final r = await _c.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = m['messages'];
    if (list is! List) return [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<Map<String, dynamic>> renameAgentSession(String id, String title) async {
    final r = await _c
        .patch(
          _u('/v1/agent/sessions/$id'),
          headers: _headers,
          body: jsonEncode({'title': title}),
        )
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteAgentSessionRemote(String id) async {
    final r = await _c
        .delete(_u('/v1/agent/sessions/$id'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
  }

  /// Patch session title and/or overrides. Pass explicit null via clear* flags.
  Future<Map<String, dynamic>> patchAgentSession(
    String id, {
    String? title,
    bool clearOverrides = false,
    int? ovMaxRounds,
    bool clearMaxRounds = false,
    double? ovTemperature,
    bool clearTemperature = false,
    int? ovConfirm,
    bool clearConfirm = false,
    String? ovPrompt,
    bool clearPrompt = false,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (clearOverrides) body['clearOverrides'] = true;
    if (clearMaxRounds) {
      body['ovMaxRounds'] = null;
    } else if (ovMaxRounds != null) {
      body['ovMaxRounds'] = ovMaxRounds;
    }
    if (clearTemperature) {
      body['ovTemperature'] = null;
    } else if (ovTemperature != null) {
      body['ovTemperature'] = ovTemperature;
    }
    if (clearConfirm) {
      body['ovConfirm'] = null;
    } else if (ovConfirm != null) {
      body['ovConfirm'] = ovConfirm;
    }
    if (clearPrompt) {
      body['ovPrompt'] = null;
    } else if (ovPrompt != null) {
      body['ovPrompt'] = ovPrompt;
    }
    final r = await _c
        .patch(
          _u('/v1/agent/sessions/$id'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAgentSessionMemory(String id) async {
    final r = await _c
        .get(_u('/v1/agent/sessions/$id/memory'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteAgentSessionMemory(String id) async {
    final r = await _c
        .delete(_u('/v1/agent/sessions/$id/memory'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> getAgentSession(String id) async {
    final r = await _c
        .get(_u('/v1/agent/sessions/$id'), headers: _headers)
        .timeout(const Duration(seconds: 15));
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
    final r = await _withTimeout(
      _c.post(
        _u('/v1/agent/exec-step'),
        headers: _headers,
        body: jsonEncode({
          'hostId': hostId,
          'command': command,
          'confirmed': confirmed,
          'sessionId': sessionId,
          'stepId': stepId,
        }),
      ),
      const Duration(seconds: 60),
    );
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      throw ApiException(409, m['error']?.toString() ?? 'confirmation required', body: m);
    }
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
