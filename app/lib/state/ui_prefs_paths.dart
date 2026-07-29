part of 'ui_prefs.dart';

extension UiPrefsPaths on UiPrefs {
  List<String> pathFavoritesFor(String? hostId) {
    if (hostId == null || hostId.isEmpty) return const [];
    final own = pathFavoritesByHost[hostId];
    if (own != null) return List<String>.from(own);
    final shared = pathFavoritesByHost[kPathFavShared];
    if (shared != null) return List<String>.from(shared);
    return const [];
  }

  static String _normPath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return '';
    if (!p.startsWith('/')) p = '/$p';
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  Future<void> setPathFavoritesFor(String hostId, List<String> paths) async {
    if (hostId.isEmpty) return;
    final cleaned = <String>[];
    for (final raw in paths) {
      final p = _normPath(raw);
      if (p.isEmpty) continue;
      if (!cleaned.contains(p)) cleaned.add(p);
      if (cleaned.length >= 12) break;
    }
    pathFavoritesByHost[hostId] = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pathFavoritesByHost', jsonEncode(pathFavoritesByHost));
    await prefs.remove('pathFavorites');
    notifyListeners();
  }

  Future<void> addPathFavorite(String hostId, String path) async {
    if (hostId.isEmpty) return;
    final list = pathFavoritesFor(hostId);
    final p = _normPath(path);
    if (p.isEmpty) return;
    list.remove(p);
    list.insert(0, p);
    await setPathFavoritesFor(hostId, list);
  }

  Future<void> removePathFavorite(String hostId, String path) async {
    if (hostId.isEmpty) return;
    final list = pathFavoritesFor(hostId)..remove(_normPath(path));
    await setPathFavoritesFor(hostId, list);
  }
}
