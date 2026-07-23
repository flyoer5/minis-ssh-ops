import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';

class AgentSession {
  AgentSession({required this.id, required this.title, required this.hostId, List<ChatMessage>? messages})
      : messages = messages ?? <ChatMessage>[],
        updatedAt = DateTime.now();

  String id;
  String title;
  String? hostId;
  final List<ChatMessage> messages;
  DateTime updatedAt;
}

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  bool backendOk = false;
  bool startingBackend = false;
  String? backendError;
  String? backendNote;
  List<dynamic> hosts = [];
  Map<String, dynamic>? llm;
  String? selectedHostId;
  String lastExecOutput = '';

  // --- Agent chat ---
  Map<String, dynamic>? lastPlan;
  String? agentSessionId;
  final Map<String, String> stepOutputs = {};
  final List<ChatMessage> agentMessages = [];
  /// Index of last plan message in agentMessages (for attaching step outputs).
  int? _lastPlanMsgIndex;
  final List<AgentSession> agentSessions = [];
  bool agentBusy = false;

  // --- Terminal ---
  final StringBuffer _termBuf = StringBuffer();
  final List<String> terminalHistory = [];
  static const int _maxHist = 100;
  static const int _maxTermChars = 120000;

  String get terminalBuffer => _termBuf.toString();

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

  List<AgentSession> sessionsForHost(String? hostId, {bool onlyCurrent = true}) {
    if (!onlyCurrent || hostId == null) return List.from(agentSessions);
    return agentSessions.where((s) => s.hostId == null || s.hostId == hostId).toList();
  }

  String get terminalPrompt {
    if (selectedHostId == null) return 'ssh> ';
    for (final h in hosts) {
      if (h is Map && h['id'] == selectedHostId) {
        final user = h['username'] ?? 'user';
        final host = (h['host'] as String?) ?? 'host';
        final short = host.contains('.') ? host.split('.').first : host;
        return '$user@$short:~\$ ';
      }
    }
    return 'ssh> ';
  }

  List<dynamic> audit = [];

  // --- Probe cache (hostId -> summary json + epoch ms) ---
  final Map<String, Map<String, dynamic>> probeCache = {};
  // --- UI prefs ---
  double termFontSize = 13;
  bool confirmWrites = false; // reserved; agent auto-runs non-blocked
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
    termFontSize = prefs.getDouble('termFontSize') ?? 13;
    selectedHostId = prefs.getString('selectedHostId') ?? selectedHostId;
    onboarded = prefs.getBool('onboarded') ?? false;
    confirmWrites = prefs.getBool('confirmWrites') ?? false;
    _loadSessionsFromPrefs(prefs);

    if (NativeBackend.isAndroidNative) {
      Object? lastErr;
      for (var i = 0; i < 3; i++) {
        try {
          final info = await NativeBackend.ensureStarted();
          if (info != null) {
            final base = (info['baseUrl'] as String?) ?? api.baseUrl;
            final tok = (info['token'] as String?) ?? '';
            api.baseUrl = base;
            if (tok.isNotEmpty) api.localToken = tok;
            await prefs.setString('baseUrl', api.baseUrl);
            await prefs.setString('localToken', api.localToken);
            backendNote = info['alreadyRunning'] == true ? '本机 Go 已在运行' : '已启动内置 Go 后端';
            lastErr = null;
            break;
          }
        } catch (e) {
          lastErr = e;
          backendNote = '启动后端重试 ${i + 1}/3…';
          notifyListeners();
          await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
        }
      }
      if (lastErr != null) {
        backendError = '启动内置后端失败: $lastErr';
      }
    }

    for (var i = 0; i < 8; i++) {
      await refreshHealth();
      if (backendOk) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    startingBackend = false;
    if (backendOk) {
      try {
        await refreshHosts();
        await refreshLlm();
        await refreshAudit();
      } catch (e) {
        backendError = '加载数据失败: $e';
      }
    }
    try {
      batteryIgnored = await NativeBackend.isIgnoringBatteryOptimizations();
    } catch (_) {}
    bootstrapped = true;
    notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('localToken', token);
    api.baseUrl = baseUrl;
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
    } catch (e) {
      backendOk = false;
      backendError = e.toString();
    }
    notifyListeners();
  }

  Future<void> refreshHosts() async {
    hosts = await api.listHosts();
    if (selectedHostId == null && hosts.isNotEmpty) {
      selectedHostId = hosts.first['id'] as String?;
    }
    notifyListeners();
  }

  Future<void> refreshLlm() async {
    llm = await api.getLlm();
    notifyListeners();
  }

  Future<void> refreshAudit() async {
    audit = await api.listAudit();
    notifyListeners();
  }

  Future<void> addHost(Map<String, dynamic> body) async {
    await api.createHost(body);
    await refreshHosts();
  }

  Future<void> removeHost(String id) async {
    await api.deleteHost(id);
    if (selectedHostId == id) selectedHostId = null;
    await refreshHosts();
  }

  Future<void> updateHost(String id, Map<String, dynamic> body) async {
    await api.updateHost(id, body);
    await refreshHosts();
  }

  void selectHost(String? id) {
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

  Future<void> setTermFontSize(double v) async {
    termFontSize = v.clamp(10, 22);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('termFontSize', termFontSize);
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

  void putProbeCache(String hostId, ProbeSummary s) {
    probeCache[hostId] = {
      'ok': s.ok,
      'oneLine': s.oneLine,
      'detail': s.detail,
      'lines': [for (final l in s.lines) {'label': l.label, 'value': l.value}],
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    notifyListeners();
  }

  ProbeSummary? getProbeCache(String hostId, {Duration maxAge = const Duration(minutes: 2)}) {
    final m = probeCache[hostId];
    if (m == null) return null;
    final at = m['at'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds) return null;
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

  void setLastExecOutput(String text) {
    lastExecOutput = text;
    notifyListeners();
  }

  // ---------- Terminal ----------

  void clearTerminal() {
    _termBuf.clear();
    notifyListeners();
  }

  void appendTerminal(String text, {bool dim = false, bool error = false}) {
    // dim/error only used by UI via prefixes if needed; keep plain for copy
    _termBuf.write(text);
    _trimTerm();
    notifyListeners();
  }

  void _trimTerm() {
    final s = _termBuf.toString();
    if (s.length > _maxTermChars) {
      _termBuf.clear();
      _termBuf.write(s.substring(s.length - (_maxTermChars ~/ 2)));
    }
  }

  Future<Map<String, dynamic>> runTerminal(String command, {bool confirmed = false}) async {
    final id = selectedHostId;
    if (id == null) {
      throw StateError('no host');
    }
    if (terminalHistory.isEmpty || terminalHistory.last != command) {
      terminalHistory.add(command);
      if (terminalHistory.length > _maxHist) {
        terminalHistory.removeAt(0);
      }
    }
    _termBuf.writeln('$terminalPrompt$command');
    notifyListeners();

    final res = await api.exec(id, command, confirmed: confirmed, sessionId: 'terminal');
    final out = StringBuffer();
    final stdout = (res['stdout'] ?? '').toString();
    final stderr = (res['stderr'] ?? '').toString();
    // Real SSH feel: print stdout/stderr only; no risk/meta spam.
    if (stdout.isNotEmpty) {
      out.write(stdout.endsWith('\n') ? stdout : '$stdout\n');
    }
    if (stderr.isNotEmpty) {
      out.write(stderr.endsWith('\n') ? stderr : '$stderr\n');
    }
    final exit = res['exitCode'];
    if (exit is int && exit != 0 && stdout.isEmpty && stderr.isEmpty) {
      out.writeln('exit $exit');
    }
    _termBuf.write(out);
    lastExecOutput = out.toString();
    _trimTerm();
    notifyListeners();
    return res;
  }

  // ---------- Agent chat ----------

  void clearAgentChat() {
    // Archive current transcript if non-empty
    if (agentMessages.isNotEmpty) {
      final title = _sessionTitleFromMessages(agentMessages);
      agentSessions.insert(
        0,
        AgentSession(
          id: agentSessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          hostId: selectedHostId,
          messages: List<ChatMessage>.from(agentMessages),
        ),
      );
      if (agentSessions.length > 30) {
        agentSessions.removeRange(30, agentSessions.length);
      }
    }
    agentMessages.clear();
    lastPlan = null;
    stepOutputs.clear();
    agentSessionId = null;
    _lastPlanMsgIndex = null;
    notifyListeners();
    _saveSessionsToPrefs();
  }

  String _sessionTitleFromMessages(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m.role == 'user' && m.content.trim().isNotEmpty) {
        final t = m.content.trim().replaceAll('\n', ' ');
        return t.length > 28 ? '${t.substring(0, 28)}…' : t;
      }
    }
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '会话 $hh:$mm';
  }

  void openAgentSession(AgentSession s) {
    // Save current transcript into sessions if needed
    if (agentMessages.isNotEmpty) {
      final curId = agentSessionId ?? '';
      if (curId != s.id) {
        final existing = agentSessions.indexWhere((e) => e.id == curId);
        final snap = AgentSession(
          id: curId.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : curId,
          title: _sessionTitleFromMessages(agentMessages),
          hostId: selectedHostId,
          messages: List<ChatMessage>.from(agentMessages),
        );
        if (existing >= 0) {
          agentSessions[existing] = snap;
        } else {
          agentSessions.insert(0, snap);
        }
      }
    }
    agentMessages
      ..clear()
      ..addAll(s.messages);
    agentSessionId = s.id;
    if (s.hostId != null) selectedHostId = s.hostId;
    lastPlan = null;
    stepOutputs.clear();
    _lastPlanMsgIndex = null;
    notifyListeners();
    _saveSessionsToPrefs();
  }

  void deleteAgentSession(String id) {
    agentSessions.removeWhere((e) => e.id == id);
    notifyListeners();
    _saveSessionsToPrefs();
  }

  void cancelAgentChat() {
    api.cancelAgentStream();
    agentBusy = false;
    _pushMsg(ChatMessage(role: 'assistant', content: '已取消', kind: ChatKind.status));
    notifyListeners();
  }


  void _loadSessionsFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString('agentSessionsJson');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      agentSessions.clear();
      for (final e in list) {
        if (e is! Map) continue;
        final msgs = <ChatMessage>[];
        final ml = e['messages'];
        if (ml is List) {
          for (final m in ml) {
            if (m is! Map) continue;
            final kindStr = m['kind']?.toString() ?? 'text';
            var kind = ChatKind.text;
            for (final k in ChatKind.values) {
              if (k.name == kindStr) kind = k;
            }
            msgs.add(ChatMessage(
              role: m['role']?.toString() ?? 'assistant',
              content: m['content']?.toString() ?? '',
              kind: kind,
            ));
          }
        }
        agentSessions.add(AgentSession(
          id: e['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: e['title']?.toString() ?? '会话',
          hostId: e['hostId']?.toString(),
          messages: msgs,
        ));
      }
    } catch (_) {}
  }

  Future<void> _saveSessionsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = <Map<String, dynamic>>[];
    for (final s in agentSessions.take(20)) {
      list.add({
        'id': s.id,
        'title': s.title,
        'hostId': s.hostId,
        'messages': [
          for (final m in s.messages.take(80))
            {'role': m.role, 'content': m.content, 'kind': m.kind.name},
        ],
      });
    }
    await prefs.setString('agentSessionsJson', jsonEncode(list));
  }

  Future<void> setConfirmWrites(bool v) async {
    confirmWrites = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirmWrites', v);
    notifyListeners();
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
      'prefs': {
        'termFontSize': termFontSize,
        'confirmWrites': confirmWrites,
      },
      'note': includeSecrets
          ? 'secrets not exported via this path'
          : 'passwords/keys not included',
    };
    return const JsonEncoder.withIndent('  ').convert(obj);
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
      if (pr['termFontSize'] is num) {
        await setTermFontSize((pr['termFontSize'] as num).toDouble());
      }
      if (pr['confirmWrites'] is bool) {
        await setConfirmWrites(pr['confirmWrites'] as bool);
      }
    }
    await refreshHosts();
    await refreshLlm();
    return '导入主机 +$added';
  }


  void _pushMsg(ChatMessage m) {
    agentMessages.add(m);
    notifyListeners();
  }

  Future<void> agentChat(String userText) async {
    final id = selectedHostId;
    if (id == null) {
      _pushMsg(ChatMessage(role: 'assistant', content: '先选主机', kind: ChatKind.error));
      return;
    }
    if (agentBusy) {
      _pushMsg(ChatMessage(role: 'assistant', content: '上一轮还在进行，可点取消', kind: ChatKind.status));
      return;
    }
    agentBusy = true;
    _pushMsg(ChatMessage(role: 'user', content: userText));
    notifyListeners();
    try {
      // Prefer SSE progressive events; fall back to batch chat.
      try {
        await api.agentChatStream(
          hostId: id,
          message: userText,
          sessionId: agentSessionId,
          confirmWrites: confirmWrites,
          onEvent: (raw) {
            final type = raw['type']?.toString() ?? '';
            if (type == 'session') {
              agentSessionId = raw['sessionId'] as String? ?? agentSessionId;
              return;
            }
            if (type == 'done') return;
            _ingestAgentEvent(raw);
            notifyListeners();
          },
        );
      } catch (_) {
        final res = await api.agentChat(hostId: id, message: userText, sessionId: agentSessionId, confirmWrites: confirmWrites);
        agentSessionId = res['sessionId'] as String? ?? agentSessionId;
        for (final raw in (res['events'] as List?) ?? []) {
          if (raw is Map) _ingestAgentEvent(Map<String, dynamic>.from(raw));
        }
      }
      notifyListeners();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ClientException') || msg.contains('Connection closed') || msg.contains('Cancel')) {
        // cancelled stream
      } else {
        _pushMsg(ChatMessage(role: 'assistant', content: _friendlyErr(e), kind: ChatKind.error));
      }
    } finally {
      agentBusy = false;
      notifyListeners();
    }
  }

  void _ingestAgentEvent(Map<String, dynamic> raw) {
    final type = raw['type']?.toString() ?? '';
    final content = (raw['content'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    final command = (raw['command'] ?? '').toString();
    if (type == 'assistant' && content.isNotEmpty) {
      _pushMsg(ChatMessage(role: 'assistant', content: content, kind: ChatKind.text));
    } else if (type == 'tool') {
      final label = command.isNotEmpty ? (r'$ ' + command) : name;
      _pushMsg(ChatMessage(
        role: 'tool',
        content: label,
        kind: ChatKind.status,
        meta: {'name': name, 'command': command},
      ));
    } else if (type == 'tool_result') {
      if (content.startsWith('error: NEEDS_CONFIRM:') || content.startsWith('NEEDS_CONFIRM:')) {
        final rest = content.replaceFirst('error: ', '').replaceFirst('NEEDS_CONFIRM:', '');
        // risk:cmd
        final colon = rest.indexOf(':');
        final risk = colon > 0 ? rest.substring(0, colon) : 'write';
        final cmd = colon > 0 ? rest.substring(colon + 1) : rest;
        final step = {
          'id': (lastPlan == null ? 1 : (((lastPlan!['steps'] as List?)?.length ?? 0) + 1)),
          'title': '需确认',
          'command': cmd,
          'risk': risk,
        };
        final steps = <Map<String, dynamic>>[step];
        if (lastPlan != null && lastPlan!['steps'] is List) {
          steps.insertAll(0, [for (final e in (lastPlan!['steps'] as List)) if (e is Map) Map<String, dynamic>.from(e)]);
        }
        lastPlan = {'summary': '待确认', 'steps': steps};
        agentMessages.add(ChatMessage(
          role: 'assistant',
          content: '待确认',
          kind: ChatKind.plan,
          meta: {'plan': lastPlan, 'outputs': <String, String>{}},
        ));
        _lastPlanMsgIndex = agentMessages.length - 1;
        return;
      }
      final head = command.isNotEmpty ? (r'$ ' + command + '\n') : (name.isNotEmpty ? (name + '\n') : '');
      _pushMsg(ChatMessage(
        role: 'tool',
        content: head + content,
        kind: ChatKind.stepResult,
        meta: {'name': name, 'command': command},
      ));
    } else if (type == 'final' && content.isNotEmpty) {
      _pushMsg(ChatMessage(role: 'assistant', content: content, kind: ChatKind.text));
    } else if (type == 'error' && content.isNotEmpty) {
      _pushMsg(ChatMessage(role: 'assistant', content: content, kind: ChatKind.error));
    }
  }

  Future<void> runAgentPlan(String goal) => agentChat(goal);

  Future<void> runAgentStep({
    required int stepId,
    required String command,
    required bool confirmed,
  }) async {
    final id = selectedHostId;
    if (id == null) return;
    try {
      final res = await api.agentExecStep(
        hostId: id,
        command: command,
        confirmed: true, // explicit UI Run always confirms
        sessionId: agentSessionId ?? 'agent',
        stepId: stepId,
      );
      final out = '${res['stdout'] ?? ''}${res['stderr'] ?? ''}'.trim();
      final block = out.isEmpty ? '(exit ${res['exitCode']})' : out;
      stepOutputs['step_$stepId'] = block;
      // attach to last plan message outputs map for rssh-style cards
      final idx = _lastPlanMsgIndex;
      if (idx != null && idx >= 0 && idx < agentMessages.length) {
        final m = agentMessages[idx];
        final meta = Map<String, dynamic>.from(m.meta ?? {});
        final outputs = Map<String, String>.from(
          (meta['outputs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
        );
        outputs['step_$stepId'] = block;
        meta['outputs'] = outputs;
        agentMessages[idx] = ChatMessage(
          role: m.role,
          content: m.content,
          kind: m.kind,
          meta: meta,
          at: m.at,
        );
      }
      notifyListeners();
    } on ApiException catch (e) {
      final msg = e.status == 403 ? 'blocked' : e.message;
      stepOutputs['step_$stepId'] = msg;
      final idx = _lastPlanMsgIndex;
      if (idx != null && idx >= 0 && idx < agentMessages.length) {
        final m = agentMessages[idx];
        final meta = Map<String, dynamic>.from(m.meta ?? {});
        final outputs = Map<String, String>.from(
          (meta['outputs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
        );
        outputs['step_$stepId'] = msg;
        meta['outputs'] = outputs;
        agentMessages[idx] = ChatMessage(
          role: m.role,
          content: m.content,
          kind: m.kind,
          meta: meta,
          at: m.at,
        );
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> runAllReadSteps() async {
    // rssh-style: never auto-run; user presses 运行 on each card.
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

  Future<void> runExec(String command, {bool confirmed = false}) async {
    final id = selectedHostId;
    if (id == null) {
      setLastExecOutput('请先选择主机');
      return;
    }
    try {
      final res = await api.exec(id, command, confirmed: confirmed);
      setLastExecOutput(
        'risk=${res['risk']} exit=${res['exitCode']} (${res['durationMs']}ms)\n'
        '${res['stdout'] ?? ''}${res['stderr'] ?? ''}',
      );
    } on ApiException catch (e) {
      if (e.status == 409) {
        setLastExecOutput('需要确认后执行（risk=${e.body?['risk']}）\n命令: $command\n请点「确认并执行」');
      } else {
        setLastExecOutput('$e');
      }
      rethrow;
    } catch (e) {
      setLastExecOutput('$e');
      rethrow;
    }
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
      lastExecOutput = summary.detail.isEmpty
          ? summary.oneLine
          : (summary.oneLine + '\n\n' + summary.detail);
      notifyListeners();
      return summary;
    } catch (e) {
      lastExecOutput = '探测失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveLlm({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    final body = <String, dynamic>{
      'baseUrl': baseUrl,
      'model': model,
    };
    if (apiKey != null && apiKey.isNotEmpty) {
      body['apiKey'] = apiKey;
    }
    llm = await api.putLlm(body);
    notifyListeners();
  }
}

class JsonEncoder {
  final String? indent;
  const JsonEncoder.withIndent(this.indent);
  String convert(Object? value) => _enc(value, 0);

  String _enc(Object? v, int level) {
    final pad = '  ' * level;
    final pad1 = '  ' * (level + 1);
    if (v is Map) {
      if (v.isEmpty) return '{}';
      final b = StringBuffer('{\n');
      final keys = v.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        final k = keys[i];
        b.write('$pad1"$k": ${_enc(v[k], level + 1)}');
        b.write(i == keys.length - 1 ? '\n' : ',\n');
      }
      b.write('$pad}');
      return b.toString();
    }
    if (v is List) {
      if (v.isEmpty) return '[]';
      final b = StringBuffer('[\n');
      for (var i = 0; i < v.length; i++) {
        b.write('$pad1${_enc(v[i], level + 1)}');
        b.write(i == v.length - 1 ? '\n' : ',\n');
      }
      b.write('$pad]');
      return b.toString();
    }
    if (v is String) return '"${v.replaceAll('"', '\\"')}"';
    return '$v';
  }
}


  String _friendlyErr(Object e) {
    final s = e.toString();
    final low = s.toLowerCase();
    if (low.contains('connection abort') || low.contains('connection reset') || low.contains('broken pipe')) {
      return '模型网关连接中断，请重试';
    }
    if (low.contains('timeout') || low.contains('timed out')) {
      return '模型请求超时，请重试';
    }
    if (low.contains('401') || low.contains('403')) {
      return '模型鉴权失败，请检查设置';
    }
    final m = RegExp(r'ApiException\(\d+\):\s*(.*)').firstMatch(s);
    if (m != null) return m.group(1)!;
    return s;
  }

class ProbeLine {
  final String label;
  final String value;
  ProbeLine(this.label, this.value);
}

class ProbeSummary {
  final bool ok;
  final String oneLine;
  final List<ProbeLine> lines;
  final String detail;

  ProbeSummary({
    required this.ok,
    required this.oneLine,
    required this.lines,
    required this.detail,
  });

  factory ProbeSummary.fromProbeJson(Map<String, dynamic> res) {
    String pick(String key) {
      final v = res[key];
      if (v is Map) {
        if (v['error'] != null) return '错误: ${v['error']}';
        final s = (v['stdout'] ?? '').toString().trim();
        final e = (v['stderr'] ?? '').toString().trim();
        if (s.isNotEmpty) return s;
        if (e.isNotEmpty) return e;
        return 'exit ${v['exitCode']}';
      }
      if (v == null) return '-';
      return v.toString();
    }

    String firstLine(String s) {
      final t = s.trim();
      if (t.isEmpty) return '-';
      return t.split('\n').first.trim();
    }

    final uname = pick('uname');
    final uptime = pick('uptime');
    final disk = pick('disk');
    final memory = pick('memory');
    final load = pick('load');

    final hasErr = [uname, uptime, disk, memory, load].any((s) => s.startsWith('错误:'));
    final ok = !hasErr && uname != '-';

    // disk use%
    String diskHint = firstLine(disk);
    final useMatch = RegExp(r'(\d+)%').firstMatch(disk);
    if (useMatch != null) {
      diskHint = '使用 ${useMatch.group(1)}%';
      // try root line
      for (final line in disk.split('\n')) {
        if (line.trim().endsWith(' /') || line.contains(r' /$')) {
          final m = RegExp(r'(\d+)%').firstMatch(line);
          if (m != null) {
            diskHint = '根分区 ${m.group(1)}%';
            break;
          }
        }
      }
    }

    final memLine = firstLine(memory);
    final loadLine = firstLine(load);
    final upLine = firstLine(uptime);
    final one = ok
        ? '${firstLine(uname).length > 48 ? '${firstLine(uname).substring(0, 48)}…' : firstLine(uname)} · $diskHint'
        : '连接或采集失败';

    final lines = <ProbeLine>[
      ProbeLine('系统', firstLine(uname)),
      ProbeLine('运行', upLine),
      ProbeLine('负载', loadLine),
      ProbeLine('磁盘', diskHint),
      ProbeLine('内存', memLine),
    ];

    final detail = StringBuffer()
      ..writeln('uname:\n$uname\n')
      ..writeln('uptime:\n$uptime\n')
      ..writeln('load:\n$load\n')
      ..writeln('disk:\n$disk\n')
      ..writeln('memory:\n$memory\n');

    return ProbeSummary(
      ok: ok,
      oneLine: one,
      lines: lines,
      detail: detail.toString().trim(),
    );
  }
}
