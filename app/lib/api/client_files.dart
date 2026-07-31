part of 'client.dart';

mixin _ApiClientFiles on _ApiTransport {
  Future<Map<String, dynamic>> fsList(String hostId, String path) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/list'),
          headers: _headers,
          body: jsonEncode({'path': path}),
        )
        .apiTimeout(const Duration(seconds: 30));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsRead(
    String hostId,
    String path, {
    int? maxBytes,
    bool force = false,
  }) async {
    final body = <String, dynamic>{'path': path, 'force': force};
    if (maxBytes != null) body['maxBytes'] = maxBytes;
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/read'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .apiTimeout(const Duration(seconds: 60));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsWrite(
    String hostId,
    String path,
    String content, {
    bool confirmed = false,
  }) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/write'),
          headers: _headers,
          body: jsonEncode({
            'path': path,
            'content': content,
            'confirmed': confirmed,
          }),
        )
        .apiTimeout(const Duration(seconds: 60));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> fsMkdir(String hostId, String path, {bool confirmed = true}) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/mkdir'),
          headers: _headers,
          body: jsonEncode({'path': path, 'confirmed': confirmed}),
        )
        .apiTimeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  Future<void> fsRemove(String hostId, String path, {bool recursive = false, bool confirmed = true}) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/remove'),
          headers: _headers,
          body: jsonEncode({'path': path, 'recursive': recursive, 'confirmed': confirmed}),
        )
        .apiTimeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  Future<void> fsRename(String hostId, String oldPath, String newPath, {bool confirmed = true}) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/rename'),
          headers: _headers,
          body: jsonEncode({'oldPath': oldPath, 'newPath': newPath, 'confirmed': confirmed}),
        )
        .apiTimeout(const Duration(seconds: 30));
    _ensureOk(r);
  }

  /// Server-side SFTP copy (files + recursive dirs). Prefer over read+write.
  Future<Map<String, dynamic>> fsCopy(
    String hostId, {
    required String src,
    required String dest,
    bool confirmed = true,
  }) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/copy'),
          headers: _headers,
          body: jsonEncode({
            'src': src,
            'dest': dest,
            'confirmed': confirmed,
          }),
        )
        .apiTimeout(const Duration(seconds: 180));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsMove(
    String hostId, {
    required String src,
    required String dest,
    bool confirmed = true,
  }) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/move'),
          headers: _headers,
          body: jsonEncode({
            'src': src,
            'dest': dest,
            'confirmed': confirmed,
          }),
        )
        .apiTimeout(const Duration(seconds: 180));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fsDownload(String hostId, String path, {int maxBytes = 32 * 1024 * 1024}) async {
    final r = await _c
        .post(
          _u('/v1/hosts/$hostId/fs/download'),
          headers: _headers,
          body: jsonEncode({'path': path, 'maxBytes': maxBytes}),
        )
        .apiTimeout(const Duration(seconds: 120));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
