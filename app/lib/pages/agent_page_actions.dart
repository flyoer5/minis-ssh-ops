part of 'agent_page.dart';

extension _AgentPageActions on _AgentPageState {
  void _loadSessions(AppState state) {
    setState(() => _sessionsLoading = true);
    _doLoad(state);
  }

  Future<void> _doLoad(AppState state) async {
    try {
      final raw = await state.api.listAgentSessions(
        hostId: _onlyCurrentHost ? state.selectedHostId : null,
        q: _sessionsQuery.isNotEmpty ? _sessionsQuery : null,
      );
      if (mounted) {
        final sessions = [for (final j in raw) AgentSession.fromJson(j)];
        setState(() {
          _cachedSessions = sessions;
          _sessionsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _openSession(AppState state, String id, {String? title}) async {
    try {
      if (_busy || state.agentBusy) {
        _stopGeneration(state);
      }
      setState(() => _sessionsLoading = true);
      try {
        final results = await Future.wait([
          state.api.getAgentSession(id),
          state.api.getAgentSessionMessages(id),
        ]);
        final sess = AgentSession.fromJson(results[0] as Map<String, dynamic>);
        final raw = results[1] as List<Map<String, dynamic>>;
        final msgs = [for (final j in raw) ChatMessage.fromJson(j)];
        final sidHost = sess.hostId;
        if (sidHost != null && sidHost.isNotEmpty && state.selectedHostId != sidHost) {
          state.selectHost(sidHost);
        }
        state.openAgentSessionRaw(
          id,
          msgs,
          title: title ?? sess.title,
          ovMaxRounds: sess.ovMaxRounds,
          ovTemperature: sess.ovTemperature,
          ovConfirm: sess.ovConfirm,
          ovPrompt: sess.ovPrompt,
        );
      } finally {
        if (mounted) setState(() => _sessionsLoading = false);
      }
    } catch (e) {
      if (mounted) showSnack(context, '加载会话失败：${cleanError(e)}', seconds: 3);
    }
  }

  Future<void> _showSessionSettings(AppState state) => showAgentSessionSettingsSheet(context, state);

  Future<void> _showSessionMemory(AppState state) => showAgentSessionMemorySheet(context, state);

  Future<void> _showSessions(AppState state) => showAgentSessionsSheet(context, this, state);

  void _stopGeneration(AppState state) {
    state.cancelAgentChat();
    if (mounted) {
      setState(() {
        _busy = false;
        _busyHint = '已停止';
      });
    }
  }

  String? _lastUserText(AppState state) {
    for (var i = state.agentMessages.length - 1; i >= 0; i--) {
      final m = state.agentMessages[i];
      if (m.role != 'user') continue;
      final t = m.content.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('User already confirmed and executed:')) continue;
      return t;
    }
    return null;
  }

  bool _canRetryLast(AppState state) {
    if (_busy || state.agentBusy || state.selectedHostId == null) return false;
    if (_lastUserText(state) == null) return false;
    for (var i = state.agentMessages.length - 1; i >= 0; i--) {
      final m = state.agentMessages[i];
      if (m.role == 'user') return false;
      if (m.kind == ChatKind.error) return true;
      if (m.kind == ChatKind.status &&
          (m.content.contains('Stopped') || m.content.contains('Canceled') || m.meta?['interrupted'] == true)) {
        return true;
      }
      if (m.meta?['interrupted'] == true) return true;
      if (m.kind == ChatKind.text || m.kind == ChatKind.reasoning) continue;
    }
    return false;
  }

  Future<void> _retryLast(AppState state) async {
    final text = _lastUserText(state);
    if (text == null || _busy) return;
    setState(() {
      _busy = true;
      _busyHint = '重试中...';
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      if (mounted) {
        showSnack(context, shortError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom();
      }
    }
  }

  Future<void> _handleHostKeyMismatch(AppState state) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('主机密钥已变化'),
        content: const Text(
          '服务器 SSH 主机密钥与本地记录不一致。可能是服务器重装，也可能存在中间人风险。确认环境可信后，可清除旧记录，并在下次连接时信任新密钥。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清除并重新信任')),
        ],
      ),
    );
    if (go == true) {
      try {
        await state.resetHostKeyForSelected();
        if (mounted) showSnack(context, '已清除，请重试');
      } catch (e) {
        if (mounted) showSnack(context, cleanError(e));
      }
    }
  }
}
