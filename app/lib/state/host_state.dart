import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';

/// Host inventory, selection, persistence, and SSH connectivity checks.
mixin HostState on ChangeNotifier {
  ApiClient get api;
  Map<String, List<String>> get pathFavoritesByHost;

  List<dynamic> hosts = [];
  String? selectedHostId;

  String get hostLabel => hostLabelFor(selectedHostId);

  String hostLabelFor(String? id) {
    if (id == null) return '未选择主机';
    for (final h in hosts) {
      if (h is Map && h['id'] == id) {
        final name = (h['name'] as String?)?.trim();
        final user = h['username'] ?? '';
        final host = h['host'] ?? '';
        final port = h['port'] ?? 22;
        if (name != null && name.isNotEmpty) {
          return '$name  $user@$host:$port';
        }
        return '$user@$host:$port';
      }
    }
    return id;
  }

  Map<String, dynamic>? hostMap(String? id) {
    if (id == null) return null;
    for (final h in hosts) {
      if (h is Map && h['id'] == id) return Map<String, dynamic>.from(h);
    }
    return null;
  }

  Future<void> resetHostKeyForSelected() async {
    final h = hostMap(selectedHostId);
    if (h == null) return;
    final host = h['host']?.toString() ?? '';
    final port = h['port'] is int ? h['port'] as int : int.tryParse('${h['port']}') ?? 22;
    if (host.isEmpty) return;
    await api.deleteKnownHost(host, port);
  }

  Future<void> refreshHosts() async {
    hosts = await api.listHosts();
    // Drop ghost selection if host was deleted while app was closed.
    if (selectedHostId != null &&
        !hosts.any((h) => h['id']?.toString() == selectedHostId)) {
      selectedHostId = null;
      SharedPreferences.getInstance().then((p) => p.remove('selectedHostId'));
    }
    if (selectedHostId == null && hosts.isNotEmpty) {
      selectedHostId = hosts.first['id'] as String?;
    }
    notifyListeners();
  }

  /// Persist user drag order (ids in display order).
  Future<void> reorderHosts(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= hosts.length) return;
    var ni = newIndex;
    if (ni > oldIndex) ni -= 1;
    if (ni < 0 || ni >= hosts.length) return;
    final list = List<dynamic>.from(hosts);
    final item = list.removeAt(oldIndex);
    list.insert(ni, item);
    hosts = list;
    notifyListeners();
    final ids = <String>[
      for (final h in hosts)
        if (h is Map && h['id'] != null) h['id'].toString(),
    ];
    try {
      final updated = await api.reorderHosts(ids);
      if (updated.isNotEmpty) {
        hosts = updated;
        notifyListeners();
      }
    } catch (_) {
      // Keep optimistic order; next refresh reconciles.
    }
  }


  /// Creates host and returns its id (when API provides one).
  Future<String?> addHost(Map<String, dynamic> body) async {
    final created = await api.createHost(body);
    await refreshHosts();
    final id = created['id']?.toString();
    if (id != null && id.isNotEmpty) {
      selectHost(id);
      return id;
    }
    // Fallback: match last list entry by host:port:user
    final host = body['host']?.toString();
    final port = body['port'] is int ? body['port'] as int : int.tryParse('${body['port']}') ?? 22;
    final user = body['username']?.toString() ?? 'root';
    for (final h in hosts.reversed) {
      if (h is! Map) continue;
      final hid = h['id']?.toString();
      if (hid == null) continue;
      if (h['host']?.toString() == host &&
          (h['port'] is int ? h['port'] as int : int.tryParse('${h['port']}') ?? 22) == port &&
          h['username']?.toString() == user) {
        selectHost(hid);
        return hid;
      }
    }
    return null;
  }

  Future<void> removeHost(String id) async {
    await api.deleteHost(id);
    if (selectedHostId == id) {
      selectedHostId = null;
      // Drop stale id from prefs so cold start doesn't re-select a ghost host.
      SharedPreferences.getInstance().then((p) => p.remove('selectedHostId'));
    }
    // Drop this host's path favorites (no longer useful).
    if (pathFavoritesByHost.containsKey(id)) {
      pathFavoritesByHost.remove(id);
      SharedPreferences.getInstance().then((p) {
        p.setString('pathFavoritesByHost', jsonEncode(pathFavoritesByHost));
      });
    }
    await refreshHosts();
  }

  Future<void> updateHost(String id, Map<String, dynamic> body) async {
    await api.updateHost(id, body);
    await refreshHosts();
  }

  void selectHost(String? id) {
    if (id != null && id.isNotEmpty) {
      final exists = hosts.any((h) => h['id']?.toString() == id);
      if (!exists) {
        // Session may reference a deleted host — don't pin a ghost selection.
        id = null;
      }
    }
    selectedHostId = id;
    notifyListeners();
    SharedPreferences.getInstance().then((p) {
      if (id == null) {
        p.remove('selectedHostId');
      } else {
        p.setString('selectedHostId', id);
      }
    });
  }








  Future<String> testHostSsh([String? hostId]) async {
    final id = hostId ?? selectedHostId;
    if (id == null) throw StateError('无主机');
    final res = await api.exec(id, 'echo OK && uname -s', confirmed: false);
    final out = '${res['stdout'] ?? ''}'.trim();
    if ((res['exitCode'] ?? 1) != 0) {
      throw ApiException(502, out.isEmpty ? 'ssh failed' : out);
    }
    return out;
  }

}

