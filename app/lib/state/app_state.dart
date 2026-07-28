import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/backend_url.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/models/probe_summary.dart';
import 'package:ssh_ai_agent/state/agent_chat_controller.dart';
import 'package:ssh_ai_agent/state/ui_prefs.dart';

export 'package:ssh_ai_agent/models/agent_session.dart';
export 'package:ssh_ai_agent/models/probe_summary.dart';

class AppState extends ChangeNotifier with UiPrefs, AgentChatController {
  AppState(this.api);

  @override
  final ApiClient api;

  bool backendOk = false;
  List<String> backendFeatures = [];
  String? backendVersion;
  bool startingBackend = false;
  String? backendError;
  String? backendNote;
  List<dynamic> hosts = [];
  Map<String, dynamic>? llm;
  @override
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

  List<dynamic> audit = [];

  // --- Probe cache (hostId -> summary json + epoch ms) ---
  final Map<String, Map<String, dynamic>> probeCache = {};
  /// Bumped only when host probe cache changes — lets host list select without
  /// rebuilding on every Agent stream token notifyListeners().
  int probeGen = 0;
  // UI prefs (fonts/nav/host card) live in UiPrefs mixin
  bool batteryIgnored = true;
  bool onboarded = true;
  bool bootstrapped = false;

  Future<void> bootstrap() async {
    startingBackend = true;
    backendError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('baseUrl') ?? api.baseUrl;
    api.localToken = prefs.getString('localToken') ?? api.localToken;
    selectedHostId = prefs.getString('selectedHostId') ?? selectedHostId;
    onboarded = true; // onboarding removed
    loadUiPrefs(prefs);
    loadAgentSessionsFromPrefs(prefs);
    // Last-known host metrics so the hosts page shows CPU/MEM instantly on
    // cold start (marked stale via probeCacheTime).
    unawaited(loadPersistedProbeCache());

    if (NativeBackend.isAndroidNative) {
      Object? lastErr;
      for (var i = 0; i < 2; i++) {
        try {
          final info = await NativeBackend.ensureStarted();
          if (info != null) {
            final base = (info['baseUrl'] as String?) ?? api.baseUrl;
            final tok = (info['token'] as String?) ?? '';
            api.baseUrl = base;
            if (tok.isNotEmpty) api.localToken = tok;
            // Persist off critical path.
            unawaited(prefs.setString('baseUrl', api.baseUrl));
            unawaited(prefs.setString('localToken', api.localToken));
            backendNote = info['alreadyRunning'] == true ? '本机 Go 已在运行' : '已启动内置 Go 后端';
            lastErr = null;
            break;
          }
        } catch (e) {
          lastErr = e;
          backendNote = '启动后端重试 ${i + 1}/2…';
          notifyListeners();
          await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
        }
      }
      if (lastErr != null) {
        backendError = '启动内置后端失败: $lastErr';
      }
    }

    // Kotlin ensureStarted already blocks until /v1/health is 200 — one check is enough.
    await refreshHealth();
    if (!backendOk) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await refreshHealth();
    }

    startingBackend = false;
    bootstrapped = true;
    notifyListeners(); // paint HomeShell immediately

    // Hosts/LLM/battery after first frame — do not block RootGate.
    if (backendOk) {
      try {
        await Future.wait<void>([refreshHosts(), refreshLlm()]);
      } catch (e) {
        backendError = '加载数据失败: $e';
        notifyListeners();
      }
    }
    try {
      batteryIgnored = await NativeBackend.isIgnoringBatteryOptimizations();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    onboarded = true;
    notifyListeners();
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', false);
    onboarded = false;
    notifyListeners();
  }

  Future<void> saveConnection({required String baseUrl, required String token}) async {
    final validatedBaseUrl = validateBackendBaseUrl(baseUrl).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', validatedBaseUrl);
    await prefs.setString('localToken', token);
    api.baseUrl = validatedBaseUrl;
    api.localToken = token;
    await refreshHealth();
    if (backendOk) {
      await refreshHosts();
      await refreshLlm();
    }
  }

