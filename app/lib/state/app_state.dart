import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/backend_url.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/state/agent_chat_controller.dart';
import 'package:ssh_ai_agent/state/host_state.dart';
import 'package:ssh_ai_agent/state/probe_state.dart';
import 'package:ssh_ai_agent/state/ui_prefs.dart';

export 'package:ssh_ai_agent/state/ui_prefs.dart';
export 'package:ssh_ai_agent/state/agent_chat_controller.dart';
export 'package:ssh_ai_agent/models/agent_session.dart';
export 'package:ssh_ai_agent/models/probe_summary.dart';

class AppState extends ChangeNotifier
    with UiPrefs, HostState, ProbeState, AgentChatController {
  AppState(this.api);

  @override
  final ApiClient api;

  bool backendOk = false;
  List<String> backendFeatures = [];
  String? backendVersion;
  bool startingBackend = false;
  String? backendError;
  String? backendNote;
  Map<String, dynamic>? llm;

  List<dynamic> audit = [];

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
            backendNote = info['alreadyRunning'] == true ? 'Backend already running' : 'Started bundled backend';
            lastErr = null;
            break;
          }
        } catch (e) {
          lastErr = e;
          backendNote = 'Starting backend retry ${i + 1}/2';
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

  Future<void> requestBatteryExempt() async {
    await NativeBackend.requestIgnoreBatteryOptimizations();
    batteryIgnored = await NativeBackend.isIgnoringBatteryOptimizations();
    notifyListeners();
  }

  Future<void> openBatterySettings() async {
    await NativeBackend.openBatterySettings();
  }

  Future<String> exportBackendLog() => NativeBackend.exportBackendLog();

  Future<String> testLlmReachable() async {
    // minimal: ensure LLM configured and do a 1-token style agent chat requires host
    final id = selectedHostId;
    if (id == null) throw StateError('Select a host first');
    final res = await api.agentChat(hostId: id, message: '只回复ok两个字母', sessionId: 'ping-${DateTime.now().millisecondsSinceEpoch}');
    return res.toString().length > 20 ? '模型可达' : res.toString();
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
