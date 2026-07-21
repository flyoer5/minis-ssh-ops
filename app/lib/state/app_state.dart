import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';

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

  Map<String, dynamic>? lastPlan;
  String? agentSessionId;
  final Map<String, String> stepOutputs = {};
  List<dynamic> audit = [];

  Future<void> bootstrap() async {
    startingBackend = true;
    backendError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('baseUrl') ?? api.baseUrl;
    api.localToken = prefs.getString('localToken') ?? api.localToken;

    if (NativeBackend.isAndroidNative) {
      // Retry native start a few times — Process/SELinux can flake on cold start.
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
            backendNote = info['alreadyRunning'] == true
                ? '本机 Go 已在运行'
                : '已启动内置 Go 后端';
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

    // Health with short retries (backend may still be binding).
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

  Future<void> runAgentPlan(String goal) async {
    final id = selectedHostId;
    if (id == null) {
      setLastExecOutput('请先选择主机');
      return;
    }
    try {
      final res = await api.agentPlan(hostId: id, goal: goal, sessionId: agentSessionId);
      agentSessionId = res['sessionId'] as String? ?? agentSessionId;
      final plan = res['plan'];
      if (plan is Map) {
        lastPlan = Map<String, dynamic>.from(plan);
      } else {
        lastPlan = null;
      }
      stepOutputs.clear();
      setLastExecOutput(lastPlan?['summary']?.toString() ?? '计划已生成');
      notifyListeners();
    } catch (e) {
      lastPlan = null;
      setLastExecOutput('规划失败: $e');
      rethrow;
    }
  }

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
      stepOutputs['step_$stepId'] =
          'risk=${res['risk']} exit=${res['exitCode']}\n${res['stdout'] ?? ''}${res['stderr'] ?? ''}';
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 409) {
        stepOutputs['step_$stepId'] = '需要确认（risk=${e.body?['risk']}），请点「确认执行」';
      } else {
        stepOutputs['step_$stepId'] = '$e';
      }
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

// avoid importing dart:convert at top for encoder used only in probe
class JsonEncoder {
  final String? indent;
  const JsonEncoder.withIndent(this.indent);
  String convert(Object? value) {
    // simple pretty for nested maps/lists
    return _enc(value, 0);
  }

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
