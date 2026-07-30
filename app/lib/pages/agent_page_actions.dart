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
      if (mounted) showSnack(context, 'Failed to load session: ${cleanError(e)}', seconds: 3);
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
        _busyHint = 'Stopped';
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
      _busyHint = 'Retrying...';
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
        title: const Text('主机密钥已变更'),
        content: const Text(
          'The SSH host key on the server does not match the local record. This can happen after a reinstall, or it may indicate a man-in-the-middle risk. If the environment is trusted, clear the old record and trust the new key on the next connection.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清除并信任')),
        ],
      ),
    );
    if (go == true) {
      try {
        await state.resetHostKeyForSelected();
        if (mounted) showSnack(context, 'Cleared, please retry');
      } catch (e) {
        if (mounted) showSnack(context, cleanError(e));
      }
    }
  }
}
