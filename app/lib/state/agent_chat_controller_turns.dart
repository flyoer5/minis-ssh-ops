part of 'agent_chat_controller.dart';

extension AgentChatControllerTurns on AgentChatController {
  void cancelAgentChat() {
    _turnExecutor.cancel();
    api.cancelAgentStream();
    agentBusy = false;
    _flushStreamNotify();

    for (var i = agentMessages.length - 1; i >= 0; i--) {
      final m = agentMessages[i];
      if (m.role == 'user') break;
      if (m.kind == ChatKind.toolUse && m.meta?['success'] == null && m.meta?['pendingConfirm'] != true) {
        agentMessages[i] = ChatMessage(
          role: m.role,
          content: '已中断',
          kind: m.kind,
          meta: {
            if (m.meta != null) ...m.meta!,
            'success': false,
            'interrupted': true,
            'output': '已中断',
          },
          at: m.at,
        );
        continue;
      }
      if (m.kind == ChatKind.text || m.kind == ChatKind.reasoning) {
        final meta = <String, dynamic>{
          if (m.meta != null) ...m.meta!,
          'interrupted': true,
        };
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
        (agentMessages.last.content == 'Stopped' || agentMessages.last.content == 'Canceled' || agentMessages.last.content == '已停止生成');
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

  Future<void> agentChat(String userText) async {
    final id = selectedHostId;
    if (id == null) {
      _pushMsg(ChatMessage(role: 'assistant', content: '请先选择主机', kind: ChatKind.error));
      return;
    }
    if (agentBusy) {
      _pushMsg(ChatMessage(role: 'assistant', content: '上一轮仍在进行，请稍候', kind: ChatKind.status));
      return;
    }

    agentBusy = true;
    final turn = _turnExecutor.beginTurn();
    if (agentSessionId == null || agentSessionId!.isEmpty) {
      try {
        final r = await api.createAgentSession(hostId: id, title: userText.trim());
        final sid = (r['sessionId'] ?? r['id'] ?? '').toString();
        if (sid.isNotEmpty) agentSessionId = sid;
      } catch (_) {}
    }
    if (!_turnExecutor.isCurrent(turn)) return;

    _pushMsg(ChatMessage(role: 'user', content: userText));
    if (agentSessionTitle == '新会话' || agentSessionTitle.isEmpty) {
      final t = userText.trim().replaceAll(RegExp(r'\s+'), ' ');
      agentSessionTitle = t.length > 32 ? '${t.substring(0, 32)}...' : t;
    }
    notifyListeners();

    try {
      final result = await _turnExecutor.execute(
        handle: turn,
        sessionId: agentSessionId,
        streamRequest: (onEvent) => api.agentChatStream(
          hostId: id,
          message: userText,
          sessionId: agentSessionId,
          confirmWrites: effectiveConfirmWrites,
          maxRounds: effectiveMaxRounds,
          temperature: effectiveTemperature,
          customPrompt: effectiveCustomPrompt,
          onEvent: onEvent,
        ),
        batchRequest: (sessionId) => api.agentChat(
          hostId: id,
          message: userText,
          sessionId: sessionId,
          confirmWrites: effectiveConfirmWrites,
          maxRounds: effectiveMaxRounds,
          temperature: effectiveTemperature,
          customPrompt: effectiveCustomPrompt,
        ),
        onSession: (sessionId) => agentSessionId = sessionId,
        onEvent: (raw) {
          final type = raw['type']?.toString() ?? '';
          _ingestAgentEvent(raw);
          if (type == 'assistant_delta' || type == 'reasoning_delta') {
            _scheduleStreamNotify();
          } else {
            _flushStreamNotify();
            notifyListeners();
          }
        },
      );

      if (result.completed && _turnExecutor.isCurrent(turn)) {
        agentSessionId = result.sessionId ?? agentSessionId;
        _flushStreamNotify();
        notifyListeners();
      }
    } catch (e) {
      if (_turnExecutor.isCurrent(turn)) {
        _pushMsg(ChatMessage(role: 'assistant', content: _friendlyErr(e), kind: ChatKind.error));
      }
    } finally {
      if (_turnExecutor.isCurrent(turn)) {
        _turnExecutor.finish(turn);
        agentBusy = false;
        _flushStreamNotify();
        notifyListeners();
      }
    }
  }

  void _supersedeAgentTurn() {
    _turnExecutor.supersede();
    api.cancelAgentStream();
  }

  void _ingestAgentEvent(Map<String, dynamic> raw) {
    final type = raw['type']?.toString() ?? '';
    final content = (raw['content'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    final command = (raw['command'] ?? '').toString();
    final reasoning = (raw['reasoning'] ?? '').toString().trim();

    switch (type) {
      case 'memory':
        _handleMemoryEvent(content, raw);
        break;
      case 'reasoning_delta':
        if (reasoning.isNotEmpty || content.isNotEmpty) {
          _appendReasoningDelta(content.isNotEmpty ? content : reasoning);
        }
        break;
      case 'assistant_delta':
        if (content.isNotEmpty) _appendAssistantDelta(content);
        break;
      case 'reasoning':
        if (reasoning.isNotEmpty || content.trim().isNotEmpty) {
          _pushReasoning(reasoning.isNotEmpty ? reasoning : content);
        }
        break;
      case 'assistant':
        if (reasoning.isNotEmpty) _pushReasoning(reasoning);
        if (content.isNotEmpty) _pushOrMergeAssistantText(content, part: 'text');
        break;
      case 'tool':
        _handleToolEvent(name: name, command: command);
        break;
      case 'tool_result':
        _handleToolResultEvent(name: name, command: command, content: content);
        break;
      case 'final':
        if (reasoning.isNotEmpty) _pushReasoning(reasoning);
        if (content.isNotEmpty) _coalesceAssistantFull(content, part: 'text');
        break;
      case 'error':
        if (content.isNotEmpty) {
          _pushMsg(ChatMessage(role: 'assistant', content: content, kind: ChatKind.error));
        }
        break;
    }
  }

  void _handleMemoryEvent(String content, Map<String, dynamic> raw) {
    final facts = (raw['facts'] ?? '').toString().trim();
    if (facts.isNotEmpty || content.trim().isNotEmpty) {
      _pushMsg(ChatMessage(role: 'system', content: '记忆已更新', kind: ChatKind.status));
    }
  }

  void _handleToolEvent({required String name, required String command}) {
    String title;
    if (name == 'probe_host') {
      title = '检查主机状态';
    } else if (command.isNotEmpty) {
      final one = command.trim().split('\n').first;
      title = one.length > 80 ? '${one.substring(0, 80)}...' : one;
    } else if (name.isNotEmpty) {
      title = name;
    } else {
      title = 'tool';
    }

    final toolName = name.isEmpty ? (command.isEmpty ? 'tool' : 'run_command') : name;
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
  }

  void _handleToolResultEvent({required String name, required String command, required String content}) {
    if (content.startsWith('error: NEEDS_CONFIRM:') || content.startsWith('NEEDS_CONFIRM:')) {
      final rest = content.replaceFirst('error: ', '').replaceFirst('NEEDS_CONFIRM:', '');
      final colon = rest.indexOf(':');
      final risk = colon > 0 ? rest.substring(0, colon) : 'write';
      final cmd = colon > 0 ? rest.substring(colon + 1) : rest;
      final toolName = name.isEmpty ? 'run_command' : name;
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
            'description': '执行前需要确认',
            'success': null,
            'pendingConfirm': true,
            'risk': risk,
          },
          at: m.at,
        );
      }

      final existingSteps = (lastPlan?['steps'] as List?) ?? const [];
      final already = existingSteps.any((e) {
        if (e is! Map) return false;
        return (e['command']?.toString() ?? '') == cmd;
      });
      if (!already) {
        final step = {
          'id': (lastPlan == null ? 1 : (((lastPlan!['steps'] as List?)?.length ?? 0) + 1)),
          'title': '需要确认',
          'command': cmd,
          'risk': risk,
        };
        final steps = <Map<String, dynamic>>[step];
        if (lastPlan != null && lastPlan!['steps'] is List) {
          steps.insertAll(0, [for (final e in (lastPlan!['steps'] as List)) if (e is Map) Map<String, dynamic>.from(e)]);
        }
        lastPlan = {'summary': '等待确认', 'steps': steps};
        final idx = _lastPlanMsgIndex;
        final planMsg = ChatMessage(
          role: 'assistant',
          content: '等待确认',
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
            ? '${command.trim().split('\n').first.substring(0, 80)}...'
            : command.trim().split('\n').first)
        : toolName;

    _completeToolResult(
      name: toolName,
      command: command,
      output: content,
      success: !failed,
      description: desc,
    );
  }

  void _sealPendingToolUse(String command, {required bool success, required String output}) {
    _transcript.sealPendingToolUse(command, success: success, output: output);
  }

  void disposeAgentChat() {
    _supersedeAgentTurn();
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }
}
