import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/state/agent_turn_executor.dart';

void main() {
  test('uses streaming events without calling the batch fallback', () async {
    final executor = AgentTurnExecutor();
    final handle = executor.beginTurn();
    final events = <Map<String, dynamic>>[];
    final sessions = <String>[];
    var batchCalls = 0;

    final result = await executor.execute(
      handle: handle,
      sessionId: 'initial',
      streamRequest: (onEvent) async {
        onEvent({'type': 'session', 'sessionId': 'stream-session'});
        onEvent({'type': 'assistant_delta', 'content': 'hello'});
        onEvent({'type': 'done'});
      },
      batchRequest: (_) async {
        batchCalls++;
        return {};
      },
      onEvent: events.add,
      onSession: sessions.add,
    );

    expect(result.status, AgentTurnStatus.completed);
    expect(result.sessionId, 'stream-session');
    expect(batchCalls, 0);
    expect(sessions, ['stream-session']);
    expect(events, [
      {'type': 'assistant_delta', 'content': 'hello'},
    ]);
  });

  test('falls back once after a genuine stream failure', () async {
    final executor = AgentTurnExecutor();
    final handle = executor.beginTurn();
    final events = <Map<String, dynamic>>[];
    var batchCalls = 0;

    final result = await executor.execute(
      handle: handle,
      sessionId: 'initial',
      streamRequest: (onEvent) async {
        onEvent({'type': 'session', 'sessionId': 'from-stream'});
        throw StateError('stream failed');
      },
      batchRequest: (sessionId) async {
        batchCalls++;
        expect(sessionId, 'from-stream');
        return {
          'sessionId': 'from-batch',
          'events': [
            {'type': 'assistant', 'content': 'complete'},
          ],
        };
      },
      onEvent: events.add,
    );

    expect(result.status, AgentTurnStatus.completed);
    expect(result.sessionId, 'from-batch');
    expect(batchCalls, 1);
    expect(events.single['content'], 'complete');
  });

  test('does not retry a cancelled stream through the batch endpoint', () async {
    final executor = AgentTurnExecutor();
    final handle = executor.beginTurn();
    var batchCalls = 0;

    final result = await executor.execute(
      handle: handle,
      sessionId: null,
      streamRequest: (_) async {
        executor.cancel();
        throw StateError('client closed');
      },
      batchRequest: (_) async {
        batchCalls++;
        return {};
      },
      onEvent: (_) {},
    );

    expect(result.status, AgentTurnStatus.cancelled);
    expect(batchCalls, 0);
  });

  test('does not start a request for an already cancelled turn', () async {
    final executor = AgentTurnExecutor();
    final handle = executor.beginTurn();
    var streamCalls = 0;
    var batchCalls = 0;
    executor.cancel();

    final result = await executor.execute(
      handle: handle,
      sessionId: null,
      streamRequest: (_) async {
        streamCalls++;
      },
      batchRequest: (_) async {
        batchCalls++;
        return {};
      },
      onEvent: (_) {},
    );

    expect(result.status, AgentTurnStatus.cancelled);
    expect(streamCalls, 0);
    expect(batchCalls, 0);
  });

  test('ignores a superseded turn and does not call the fallback', () async {
    final executor = AgentTurnExecutor();
    final first = executor.beginTurn();
    final events = <Map<String, dynamic>>[];
    var batchCalls = 0;

    final result = await executor.execute(
      handle: first,
      sessionId: null,
      streamRequest: (onEvent) async {
        executor.beginTurn();
        onEvent({'type': 'assistant_delta', 'content': 'stale'});
        throw StateError('old stream closed');
      },
      batchRequest: (_) async {
        batchCalls++;
        return {};
      },
      onEvent: events.add,
    );

    expect(result.status, AgentTurnStatus.superseded);
    expect(batchCalls, 0);
    expect(events, isEmpty);
  });

  test('surfaces a batch failure while the turn is still active', () async {
    final executor = AgentTurnExecutor();
    final handle = executor.beginTurn();

    await expectLater(
      executor.execute(
        handle: handle,
        sessionId: null,
        streamRequest: (_) async => throw StateError('stream failed'),
        batchRequest: (_) async => throw ArgumentError('batch failed'),
        onEvent: (_) {},
      ),
      throwsArgumentError,
    );
  });
}
