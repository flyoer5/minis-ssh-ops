import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';

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

  // --- Terminal ---
  final StringBuffer _termBuf = StringBuffer();
  final List<String> terminalHistory = [];
  static const int _maxHist = 100;
  static const int _maxTermChars = 120000;

  String get terminalBuffer => _termBuf.toString();

  String get hostLabel {
    if (selectedHostId == null) return '未选择主机';
    for (final h in hosts) {
      if (h is Map && h['id'] == selectedHostId) {
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
    return selectedHostId!;
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

  Future<void> bootstrap() async {
    startingBackend = true;
    backendError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('baseUrl') ?? api.baseUrl;
    api.localToken = prefs.getString('localToken') ?? api.localToken;

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
      } catch (e) {
        backendError = '加载数据失败: $e';
      }
    }
    if (_termBuf.isEmpty) {
      _termBuf.writeln('# SSH AI Agent terminal');
      _termBuf.writeln('# type a command and press Enter · clear to reset');
      _termBuf.writeln('');
    }
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

  void selectHost(String? id) {
    selectedHostId = id;
    notifyListeners();
  }

  void setLastExecOutput(String text) {
    lastExecOutput = text;
    notifyListeners();
  }

  // ---------- Terminal ----------

  void clearTerminal() {
    _termBuf.clear();
    _termBuf.writeln('# cleared');
    _termBuf.writeln('');
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
    if (stdout.isNotEmpty) out.write(stdout.endsWith('\n') ? stdout : '$stdout\n');
    if (stderr.isNotEmpty) out.write(stderr.endsWith('\n') ? stderr : '$stderr\n');
    final exit = res['exitCode'];
    final risk = res['risk'];
    if (out.isEmpty) {
      out.writeln('[exit $exit · risk $risk · ${res['durationMs']}ms]');
    } else {
      out.writeln('[exit $exit · risk $risk · ${res['durationMs']}ms]');
    }
    _termBuf.write(out);
    _termBuf.writeln('');
    lastExecOutput = out.toString();
    _trimTerm();
    notifyListeners();
    return res;
  }

  // ---------- Agent chat ----------

  void clearAgentChat() {
    agentMessages.clear();
    lastPlan = null;
    stepOutputs.clear();
    agentSessionId = null;
    _lastPlanMsgIndex = null;
    notifyListeners();
  }

  void _pushMsg(ChatMessage m) {
    agentMessages.add(m);
    notifyListeners();
  }

  Future<void> agentChat(String userText) async {
    final id = selectedHostId;
    if (id == null) {
      _pushMsg(ChatMessage(role: 'system', content: '请先选择主机', kind: ChatKind.error));
      return;
    }
    _pushMsg(ChatMessage(role: 'user', content: userText));
    try {
      final res = await api.agentPlan(hostId: id, goal: userText, sessionId: agentSessionId);
      agentSessionId = res['sessionId'] as String? ?? agentSessionId;
      final planRaw = res['plan'];
      Map<String, dynamic>? plan;
      if (planRaw is Map) {
        plan = Map<String, dynamic>.from(planRaw);
        lastPlan = plan;
      }
      stepOutputs.clear();
      final summary = plan?['summary']?.toString() ?? '已生成计划';
      _pushMsg(ChatMessage(role: 'assistant', content: summary, kind: ChatKind.text));
      if (plan != null) {
        final planMsg = ChatMessage(
          role: 'assistant',
          content: summary,
          kind: ChatKind.plan,
          meta: {'plan': plan, 'outputs': <String, String>{}},
        );
        agentMessages.add(planMsg);
        _lastPlanMsgIndex = agentMessages.length - 1;
        notifyListeners();
      }
    } catch (e) {
      _pushMsg(ChatMessage(role: 'system', content: '规划失败: $e', kind: ChatKind.error));
      rethrow;
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
        confirmed: confirmed,
        sessionId: agentSessionId ?? 'agent',
        stepId: stepId,
      );
      final text =
          'risk=${res['risk']} exit=${res['exitCode']} (${res['durationMs']}ms)\n'
          '${res['stdout'] ?? ''}${res['stderr'] ?? ''}';
      stepOutputs['step_$stepId'] = text;

      // attach to plan message outputs
      final idx = _lastPlanMsgIndex;
      if (idx != null && idx >= 0 && idx < agentMessages.length) {
        final old = agentMessages[idx];
        final meta = Map<String, dynamic>.from(old.meta ?? {});
        final outs = Map<String, dynamic>.from(meta['outputs'] as Map? ?? {});
        outs['step_$stepId'] = text;
        meta['outputs'] = outs;
        agentMessages[idx] = ChatMessage(
          role: old.role,
          content: old.content,
          kind: old.kind,
          meta: meta,
          at: old.at,
        );
      }

      _pushMsg(ChatMessage(
        role: 'tool',
        content: text,
        kind: ChatKind.stepResult,
        meta: {
          'stepId': stepId,
          'command': command,
          'exitCode': res['exitCode'],
          'risk': res['risk'],
        },
      ));
    } on ApiException catch (e) {
      if (e.status == 409) {
        final msg = '需要确认（risk=${e.body?['risk']}）：$command';
        stepOutputs['step_$stepId'] = msg;
        _pushMsg(ChatMessage(role: 'system', content: msg, kind: ChatKind.status));
      } else if (e.status == 403) {
        _pushMsg(ChatMessage(role: 'system', content: 'blocked: ${e.message}', kind: ChatKind.error));
      } else {
        _pushMsg(ChatMessage(role: 'system', content: '$e', kind: ChatKind.error));
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> runAllReadSteps() async {
    final plan = lastPlan;
    if (plan == null) return;
    final steps = (plan['steps'] as List?) ?? [];
    for (final raw in steps) {
      if (raw is! Map) continue;
      final risk = raw['risk']?.toString() ?? 'read';
      if (risk != 'read') continue;
      final id = raw['id'];
      final stepId = id is int ? id : int.tryParse('$id') ?? 0;
      final cmd = raw['command']?.toString() ?? '';
      if (cmd.isEmpty) continue;
      try {
        await runAgentStep(stepId: stepId, command: cmd, confirmed: false);
      } catch (_) {
        // continue others
      }
    }
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
    final id = hostId ?? selectedHostId;
    if (id == null) {
      setLastExecOutput('请先选择主机');
      return;
    }
    try {
      final res = await api.probe(id);
      setLastExecOutput(const JsonEncoder.withIndent('  ').convert(res));
    } catch (e) {
      setLastExecOutput('探测失败: $e');
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
