import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  bool backendOk = false;
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
    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('baseUrl') ?? api.baseUrl;
    api.localToken = prefs.getString('localToken') ?? api.localToken;

    if (NativeBackend.isAndroidNative) {
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
        }
      } catch (e) {
        backendError = '启动内置后端失败: $e';
        backendOk = false;
        notifyListeners();
      }
    }

    await refreshHealth();
    if (backendOk) {
      await refreshHosts();
      await refreshLlm();
    }
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
      backendError = null;
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
