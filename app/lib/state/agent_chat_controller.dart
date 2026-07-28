import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/agent_session_store.dart';
import 'package:ssh_ai_agent/state/agent_transcript.dart';

/// Agent transcript, sessions, SSE coalescing / tool pairing.
/// Mixed into [AppState]; requires [api], [selectedHostId], [confirmWrites], [agentMaxRounds].
mixin AgentChatController on ChangeNotifier {
  ApiClient get api;
  String? get selectedHostId;
  set selectedHostId(String? value);
  bool get confirmWrites;
  int get agentMaxRounds;
  double get agentTemperature;
  String get agentCustomPrompt;

  /// Coalesce high-frequency stream token notifies (~30fps max).
  Timer? _streamNotifyTimer;
  bool _streamNotifyPending = false;
  // --- Agent chat ---
  Map<String, dynamic>? lastPlan;
  String? agentSessionId;
  /// Display title for the open session (Minis-style app bar).
  String agentSessionTitle = '新会话';

  /// Public setter for session id/title from outside the notifier (replaces
  /// the invalid external `state.notifyListeners()` call).
  void setAgentSessionMeta(String id, String title) {
    agentSessionId = id;
    agentSessionTitle = title;
    notifyListeners();
  }
  /// Session-level overrides (null = inherit global UiPrefs).
  int? sessionOvMaxRounds;
  double? sessionOvTemperature;
  /// null inherit; 0 off; 1 on
  int? sessionOvConfirm;
  String? sessionOvPrompt;
  final Map<String, String> stepOutputs = {};
  final List<ChatMessage> agentMessages = [];
  late final AgentTranscript _transcript = AgentTranscript(agentMessages);
  /// Index of last plan message in agentMessages (for attaching step outputs).
  int? _lastPlanMsgIndex;
  final List<AgentSession> agentSessions = [];
  bool agentBusy = false;

  List<AgentSession> sessionsForHost(String? hostId, {bool onlyCurrent = true}) {
    if (!onlyCurrent || hostId == null) return List.from(agentSessions);
    return agentSessions.where((s) => s.hostId == null || s.hostId == hostId).toList();
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
    agentSessionTitle = '新会话';
    sessionOvMaxRounds = null;
    sessionOvTemperature = null;
    sessionOvConfirm = null;
    sessionOvPrompt = null;
    _lastPlanMsgIndex = null;
    _agentCancelRequested = false;
    _runningStepIds.clear();
    agentBusy = false;
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
    agentSessionTitle = s.title.isNotEmpty ? s.title : '会话';
    // Prefer selectHost so selectedHostId is persisted across restarts.
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
    stepOutputs.clear();
    _lastPlanMsgIndex = null;
    _agentCancelRequested = false;
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
    // Save current transcript into sessions if needed (as before)
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
    stepOutputs.clear();
    _lastPlanMsgIndex = null;
    _agentCancelRequested = false;
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
    return '$g\n\n## 本会话附加\n$o';
  }

  Future<void> renameOpenSessionTitle(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    agentSessionTitle = t.length > 48 ? '${t.substring(0, 48)}…' : t;
    notifyListeners();
    final id = agentSessionId;
    if (id == null || id.isEmpty) return;
    try {
      await api.renameAgentSession(id, agentSessionTitle);
    } catch (_) {}
  }

  void deleteAgentSession(String id) {
    agentSessions.removeWhere((e) => e.id == id);
    // If deleting the open session, clear the live transcript
    if (agentSessionId == id) {
      agentMessages.clear();
      agentSessionId = null;
      agentSessionTitle = '新会话';
      sessionOvMaxRounds = null;
      sessionOvTemperature = null;
      sessionOvConfirm = null;
      sessionOvPrompt = null;
      lastPlan = null;
      stepOutputs.clear();
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
    agentSessions[i].title = t.length > 48 ? '${t.substring(0, 48)}…' : t;
    agentSessions[i].updatedAt = DateTime.now();
    notifyListeners();
    _saveSessionsToPrefs();
  }

  /// Set when user hits stop — stream close must NOT fall back to batch chat.
  bool _agentCancelRequested = false;

  /// Bumped on each agentChat / cancel so stale SSE events are ignored.
  int _agentTurnGen = 0;

  /// In-flight manual exec-step ids (prevent double-tap).
  final Set<int> _runningStepIds = {};

  void cancelAgentChat() {
    _agentCancelRequested = true;
    _agentTurnGen++; // invalidate in-flight stream callbacks
    api.cancelAgentStream();
    agentBusy = false;
    _flushStreamNotify();
    // Tag open turn bubbles so UI can show「已中断」on half-finished text/thinking.
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'user') break;
      if (m.kind == ChatKind.toolUse && m.meta?['success'] == null && m.meta?['pendingConfirm'] != true) {
        final meta = <String, dynamic>{
          if (m.meta != null) ...m.meta!,
          'success': false,
          'interrupted': true,
          'output': '已中断',
        };
        agentMessages[i] = ChatMessage(
          role: m.role,
          content: '已中断',
          kind: m.kind,
          meta: meta,
          at: m.at,
        );
        continue;
      }
      if (m.kind == ChatKind.text || m.kind == ChatKind.reasoning) {
        final meta = <String, dynamic>{
          if (m.meta != null) ...m.meta!,
          'interrupted': true,
        };
        // Seal stream draft so it won't keep looking "live"
        if (meta['part']?.toString() == 'text_delta') meta['part'] = 'text';
        agentMessages[i] = ChatMessage(
          role: m.role,
          content: m.content,
          kind: m.kind,
          meta: meta,
          at: m.at,
        );
      }
    }
    final already = agentMessages.isNotEmpty &&
        agentMessages.last.kind == ChatKind.status &&
        (agentMessages.last.content == '已停止生成' || agentMessages.last.content == '已取消');
    if (!already) {
      _pushMsg(ChatMessage(
        role: 'assistant',
        content: '已停止生成',
        kind: ChatKind.status,
        meta: {'interrupted': true},
      ));
    }
    notifyListeners();
  }


  void loadAgentSessionsFromPrefs(SharedPreferences prefs) {
    final loaded = AgentSessionStore.load(prefs);
    if (loaded.isEmpty) return;
    agentSessions
      ..clear()
      ..addAll(loaded);
  }

  Future<void> _saveSessionsToPrefs() => AgentSessionStore.save(agentSessions);


  // exportConfigJson / importConfigJson live on AppState (hosts/llm/uiPrefs).

  String _friendlyErr(Object e) {
    final s = e.toString();
    final low = s.toLowerCase();
    if (low.contains('connection abort') || low.contains('connection reset') || low.contains('broken pipe')) {
      return '模型网关连接中断，请重试';
    }
    if (low.contains('timeout') || low.contains('timed out') || low.contains('deadline exceeded')) {
      if (low.contains('context deadline') || low.contains('ssh') || low.contains('exec')) {
        return '远程命令执行超时（主机负载高或命令过慢）。可重试，或让 Agent 拆成更短的命令。';
      }
      return '请求超时，请重试';
    }
    if (low.contains('401') || low.contains('unauthorized')) {
      return '模型鉴权失败，请检查 API Key';
    }
    if (low.contains('403') || low.contains('forbidden')) {
      return '模型拒绝访问（403），请检查密钥权限或额度';
    }
    if (low.contains('429') || low.contains('rate limit')) {
      return '模型请求过于频繁，请稍后再试';
    }
    if (low.contains('llm not configured') || low.contains('not configured')) {
      return '未配置模型，请到设置里填写';
    }
    if (low.contains('failed host lookup') || low.contains('network is unreachable')) {
      return '网络不可用，请检查连接后重试';
    }
    if (low.contains('lookup ') && (low.contains('connection refused') || low.contains('[::1]:53') || low.contains('127.0.0.1:53'))) {
      return 'DNS 解析失败（本机无可用 DNS）。请更新到最新版，或检查网络后重试。';
    }
    if (low.contains('dial tcp') && low.contains('lookup')) {
      return '无法解析模型地址，请检查 Base URL 与网络';
    }
    if (low.contains('certificate') || low.contains('handshake') || low.contains('x509')) {
      return 'TLS 证书校验失败，请检查 Base URL 是否为 https 且证书有效';
    }
    if (low.contains('502') || low.contains('bad gateway')) {
      // Prefer more specific matches above; generic 502 last.
      if (low.contains('模型请求失败') || low.contains('llm')) {
        final m = RegExp(r'模型请求失败[:：]\s*(.*)').firstMatch(s);
        if (m != null) {
          final body = m.group(1)!.trim();
          if (body.contains('lookup') && body.contains('connection refused')) {
            return 'DNS 解析失败，无法连接模型网关。请重试或检查网络。';
          }
          if (body.length > 160) return '模型网关错误：${body.substring(0, 160)}…';
          return '模型网关错误：$body';
        }
      }
    }
    final m = RegExp(r'ApiException\(\d+\):\s*(.*)').firstMatch(s);
    if (m != null) {
      final body = m.group(1)!.trim();
      if (body.length > 280) return '${body.substring(0, 280)}…';
      return body.isEmpty ? '请求失败' : body;
    }
    if (s.length > 280) return '${s.substring(0, 280)}…';
    return s;
  }

  void _pushMsg(ChatMessage m) {
    _transcript.add(m);
    notifyListeners();
  }

  int _lastReasoningIndexInTurn() => _transcript.lastReasoningIndexInTurn;

  bool _turnHasAssistantText() => _transcript.turnHasAssistantText;

  void _pushReasoning(String reasoning) => _transcript.pushReasoning(reasoning);

  void _appendAssistantDelta(String piece) => _transcript.appendAssistantDelta(piece);

  void _appendReasoningDelta(String piece) => _transcript.appendReasoningDelta(piece);

  void _coalesceAssistantFull(String content, {String part = 'text'}) {
    _transcript.coalesceAssistantFull(content);
  }

  void _pushOrMergeAssistantText(String content, {String part = 'text'}) {
    _transcript.coalesceAssistantFull(content);
  }

  int _findOpenToolUse({required String name, required String command}) {
    return _transcript.findOpenToolUse(name: name, command: command);
  }

  void _pushToolUse({
    required String name,
    required String command,
    required String description,
  }) {
    _transcript.pushToolUse(name: name, command: command, description: description);
  }

  void _completeToolResult({
    required String name,
    required String command,
    required String output,
    required bool success,
    required String description,
  }) {
    _transcript.completeToolResult(
      name: name,
      command: command,
      output: output,
      success: success,
      description: description,
    );
  }

  void _scheduleStreamNotify() {
    _streamNotifyPending = true;
    if (_streamNotifyTimer?.isActive == true) return;
    // ~20fps is enough for token paint; lower = less jank on mid-range phones when
    // other tabs still listen to AppState (IndexedStack keepAlive).
    _streamNotifyTimer = Timer(const Duration(milliseconds: 80), () {
      if (!_streamNotifyPending) return;
      _streamNotifyPending = false;
      notifyListeners();
    });
  }

  void _flushStreamNotify() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
    if (_streamNotifyPending) {
      _streamNotifyPending = false;
      notifyListeners();
    }
  }

  Future<void> agentChat(String userText) async {
    final id = selectedHostId;
    if (id == null) {
      _pushMsg(ChatMessage(role: 'assistant', content: '先选主机', kind: ChatKind.error));
      return;
    }
    if (agentBusy) {
      _pushMsg(ChatMessage(role: 'assistant', content: '上一轮还在进行，可点停止', kind: ChatKind.status));
      return;
    }
    agentBusy = true;
    _agentCancelRequested = false;
    final turn = ++_agentTurnGen;
    // Always have a durable server session before the turn (Minis-style).
    if (agentSessionId == null || agentSessionId!.isEmpty) {
      try {
        final r = await api.createAgentSession(hostId: id, title: userText.trim());
        final sid = (r['sessionId'] ?? r['id'] ?? '').toString();
        if (sid.isNotEmpty) agentSessionId = sid;
      } catch (_) {
        // Backend will still mint a UUID if sessionId is omitted.
      }
    }
    _pushMsg(ChatMessage(role: 'user', content: userText));
    if (agentSessionTitle == '新会话' || agentSessionTitle.isEmpty) {
      final t = userText.trim().replaceAll(RegExp(r'\s+'), ' ');
      agentSessionTitle = t.length > 32 ? '${t.substring(0, 32)}…' : t;
    }
    notifyListeners();
    try {
      // Prefer SSE progressive events; fall back to batch chat only on real errors.
      try {
        await api.agentChatStream(
          hostId: id,
          message: userText,
          sessionId: agentSessionId,
          confirmWrites: effectiveConfirmWrites,
          maxRounds: effectiveMaxRounds,
          temperature: effectiveTemperature,
          customPrompt: effectiveCustomPrompt,
          onEvent: (raw) {
            if (turn != _agentTurnGen) return;
            final type = raw['type']?.toString() ?? '';
            if (type == 'session') {
              agentSessionId = raw['sessionId'] as String? ?? agentSessionId;
              return;
            }
            if (type == 'done') return;
            _ingestAgentEvent(raw);
            // Token deltas: throttle UI rebuilds. Structural events: flush now.
            if (type == 'assistant_delta' || type == 'reasoning_delta') {
              _scheduleStreamNotify();
            } else {
              _flushStreamNotify();
              notifyListeners();
            }
          },
        );
      } catch (e) {
        // User stop closes the HTTP client — never re-run the whole turn via batch.
        if (turn != _agentTurnGen || _agentCancelRequested || _isCancelError(e)) {
          // already tagged by cancelAgentChat / superseded
        } else {
          final res = await api.agentChat(
            hostId: id,
            message: userText,
            sessionId: agentSessionId,
            confirmWrites: effectiveConfirmWrites,
            maxRounds: effectiveMaxRounds,
            temperature: effectiveTemperature,
            customPrompt: effectiveCustomPrompt,
          );
          if (turn != _agentTurnGen) return;
          agentSessionId = res['sessionId'] as String? ?? agentSessionId;
          for (final raw in (res['events'] as List?) ?? []) {
            if (raw is Map) _ingestAgentEvent(Map<String, dynamic>.from(raw));
          }
        }
      }
      if (turn == _agentTurnGen) {
        _flushStreamNotify();
        notifyListeners();
      }
    } catch (e) {
      if (turn != _agentTurnGen || _agentCancelRequested || _isCancelError(e)) {
        // cancelled / superseded
      } else {
        _pushMsg(ChatMessage(role: 'assistant', content: _friendlyErr(e), kind: ChatKind.error));
      }
    } finally {
      if (turn == _agentTurnGen) {
        agentBusy = false;
        _agentCancelRequested = false;
        _flushStreamNotify();
        notifyListeners();
      }
    }
  }

  bool _isCancelError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('clientexception') ||
        msg.contains('connection closed') ||
        msg.contains('cancel') ||
        msg.contains('broken pipe') ||
        msg.contains('connection reset') ||
        msg.contains('stream closed') ||
        msg.contains('socketexception');
  }


  void _ingestAgentEvent(Map<String, dynamic> raw) {
    final type = raw['type']?.toString() ?? '';
    final content = (raw['content'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    final command = (raw['command'] ?? '').toString();
    // Keep raw reasoning for deltas — a token may be only " " (leading space).
    final reasoningRaw = (raw['reasoning'] ?? '').toString();
    final reasoning = reasoningRaw.trim();
    if (type == 'memory') {
      // optional silent update; show short status once
      final facts = (raw['facts'] ?? '').toString().trim();
      final note = content.trim().isEmpty ? '长期记忆已更新' : '长期记忆已更新';
      if (facts.isNotEmpty || content.trim().isNotEmpty) {
        _pushMsg(ChatMessage(role: 'system', content: note, kind: ChatKind.status));
      }
    } else if (type == 'reasoning_delta' && (reasoningRaw.isNotEmpty || content.isNotEmpty)) {
      // Prefer content field, else untrimmed reasoning (preserve spaces)
      final piece = content.isNotEmpty ? content : reasoningRaw;
      _appendReasoningDelta(piece);
    } else if (type == 'assistant_delta' && content.isNotEmpty) {
      // Token stream: append into open assistant text bubble
      _appendAssistantDelta(content);
    } else if (type == 'reasoning' && (reasoning.isNotEmpty || content.trim().isNotEmpty)) {
      // Full reasoning (non-stream or end-of-turn). Prefer replacing streamed draft if identical prefix.
      _pushReasoning(reasoning.isNotEmpty ? reasoning : content);
    } else if (type == 'assistant' && (content.isNotEmpty || reasoning.isNotEmpty)) {
      if (reasoning.isNotEmpty) _pushReasoning(reasoning);
      if (content.isNotEmpty) {
        _pushOrMergeAssistantText(content, part: 'text');
      }
    } else if (type == 'tool') {
      // Minis toolUse — one open card; later tool_result completes same card
      String title;
      if (name == 'probe_host') {
        title = '探测主机状态';
      } else if (command.isNotEmpty) {
        final one = command.trim().split('\n').first;
        title = one.length > 80 ? '${one.substring(0, 80)}…' : one;
      } else if (name.isNotEmpty) {
        title = name;
      } else {
        title = 'tool';
      }
      final toolName = name.isEmpty ? (command.isEmpty ? 'tool' : 'run_command') : name;
      // If same toolUse already open (duplicate SSE), don't stack another
      final open = _findOpenToolUse(name: toolName, command: command);
      if (open >= 0) {
        final m = agentMessages[open];
        agentMessages[open] = ChatMessage(
          role: 'tool',
          content: title,
          kind: ChatKind.status,
          meta: {
            ...?m.meta,
            'part': 'toolUse',
            'name': toolName,
            'command': command.isNotEmpty ? command : (m.meta?['command'] ?? ''),
            'description': title,
            'success': null,
          },
          at: m.at,
        );
        return;
      }
      _pushToolUse(name: toolName, command: command, description: title);
    } else if (type == 'tool_result') {
      // Minis toolResult — complete matching toolUse (stream merge)
      if (content.startsWith('error: NEEDS_CONFIRM:') || content.startsWith('NEEDS_CONFIRM:')) {
        final rest = content.replaceFirst('error: ', '').replaceFirst('NEEDS_CONFIRM:', '');
        final colon = rest.indexOf(':');
        final risk = colon > 0 ? rest.substring(0, colon) : 'write';
        final cmd = colon > 0 ? rest.substring(colon + 1) : rest;
        final toolName = name.isEmpty ? (command.isEmpty ? 'run_command' : 'run_command') : name;
        final open = _findOpenToolUse(name: toolName, command: command.isNotEmpty ? command : cmd);
        if (open >= 0) {
          final m = agentMessages[open];
          agentMessages[open] = ChatMessage(
            role: 'tool',
            content: '等待确认',
            kind: ChatKind.toolUse,
            meta: {
              ...?m.meta,
              'part': 'toolUse',
              'name': toolName,
              'command': cmd.isNotEmpty ? cmd : (m.meta?['command'] ?? ''),
              'description': '需要确认后执行',
              'success': null,
              'pendingConfirm': true,
              'risk': risk,
            },
            at: m.at,
          );
        }
        // Dedup: if the same command is already pending in last plan, just refresh UI.
        final existingSteps = (lastPlan?['steps'] as List?) ?? const [];
        final already = existingSteps.any((e) {
          if (e is! Map) return false;
          return (e['command']?.toString() ?? '') == cmd;
        });
        if (!already) {
          final step = {
            'id': (lastPlan == null ? 1 : (((lastPlan!['steps'] as List?)?.length ?? 0) + 1)),
            'title': '需确认',
            'command': cmd,
            'risk': risk,
          };
          final steps = <Map<String, dynamic>>[step];
          if (lastPlan != null && lastPlan!['steps'] is List) {
            steps.insertAll(0, [
              for (final e in (lastPlan!['steps'] as List))
                if (e is Map) Map<String, dynamic>.from(e),
            ]);
          }
          lastPlan = {'summary': '待确认', 'steps': steps};
          // Replace previous open plan card if still empty, else append.
          final idx = _lastPlanMsgIndex;
          final planMsg = ChatMessage(
            role: 'assistant',
            content: '待确认',
            kind: ChatKind.plan,
            meta: {'plan': lastPlan, 'outputs': <String, String>{}},
          );
          final canReplace = idx != null &&
              idx >= 0 &&
              idx < agentMessages.length &&
              agentMessages[idx].kind == ChatKind.plan &&
              ((agentMessages[idx].meta?['outputs'] as Map?)?.isEmpty ?? true);
          if (canReplace) {
            agentMessages[idx] = planMsg;
          } else {
            agentMessages.add(planMsg);
            _lastPlanMsgIndex = agentMessages.length - 1;
          }
        }
        return;
      }
      final toolName = name.isEmpty ? (command.isEmpty ? 'tool' : 'run_command') : name;
      final failed = content.startsWith('error:') ||
          content.contains('Command timed out') ||
          (content.contains('(exit code') && !RegExp(r'\(exit code 0\)').hasMatch(content));
      final desc = command.isNotEmpty
          ? (command.trim().split('\n').first.length > 80
              ? '${command.trim().split('\n').first.substring(0, 80)}…'
              : command.trim().split('\n').first)
          : toolName;
      _completeToolResult(
        name: toolName,
        command: command,
        output: content,
        success: !failed,
        description: desc,
      );
    } else if (type == 'final' && (content.isNotEmpty || reasoning.isNotEmpty)) {
      // final often re-sends full reasoning after deltas + answer already rendered.
      // Coalesce only — never stack a second thinking card under the reply.
      if (reasoning.isNotEmpty) {
        final ri = _lastReasoningIndexInTurn();
        if (ri >= 0) {
          // Prefer replacing stream draft with final (usually better spaced).
          _pushReasoning(reasoning);
        } else if (!_turnHasAssistantText()) {
          _pushReasoning(reasoning);
        } else {
          // Answer already shown and no prior reasoning bubble — put above answer once.
          _pushReasoning(reasoning);
        }
      }
      if (content.isNotEmpty) {
        // Stream already drew the bubble via assistant_delta; final must not spawn a second one.
        _coalesceAssistantFull(content, part: 'text');
      }
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
    if (_runningStepIds.contains(stepId)) return;
    // Already have output for this step (e.g. double-tap after success).
    if ((stepOutputs['step_$stepId'] ?? '').isNotEmpty) return;
    _runningStepIds.add(stepId);
    notifyListeners();
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
      _sealPendingToolUse(command, success: true, output: block);
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
      final msg = e.status == 403 ? '已拦截' : e.message;
      stepOutputs['step_$stepId'] = msg;
      _sealPendingToolUse(command, success: false, output: msg);
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
    } finally {
      _runningStepIds.remove(stepId);
      notifyListeners();
    }
  }

  /// After user confirms exec, close matching pending toolUse cards.
  void _sealPendingToolUse(String command, {required bool success, required String output}) {
    _transcript.sealPendingToolUse(command, success: success, output: output);
  }



  void disposeAgentChat() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }
}
