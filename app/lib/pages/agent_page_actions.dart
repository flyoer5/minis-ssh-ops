part of 'agent_page.dart';

extension _AgentPageActions on _AgentPageState {
  /// If a generation is running, ask the user to confirm before an action
  /// (switch session / host / new session) interrupts it. Protects against
  /// silently disrupting an in-progress turn.
  Future<bool> _confirmInterrupt(AppState state, {required String action}) async {
    if (!_busy && !state.agentBusy) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(action),
        content: const Text(
          '当前正在生成回复。继续此操作会中断当前生成，确定继续吗？',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('中断生成'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      _stopGeneration(state);
    }
    return go == true;
  }

  Future<void> _openSession(AppState state, String id, {String? title}) async {
    if (!await _confirmInterrupt(state, action: '切换会话')) return;
    try {
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
    _generationId++;
    _genTimer?.cancel();
    _genTimer = null;
    final elapsed = _elapsedLabel();
    _genStarted = null;
    state.cancelAgentChat();
    if (mounted) {
      setState(() {
        _busy = false;
        _busyHint = '已停止';
      });
      if (elapsed.isNotEmpty) {
        showSnack(context, '已停止生成（用时 $elapsed）', seconds: 2);
      }
    }
  }

  String _elapsedLabel() {
    if (_genStarted == null) return '';
    final sec = DateTime.now().difference(_genStarted!).inSeconds;
    if (sec < 60) return '$sec 秒';
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
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
    if (text == null || _busy || state.agentBusy) return;
    final generationId = ++_generationId;
    setState(() {
      _busy = true;
      _genStarted = DateTime.now();
      _busyHint = '重试中...';
    });
    _genTimer?.cancel();
    _genTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_busy || generationId != _generationId || _genStarted == null) return;
      final sec = DateTime.now().difference(_genStarted!).inSeconds;
      setState(() => _busyHint = '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')} 重试中');
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      if (generationId == _generationId && mounted) {
        showSnack(context, shortError(e), seconds: 3);
      }
    } finally {
      if (generationId == _generationId) {
        _genTimer?.cancel();
        _genTimer = null;
        _genStarted = null;
        if (mounted) {
          setState(() => _busy = false);
          _bottom(force: true);
        }
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
