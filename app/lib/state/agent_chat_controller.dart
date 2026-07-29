import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/agent_session_store.dart';
import 'package:ssh_ai_agent/state/agent_transcript.dart';
import 'package:ssh_ai_agent/state/agent_turn_executor.dart';

part 'agent_chat_controller_helpers.dart';
part 'agent_chat_controller_sessions.dart';
part 'agent_chat_controller_turns.dart';

mixin AgentChatController on ChangeNotifier {
  ApiClient get api;
  String? get selectedHostId;
  set selectedHostId(String? value);
  bool get confirmWrites;
  int get agentMaxRounds;
  double get agentTemperature;
  String get agentCustomPrompt;

  Timer? _streamNotifyTimer;
  bool _streamNotifyPending = false;
  Map<String, dynamic>? lastPlan;
  String? agentSessionId;
  String agentSessionTitle = 'New session';
  int? sessionOvMaxRounds;
  double? sessionOvTemperature;
  int? sessionOvConfirm;
  String? sessionOvPrompt;
  final Map<int, Map<String, dynamic>> stepResults = {};
  final List<ChatMessage> agentMessages = [];
  late final AgentTranscript _transcript = AgentTranscript(agentMessages);
  final AgentTurnExecutor _turnExecutor = AgentTurnExecutor();
  int? _lastPlanMsgIndex;
  final List<AgentSession> agentSessions = [];
  final Set<int> _runningStepIds = {};
  bool agentBusy = false;

  Future<Map<String, dynamic>> runAgentStep({
    required int stepId,
    required String command,
    required bool confirmed,
  }) async {
    final hostId = selectedHostId;
    if (hostId == null) {
      throw StateError('select host first');
    }
    if (_runningStepIds.contains(stepId)) {
      return <String, dynamic>{'ok': true, 'skipped': true};
    }

    _runningStepIds.add(stepId);
    try {
      final res = await api.agentExecStep(
        hostId: hostId,
        command: command,
        confirmed: confirmed,
        sessionId: agentSessionId ?? 'agent',
        stepId: stepId,
      );
      stepResults[stepId] = Map<String, dynamic>.from(res);
      return res;
    } finally {
      _runningStepIds.remove(stepId);
    }
  }

  void setAgentSessionMeta(String id, String title) {
    final sid = id.trim();
    if (sid.isEmpty) return;
    agentSessionId = sid;
    final t = title.trim();
    if (t.isNotEmpty) {
      agentSessionTitle = t;
    }
    notifyListeners();
  }

  List<AgentSession> sessionsForHost(String? hostId, {bool onlyCurrent = true}) {
    if (!onlyCurrent || hostId == null) return List.from(agentSessions);
    return agentSessions.where((s) => s.hostId == null || s.hostId == hostId).toList();
  }
}
