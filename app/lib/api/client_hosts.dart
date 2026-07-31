part of 'client.dart';

mixin _ApiClientHosts on _ApiTransport {
  Future<List<dynamic>> listHosts() async {
    final r = await _c.get(_u('/v1/hosts'), headers: _headers).apiTimeout(const Duration(seconds: 6));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['hosts'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> createHost(Map<String, dynamic> body) async {
    final r = await _c
        .post(_u('/v1/hosts'), headers: _headers, body: jsonEncode(body))
        .apiTimeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteHost(String id) async {
    final r = await _c.delete(_u('/v1/hosts/$id'), headers: _headers).apiTimeout(const Duration(seconds: 10));
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> updateHost(String id, Map<String, dynamic> body) async {
    final r = await _c
        .put(_u('/v1/hosts/$id'), headers: _headers, body: jsonEncode(body))
        .apiTimeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exec(
    String id,
    String command, {
    bool confirmed = false,
    String sessionId = 'manual',
  }) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$id/exec'),
          headers: _headers,
          body: jsonEncode({
            'command': command,
            'confirmed': confirmed,
            'sessionId': sessionId,
          }),
        )
        .apiTimeout(const Duration(seconds: 60));
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      throw ApiException(409, m['error']?.toString() ?? 'confirmation required', body: m);
    }
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> probe(String id) async {
    final r = await _c
        .post(_u('/v1/hosts/$id/probe'), headers: _headers, body: '{}')
        .apiTimeout(const Duration(seconds: 25));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
