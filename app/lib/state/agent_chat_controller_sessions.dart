part of 'agent_chat_controller.dart';

extension AgentChatControllerSessions on AgentChatController {
  void clearAgentChat() {
    _supersedeAgentTurn();
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
    stepResults.clear();
    agentSessionId = null;
    agentSessionTitle = '新会话';
    sessionOvMaxRounds = null;
    sessionOvTemperature = null;
    sessionOvConfirm = null;
    sessionOvPrompt = null;
    _lastPlanMsgIndex = null;
    _runningStepIds.clear();
    agentBusy = false;
    notifyListeners();
    _saveSessionsToPrefs();
  }

  String _sessionTitleFromMessages(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m.role == 'user' && m.content.trim().isNotEmpty) {
        final t = m.content.trim().replaceAll('\n', ' ');
        return t.length > 28 ? '${t.substring(0, 28)}...' : t;
      }
    }
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '会话 $hh:$mm';
  }

  void openAgentSession(AgentSession s) {
    _supersedeAgentTurn();
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
    agentSessionTitle = s.title.isNotEmpty ? s.title : '会话';
    if (s.hostId != null && s.hostId != selectedHostId) {
      selectedHostId = s.hostId;
      SharedPreferences.getInstance().then((p) {
        final id = s.hostId;
        if (id == null) {
          p.remove('selectedHostId');
        } else {
          p.setString('selectedHostId', id);
        }
      });
    }
    lastPlan = null;
    stepResults.clear();
    _lastPlanMsgIndex = null;
    _runningStepIds.clear();
    agentBusy = false;
    notifyListeners();
    _saveSessionsToPrefs();
  }

  void openAgentSessionRaw(
    String id,
    List<ChatMessage> msgs, {
    String? title,
    int? ovMaxRounds,
    double? ovTemperature,
    int? ovConfirm,
    String? ovPrompt,
  }) {
    _supersedeAgentTurn();
    if (agentMessages.isNotEmpty) {
      final curId = agentSessionId ?? '';
      if (curId != id) {
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
      ..addAll(msgs);
    agentSessionId = id;
    if (title != null && title.trim().isNotEmpty) {
      agentSessionTitle = title.trim();
    } else if (msgs.isNotEmpty) {
      agentSessionTitle = _sessionTitleFromMessages(msgs);
    } else {
      agentSessionTitle = '会话';
    }
    applySessionOverrides(
      maxRounds: ovMaxRounds,
      temperature: ovTemperature,
      confirm: ovConfirm,
      prompt: ovPrompt,
    );
    lastPlan = null;
    stepResults.clear();
    _lastPlanMsgIndex = null;
    _runningStepIds.clear();
    agentBusy = false;
    notifyListeners();
    _saveSessionsToPrefs();
  }

  void applySessionOverrides({
    int? maxRounds,
    double? temperature,
    int? confirm,
    String? prompt,
    bool clearAll = false,
  }) {
    if (clearAll) {
      sessionOvMaxRounds = null;
      sessionOvTemperature = null;
      sessionOvConfirm = null;
      sessionOvPrompt = null;
    } else {
      sessionOvMaxRounds = maxRounds;
      sessionOvTemperature = temperature;
      sessionOvConfirm = confirm;
      sessionOvPrompt = prompt;
    }
    notifyListeners();
  }

  int get effectiveMaxRounds => sessionOvMaxRounds ?? agentMaxRounds;
  double get effectiveTemperature => sessionOvTemperature ?? agentTemperature;
  bool get effectiveConfirmWrites =>
      sessionOvConfirm == null ? confirmWrites : sessionOvConfirm == 1;
  String get effectiveCustomPrompt {
    final g = agentCustomPrompt;
    final o = sessionOvPrompt;
    if (o == null || o.trim().isEmpty) return g;
    if (g.trim().isEmpty) return o;
    return '$g\n\n## Session note\n$o';
  }

  Future<void> renameOpenSessionTitle(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    agentSessionTitle = t.length > 48 ? '${t.substring(0, 48)}...' : t;
    notifyListeners();
    final id = agentSessionId;
    if (id == null || id.isEmpty) return;
    try {
      await api.renameAgentSession(id, agentSessionTitle);
    } catch (_) {}
  }

  void deleteAgentSession(String id) {
    agentSessions.removeWhere((e) => e.id == id);
    if (agentSessionId == id) {
      _supersedeAgentTurn();
      agentMessages.clear();
      agentSessionId = null;
      agentSessionTitle = '新会话';
      sessionOvMaxRounds = null;
      sessionOvTemperature = null;
      sessionOvConfirm = null;
      sessionOvPrompt = null;
      lastPlan = null;
      stepResults.clear();
      _lastPlanMsgIndex = null;
    }
    notifyListeners();
    _saveSessionsToPrefs();
  }

  void renameAgentSession(String id, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    final i = agentSessions.indexWhere((e) => e.id == id);
    if (i < 0) return;
    agentSessions[i].title = t.length > 48 ? '${t.substring(0, 48)}...' : t;
    agentSessions[i].updatedAt = DateTime.now();
    notifyListeners();
    _saveSessionsToPrefs();
  }
}
