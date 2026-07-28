part of 'client.dart';

mixin _ApiClientAdmin on _ApiTransport {
  Future<List<dynamic>> listAudit({int limit = 100}) async {
    final r = await _c
        .get(_u('/v1/audit?limit=$limit'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (m['entries'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> listKnownHosts() async {
    final r = await _c.get(_u('/v1/known-hosts'), headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteKnownHost(String host, int port) async {
    final uri = Uri.parse('$baseUrl/v1/known-hosts').replace(queryParameters: {
      'host': host,
      'port': '$port',
    });
    final r = await _c.delete(uri, headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
  }

  Future<Map<String, dynamic>> clearKnownHosts() async {
    final uri = Uri.parse('$baseUrl/v1/known-hosts').replace(queryParameters: {
      'all': '1',
    });
    final r = await _c.delete(uri, headers: _headers).timeout(const Duration(seconds: 10));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listSessionMemory() async {
    final r = await _c.get(_u('/v1/session-memory'), headers: _headers).timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteSessionMemory({String? sessionId, bool all = false}) async {
    final q = <String, String>{};
    if (all) {
      q['all'] = '1';
    } else if (sessionId != null && sessionId.isNotEmpty) {
      q['sessionId'] = sessionId;
    } else {
      throw Exception('sessionId or all required');
    }
    final uri = Uri.parse('$baseUrl/v1/session-memory').replace(queryParameters: q);
    final r = await _c.delete(uri, headers: _headers).timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
