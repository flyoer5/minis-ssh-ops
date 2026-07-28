part of 'client.dart';

mixin ApiClientSettings on _ApiTransport {
  Future<Map<String, dynamic>> health() async {
    final r = await _c.get(_u('/v1/health')).timeout(const Duration(milliseconds: 800));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<String> pingLlm() async {
    final h = await health();
    if (h['ok'] != true) throw ApiException(500, 'backend not ok');
    return 'backend ok · features=${h['features']}';
  }

  Future<Map<String, dynamic>> getLlm() async {
    final r = await _c.get(_u('/v1/settings/llm'), headers: _headers).timeout(const Duration(seconds: 6));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<String>> listModels() async {
    final r = await _c.get(_u('/v1/settings/llm/models'), headers: _headers).timeout(const Duration(seconds: 20));
    _ensureOk(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = m['models'];
    if (list is! List) return <String>[];
    return [for (final e in list) e.toString()];
  }

  Future<Map<String, dynamic>> putLlm(Map<String, dynamic> body) async {
    final r = await _c
        .put(_u('/v1/settings/llm'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
