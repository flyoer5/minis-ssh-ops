part of 'agent_chat_controller.dart';

extension AgentChatControllerHelpers on AgentChatController {
  void loadAgentSessionsFromPrefs(SharedPreferences prefs) {
    final loaded = AgentSessionStore.load(prefs);
    if (loaded.isEmpty) return;
    agentSessions
      ..clear()
      ..addAll(loaded);
  }

  Future<void> _saveSessionsToPrefs() => AgentSessionStore.save(agentSessions);

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
}
