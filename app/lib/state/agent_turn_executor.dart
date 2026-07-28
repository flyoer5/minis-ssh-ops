typedef AgentEventHandler = void Function(Map<String, dynamic> event);
typedef AgentSessionHandler = void Function(String sessionId);
typedef AgentStreamRequest = Future<void> Function(AgentEventHandler onEvent);
typedef AgentBatchRequest = Future<Map<String, dynamic>> Function(String? sessionId);

enum AgentTurnStatus { completed, cancelled, superseded }

class AgentTurnResult {
  const AgentTurnResult({required this.status, this.sessionId});

  final AgentTurnStatus status;
  final String? sessionId;

  bool get completed => status == AgentTurnStatus.completed;
}

class AgentTurnHandle {
  AgentTurnHandle._();

  bool _cancelled = false;
  bool _superseded = false;
}

/// Runs one Agent turn with streaming first and a single batch fallback.
///
/// The controller keeps UI and transcript ownership. This class only owns the
/// request lifecycle so cancelled or superseded turns cannot emit stale events.
class AgentTurnExecutor {
  AgentTurnHandle? _current;

  AgentTurnHandle beginTurn() {
    supersede();
    final handle = AgentTurnHandle._();
    _current = handle;
    return handle;
  }

  bool isCurrent(AgentTurnHandle handle) =>
      identical(_current, handle) && !handle._cancelled && !handle._superseded;

  void cancel() {
    final handle = _current;
    if (handle == null) return;
    handle._cancelled = true;
    _current = null;
  }

  void supersede() {
    final handle = _current;
    if (handle == null) return;
    handle._superseded = true;
    _current = null;
  }

  void finish(AgentTurnHandle handle) {
    if (identical(_current, handle)) _current = null;
  }

  Future<AgentTurnResult> execute({
    required AgentTurnHandle handle,
    required String? sessionId,
    required AgentStreamRequest streamRequest,
    required AgentBatchRequest batchRequest,
    required AgentEventHandler onEvent,
    AgentSessionHandler? onSession,
  }) async {
    var resolvedSessionId = sessionId;

    if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);

    void acceptEvent(Map<String, dynamic> raw) {
      if (!isCurrent(handle)) return;
      final type = raw['type']?.toString() ?? '';
      if (type == 'session') {
        final nextSessionId = raw['sessionId']?.toString() ?? '';
        if (nextSessionId.isNotEmpty) {
          resolvedSessionId = nextSessionId;
          onSession?.call(nextSessionId);
        }
        return;
      }
      if (type != 'done') onEvent(raw);
    }

    try {
      try {
        await streamRequest(acceptEvent);
      } catch (_) {
        if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);

        final response = await batchRequest(resolvedSessionId);
        if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);

        final nextSessionId = response['sessionId']?.toString() ?? '';
        if (nextSessionId.isNotEmpty) {
          resolvedSessionId = nextSessionId;
          onSession?.call(nextSessionId);
        }
        for (final raw in (response['events'] as List?) ?? const []) {
          if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);
          if (raw is Map) acceptEvent(Map<String, dynamic>.from(raw));
        }
      }

      if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);
      return AgentTurnResult(
        status: AgentTurnStatus.completed,
        sessionId: resolvedSessionId,
      );
    } catch (_) {
      if (!isCurrent(handle)) return _stoppedResult(handle, resolvedSessionId);
      rethrow;
    }
  }

  AgentTurnResult _stoppedResult(AgentTurnHandle handle, String? sessionId) {
    return AgentTurnResult(
      status: handle._cancelled ? AgentTurnStatus.cancelled : AgentTurnStatus.superseded,
      sessionId: sessionId,
    );
  }
}
