import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/agent/reasoning_merge.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';

/// Agent transcript, sessions, SSE coalescing / tool pairing.
/// Mixed into [AppState]; requires [api], [selectedHostId], [confirmWrites].
mixin AgentChatController on ChangeNotifier {
  ApiClient get api;
  String? get selectedHostId;
  set selectedHostId(String? value);
  bool get confirmWrites;

  /// Coalesce high-frequency stream token notifies (~30fps max).
  Timer? _streamNotifyTimer;
  bool _streamNotifyPending = false;
  // --- Agent chat ---
  Map<String, dynamic>? lastPlan;
  String? agentSessionId;
  final Map<String, String> stepOutputs = {};
  final List<ChatMessage> agentMessages = [];
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
    // If deleting the open session, clear the live transcript
    if (agentSessionId == id) {
      agentMessages.clear();
      agentSessionId = null;
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

  void cancelAgentChat() {
    api.cancelAgentStream();
    agentBusy = false;
    _flushStreamNotify();
    // Tag open turn bubbles so UI can show「已中断」on half-finished text/thinking.
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'user') break;
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
            Map<String, dynamic>? meta;
            final rawMeta = m['meta'];
            if (rawMeta is Map) meta = Map<String, dynamic>.from(rawMeta);
            // migrate legacy meta.part → first-class kind
            final part = meta?['part']?.toString();
            if (part == 'toolUse' && kind != ChatKind.toolUse) kind = ChatKind.toolUse;
            if ((part == 'toolResult' || kind == ChatKind.stepResult) &&
                kind != ChatKind.toolResult &&
                kind != ChatKind.plan) {
              if (kind == ChatKind.stepResult || part == 'toolResult') kind = ChatKind.toolResult;
            }
            msgs.add(ChatMessage(
              role: m['role']?.toString() ?? 'assistant',
              content: m['content']?.toString() ?? '',
              kind: kind,
              meta: meta,
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
    // Keep SharedPreferences payload bounded (20 sessions × 80 msgs × ~12k chars).
    const maxContent = 12000;
    for (final s in agentSessions.take(20)) {
      list.add({
        'id': s.id,
        'title': s.title,
        'hostId': s.hostId,
        'messages': [
          for (final m in s.messages.take(80))
            {
              'role': m.role,
              'content': m.content.length > maxContent
                  ? '${m.content.substring(0, maxContent)}…'
                  : m.content,
              'kind': m.kind.name,
              if (m.meta != null) 'meta': m.meta,
            },
        ],
      });
    }
    await prefs.setString('agentSessionsJson', jsonEncode(list));
  }


  // exportConfigJson / importConfigJson live on AppState (hosts/llm/uiPrefs).

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

  void _pushMsg(ChatMessage m) {
    agentMessages.add(m);
    notifyListeners();
  }

  /// Index of the latest reasoning bubble in the *current turn* (after last user msg).
  /// Returns -1 if none. Used so final/reasoning never spawns a second block under the answer.
  int _lastReasoningIndexInTurn() {
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'user') break;
      if (m.kind == ChatKind.reasoning) return i;
    }
    return -1;
  }

  /// Whether this turn already has assistant answer text (after last user).
  bool _turnHasAssistantText() {
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'user') break;
      if (m.role == 'assistant' && m.kind == ChatKind.text) return true;
    }
    return false;
  }

  /// Minis-like: reasoning is a foldable block *above* the answer for this turn.
  /// Never append a new thinking card after assistant text (final often re-sends full reasoning).
  void _pushReasoning(String reasoning) {
    final r = reasoning.trim();
    if (r.isEmpty) return;
    final idx = _lastReasoningIndexInTurn();
    if (idx >= 0) {
      final last = agentMessages[idx];
      // Stream (maybe glued) + final (spaced) → ONE card via pure merge helper
      final merged = mergeReasoningForTurn(last.content, r);
      agentMessages[idx] = ChatMessage(
        role: 'assistant',
        content: merged,
        kind: ChatKind.reasoning,
        meta: {'part': 'reasoning'},
        at: last.at,
      );
      return;
    }
    // No reasoning yet this turn.
    // If answer text already exists, do NOT put thinking under the reply —
    // insert just before the first assistant text of this turn, or skip if empty utility.
    if (_turnHasAssistantText()) {
      // Find first assistant text after last user; insert reasoning before it
      var insertAt = agentMessages.length;
      for (var i = agentMessages.length - 1; i >= 0; i--) {
        final m = agentMessages[i];
        if (m.role == 'user') break;
        if (m.role == 'assistant' && m.kind == ChatKind.text) insertAt = i;
      }
      agentMessages.insert(
        insertAt,
        ChatMessage(
          role: 'assistant',
          content: r,
          kind: ChatKind.reasoning,
          meta: {'part': 'reasoning'},
        ),
      );
      return;
    }
    agentMessages.add(ChatMessage(
      role: 'assistant',
      content: r,
      kind: ChatKind.reasoning,
      meta: {'part': 'reasoning'},
    ));
  }

  /// Stable id for pairing toolUse → toolResult across SSE events.
  String _newToolId() => 't${DateTime.now().microsecondsSinceEpoch}';

  /// Stream token: append to last assistant text bubble (or create one).
  void _appendAssistantDelta(String piece) {
    if (piece.isEmpty) return;
    if (agentMessages.isNotEmpty) {
      final last = agentMessages.last;
      final lastPart = last.meta?['part']?.toString();
      final isText = last.role == 'assistant' &&
          last.kind == ChatKind.text &&
          (lastPart == null || lastPart == 'text' || lastPart == 'text_delta');
      if (isText) {
        agentMessages[agentMessages.length - 1] = ChatMessage(
          role: 'assistant',
          content: last.content + piece,
          kind: ChatKind.text,
          meta: {'part': 'text_delta'},
          at: last.at,
        );
        return;
      }
    }
    agentMessages.add(ChatMessage(
      role: 'assistant',
      content: piece,
      kind: ChatKind.text,
      meta: {'part': 'text_delta'},
    ));
  }

  /// Stream token: append into current-turn reasoning bubble (never after answer text).
  void _appendReasoningDelta(String piece) {
    if (piece.isEmpty) return;
    final idx = _lastReasoningIndexInTurn();
    if (idx >= 0) {
      final last = agentMessages[idx];
      agentMessages[idx] = ChatMessage(
        role: 'assistant',
        content: last.content + piece,
        kind: ChatKind.reasoning,
        meta: {'part': 'reasoning'},
        at: last.at,
      );
      return;
    }
    // If answer already started, open/update a reasoning card *above* it
    if (_turnHasAssistantText()) {
      var insertAt = agentMessages.length;
      for (var i = agentMessages.length - 1; i >= 0; i--) {
        final m = agentMessages[i];
        if (m.role == 'user') break;
        if (m.role == 'assistant' && m.kind == ChatKind.text) insertAt = i;
      }
      agentMessages.insert(
        insertAt,
        ChatMessage(
          role: 'assistant',
          content: piece,
          kind: ChatKind.reasoning,
          meta: {'part': 'reasoning'},
        ),
      );
      return;
    }
    agentMessages.add(ChatMessage(
      role: 'assistant',
      content: piece,
      kind: ChatKind.reasoning,
      meta: {'part': 'reasoning'},
    ));
  }

  /// Normalize for duplicate detection (stream final vs deltas often differ by WS/newlines).
  String _normText(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Find the latest assistant text bubble (skip trailing status if any).
  int _lastAssistantTextIndex() {
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'assistant' && m.kind == ChatKind.text) return i;
      // stop if we hit user message — different turn
      if (m.role == 'user') break;
      // skip status/reasoning after text (e.g. stop status shouldn't block coalesce)
      if (m.kind == ChatKind.status || m.kind == ChatKind.reasoning) continue;
      break;
    }
    return -1;
  }

  /// After token stream, full assistant/final must REPLACE the draft bubble, not create a second one.
  /// Also seals part from `text_delta` → `text` so UI switches from plain to Markdown once.
  void _coalesceAssistantFull(String content, {String part = 'text'}) {
    final t = content.trimRight();
    if (t.isEmpty) return;
    final idx = _lastAssistantTextIndex();
    if (idx >= 0) {
      final last = agentMessages[idx];
      final a = _normText(last.content);
      final b = _normText(t);
      String body = t;
      // identical / prefix / either contains the other → one bubble
      if (a == b || b.startsWith(a) || a.startsWith(b) || a.contains(b) || b.contains(a)) {
        body = t.length >= last.content.length ? t : last.content;
      }
      agentMessages[idx] = ChatMessage(
        role: 'assistant',
        content: body,
        kind: ChatKind.text,
        meta: {'part': 'text'}, // seal: leave streaming plain-text mode
        at: last.at,
      );
      return;
    }
    agentMessages.add(ChatMessage(
      role: 'assistant',
      content: t,
      kind: ChatKind.text,
      meta: {'part': 'text'},
    ));
  }

  /// Minis-like: consecutive assistant/final text chunks merge into one bubble.
  void _pushOrMergeAssistantText(String content, {String part = 'text'}) {
    // Full-frame events (assistant / final) always coalesce into one bubble.
    _coalesceAssistantFull(content, part: part);
  }

  bool _isOpenToolUse(ChatMessage m) {
    if (m.kind == ChatKind.toolUse) return m.meta?['success'] == null;
    // legacy: meta.part toolUse with status kind
    return m.meta?['part']?.toString() == 'toolUse' && m.meta?['success'] == null;
  }

  /// Find last open toolUse to complete (same name, prefer same command).
  int _findOpenToolUse({required String name, required String command}) {
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (!_isOpenToolUse(m)) continue;
      final n = (m.meta?['name'] ?? '').toString();
      if (name.isNotEmpty && n.isNotEmpty && n != name) continue;
      final c = (m.meta?['command'] ?? '').toString();
      if (command.isNotEmpty && c.isNotEmpty && c != command) {
        if (c.trim() != command.trim()) continue;
      }
      return i;
    }
    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (!_isOpenToolUse(m)) continue;
      final n = (m.meta?['name'] ?? '').toString();
      if (name.isEmpty || n == name) return i;
    }
    return -1;
  }

  void _pushToolUse({
    required String name,
    required String command,
    required String description,
  }) {
    final id = _newToolId();
    agentMessages.add(ChatMessage(
      role: 'tool',
      content: description,
      kind: ChatKind.toolUse,
      meta: {
        'part': 'toolUse',
        'id': id,
        'name': name,
        'command': command,
        'description': description,
        'success': null,
      },
    ));
  }

  /// Merge tool_result into the matching toolUse card (Minis stream pairing).
  void _completeToolResult({
    required String name,
    required String command,
    required String output,
    required bool success,
    required String description,
  }) {
    final idx = _findOpenToolUse(name: name, command: command);
    final id = idx >= 0
        ? (agentMessages[idx].meta?['id']?.toString() ?? _newToolId())
        : _newToolId();
    final prev = idx >= 0 ? agentMessages[idx] : null;
    final desc = description.isNotEmpty
        ? description
        : (prev?.meta?['description']?.toString() ??
            (command.isNotEmpty ? command.trim().split('\n').first : name));
    final cmd = command.isNotEmpty ? command : (prev?.meta?['command']?.toString() ?? '');
    final toolName = name.isNotEmpty ? name : (prev?.meta?['name']?.toString() ?? 'tool');
    final msg = ChatMessage(
      role: 'tool',
      content: output,
      kind: ChatKind.toolResult,
      meta: {
        'part': 'toolResult',
        'id': id,
        'name': toolName,
        'command': cmd,
        'description': desc,
        'success': success,
      },
      at: prev?.at,
    );
    if (idx >= 0) {
      agentMessages[idx] = msg;
    } else {
      agentMessages.add(msg);
    }
  }

  void _scheduleStreamNotify() {
    _streamNotifyPending = true;
    if (_streamNotifyTimer?.isActive == true) return;
    _streamNotifyTimer = Timer(const Duration(milliseconds: 33), () {
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
            // Token deltas: throttle UI rebuilds. Structural events: flush now.
            if (type == 'assistant_delta' || type == 'reasoning_delta') {
              _scheduleStreamNotify();
            } else {
              _flushStreamNotify();
              notifyListeners();
            }
          },
        );
      } catch (_) {
        final res = await api.agentChat(hostId: id, message: userText, sessionId: agentSessionId, confirmWrites: confirmWrites);
        agentSessionId = res['sessionId'] as String? ?? agentSessionId;
        for (final raw in (res['events'] as List?) ?? []) {
          if (raw is Map) _ingestAgentEvent(Map<String, dynamic>.from(raw));
        }
      }
      _flushStreamNotify();
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
      _flushStreamNotify();
      notifyListeners();
    }
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



  void disposeAgentChat() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }
}