  Future<void> refreshHealth() async {
    try {
      final h = await api.health();
      backendOk = h['ok'] == true;
      if (backendOk) backendError = null;
      final feats = h['features'];
      if (feats is List) {
        backendFeatures = [for (final e in feats) e.toString()];
      }
      final ver = h['version']?.toString();
      if (ver != null && ver.isNotEmpty) backendVersion = ver;
    } catch (e) {
      backendOk = false;
      backendError = e.toString();
    }
    notifyListeners();
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

  Future<void> refreshLlm() async {
    llm = await api.getLlm();
    notifyListeners();
  }

  int auditLimit = 100;
  Future<void> refreshAudit({int? limit}) async {
    if (limit != null) auditLimit = limit;
    audit = await api.listAudit(limit: auditLimit);
    notifyListeners();
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








  Future<void> requestBatteryExempt() async {
    await NativeBackend.requestIgnoreBatteryOptimizations();
    batteryIgnored = await NativeBackend.isIgnoringBatteryOptimizations();
    notifyListeners();
  }

  Future<void> openBatterySettings() async {
    await NativeBackend.openBatterySettings();
  }

  Future<String> exportBackendLog() => NativeBackend.exportBackendLog();

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

  Future<String> testLlmReachable() async {
    // minimal: ensure LLM configured and do a 1-token style agent chat requires host
    final id = selectedHostId;
    if (id == null) throw StateError('先选主机再测模型');
    final res = await api.agentChat(hostId: id, message: '只回复ok两个字母', sessionId: 'ping-' + DateTime.now().millisecondsSinceEpoch.toString());
    return res.toString().length > 20 ? '模型可达' : res.toString();
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


  Future<String> exportConfigJson({bool includeSecrets = false}) async {
    final hostsOut = <Map<String, dynamic>>[];
    for (final h in hosts) {
      if (h is! Map) continue;
      final m = <String, dynamic>{
        'name': h['name'],
        'host': h['host'],
        'port': h['port'],
        'username': h['username'],
      };
      hostsOut.add(m);
    }
    final llmOut = <String, dynamic>{
      'baseUrl': llm?['baseUrl'],
      'model': llm?['model'],
      'apiKeySet': llm?['apiKeySet'] == true,
    };
    final obj = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'hosts': hostsOut,
      'llm': llmOut,
      'prefs': uiPrefsExport(),
      'note': includeSecrets
          ? 'secrets not exported via this path'
          : 'passwords/keys not included',
    };
    return JsonEncoder.withIndent('  ').convert(obj);
  }


  Future<String> importConfigJson(String raw) async {
    final obj = jsonDecode(raw);
    if (obj is! Map) throw StateError('invalid json');
    var added = 0;
    final hl = obj['hosts'];
    if (hl is List) {
      for (final e in hl) {
        if (e is! Map) continue;
        final host = e['host']?.toString() ?? '';
        if (host.isEmpty) continue;
        // skip if same host:port:user exists
        final port = e['port'] is int ? e['port'] as int : int.tryParse('${e['port']}') ?? 22;
        final user = e['username']?.toString() ?? 'root';
        final exists = hosts.any((h) =>
            h is Map &&
            h['host']?.toString() == host &&
            (h['port'] is int ? h['port'] as int : int.tryParse('${h['port']}') ?? 22) == port &&
            h['username']?.toString() == user);
        if (exists) continue;
        await api.createHost({
          'name': e['name']?.toString() ?? host,
          'host': host,
          'port': port,
          'username': user,
        });
        added++;
      }
    }
    final l = obj['llm'];
    if (l is Map) {
      final base = l['baseUrl']?.toString() ?? '';
      final model = l['model']?.toString() ?? '';
      if (base.isNotEmpty && model.isNotEmpty) {
        await saveLlm(baseUrl: base, model: model);
      }
    }
    final pr = obj['prefs'];
    if (pr is Map) {
      await applyUiPrefsImport(pr);
    }
    await refreshHosts();
    await refreshLlm();
    return '导入主机 +$added';
  }

  Future<List<String>> fetchModels() async {
    return api.listModels();
  }

  Future<void> saveLlm({
    required String baseUrl,
    required String model,
    String? apiKey,
    String? thinkingLevel,
  }) async {
    final body = <String, dynamic>{
      'baseUrl': baseUrl,
      'model': model,
    };
    if (apiKey != null && apiKey.isNotEmpty) {
      body['apiKey'] = apiKey;
    }
    if (thinkingLevel != null && thinkingLevel.isNotEmpty) {
      body['thinkingLevel'] = thinkingLevel;
    }
    llm = await api.putLlm(body);
    notifyListeners();
  }

  @override
  void dispose() {
    disposeAgentChat();
    api.dispose();
    super.dispose();
  }

}
