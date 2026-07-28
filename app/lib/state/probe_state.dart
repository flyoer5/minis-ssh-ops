import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/models/probe_summary.dart';

/// Host probe execution, error mapping, and persisted result cache.
mixin ProbeState on ChangeNotifier {
  ApiClient get api;
  String? get selectedHostId;

  final Map<String, Map<String, dynamic>> probeCache = {};
  /// Bumped only when host probe cache changes — lets host list select without
  /// rebuilding on every Agent stream token notifyListeners().
  int probeGen = 0;


  void putProbeCache(String hostId, ProbeSummary s) {
    probeGen++;
    final at = DateTime.now().millisecondsSinceEpoch;
    probeCache[hostId] = {
      'ok': s.ok,
      'oneLine': s.oneLine,
      'detail': s.detail,
      'lines': [for (final l in s.lines) {'label': l.label, 'value': l.value}],
      'at': at,
    };
    notifyListeners();
    // Persist so a cold start can show last-known CPU/MEM instantly.
    _persistProbeCache(hostId, at);
  }

  /// Async fire-and-forget: write this host's snapshot to SharedPreferences.
  void _persistProbeCache(String hostId, int at) {
    SharedPreferences.getInstance().then((prefs) {
      final m = probeCache[hostId];
      if (m == null) return;
      try {
        prefs.setString('probeCache.$hostId', jsonEncode(m));
      } catch (_) {}
    });
  }

  /// Load persisted probe snapshots into memory on bootstrap. These are older
  /// than the live 2-min window by nature, so [getProbeCache] callers pass a
  /// longer maxAge (or accept the default for the in-memory path).
  Future<void> loadPersistedProbeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('probeCache.')) continue;
        final id = key.substring('probeCache.'.length);
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final m = jsonDecode(raw);
          if (m is Map) {
            final mm = Map<String, dynamic>.from(m);
            mm['persisted'] = true;
            probeCache[id] = mm;
          }
        } catch (_) {}
      }
      if (probeCache.isNotEmpty) {
        probeGen++;
        notifyListeners();
      }
    } catch (_) {}
  }

  ProbeSummary? getProbeCache(String hostId, {Duration maxAge = const Duration(minutes: 2)}) {
    final m = probeCache[hostId];
    if (m == null) return null;
    final at = m['at'] as int? ?? 0;
    // Entries restored from disk bypass the short live window so cold start can
    // show last-known metrics; the UI marks them via probeCacheTime anyway.
    final fromDisk = m['persisted'] == true;
    if (!fromDisk && DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds) {
      return null;
    }
    final lines = <ProbeLine>[];
    final rawLines = m['lines'];
    if (rawLines is List) {
      for (final e in rawLines) {
        if (e is Map) {
          lines.add(ProbeLine(e['label']?.toString() ?? '', e['value']?.toString() ?? ''));
        }
      }
    }
    return ProbeSummary(
      ok: m['ok'] == true,
      oneLine: m['oneLine']?.toString() ?? '',
      lines: lines,
      detail: m['detail']?.toString() ?? '',
    );
  }

  DateTime? probeCacheTime(String hostId) {
    final at = probeCache[hostId]?['at'] as int?;
    if (at == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(at);
  }



  Future<void> runProbe([String? hostId]) async {
    await runProbeSummary(hostId);
  }

  /// Human-readable probe for host list UI.
  Future<ProbeSummary> runProbeSummary([String? hostId, bool force = false]) async {
    final id = hostId ?? selectedHostId;
    if (id == null) {
      throw StateError('请先选择主机');
    }
    if (!force) {
      final cached = getProbeCache(id);
      if (cached != null) return cached;
    }
    try {
      final res = await api.probe(id);
      final summary = ProbeSummary.fromProbeJson(res);
      putProbeCache(id, summary);
      notifyListeners();
      return summary;
    } catch (e) {
      final friendly = friendlyProbeError(e);
      final summary = ProbeSummary(
        ok: false,
        oneLine: friendly['short']!,
        lines: [
          ProbeLine('错误', friendly['short']!),
          if ((friendly['detail'] ?? '').isNotEmpty) ProbeLine('详情', friendly['detail']!),
        ],
        detail: e.toString(),
      );
      // do not cache failures as success; still return for UI
      notifyListeners();
      return summary;
    }
  }

  /// Map probe exceptions to short Chinese labels for host cards.
  Map<String, String> friendlyProbeError(Object e) {
    final raw = e.toString();
    final s = raw.toLowerCase();
    String short;
    if (s.contains('timeout') || s.contains('deadline') || s.contains('timed out')) {
      short = '超时';
    } else if (s.contains('auth') ||
        s.contains('password') ||
        s.contains('permission denied') ||
        s.contains('unable to authenticate') ||
        s.contains('handshake failed') ||
        s.contains('publickey') ||
        s.contains('keyboard-interactive')) {
      short = '认证失败';
    } else if (s.contains('connection refused')) {
      short = '连接拒绝';
    } else if (s.contains('no route') ||
        s.contains('network is unreachable') ||
        s.contains('network unreachable') ||
        s.contains('host is down')) {
      short = '网络不可达';
    } else if (s.contains('connection reset') || s.contains('broken pipe')) {
      short = '连接中断';
    } else if (s.contains('unknown host') ||
        s.contains('no such host') ||
        s.contains('name or service not known') ||
        s.contains('temporary failure in name resolution') ||
        s.contains('failed host lookup')) {
      short = '域名解析失败';
    } else if (s.contains('host key') || s.contains('hostkey') || s.contains('tofu')) {
      short = 'HostKey 异常';
    } else if (s.contains('socketexception')) {
      short = '无法连接';
    } else {
      short = '探测失败';
    }
    var detail = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (detail.length > 120) detail = '${detail.substring(0, 120)}…';
    return {'short': short, 'detail': detail};
  }


}

