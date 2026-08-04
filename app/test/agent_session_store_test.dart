import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/agent_session_store.dart';

void main() {
  test('decodes legacy tool parts into first-class message kinds', () {
    final sessions = AgentSessionStore.decode(jsonEncode([
      {
        'id': 's1',
        'title': 'Legacy',
        'messages': [
          {
            'role': 'assistant',
            'content': 'run',
            'kind': 'text',
            'meta': {'part': 'toolUse'},
          },
          {
            'role': 'tool',
            'content': 'done',
            'kind': 'stepResult',
            'meta': {'part': 'toolResult'},
          },
        ],
      },
    ]));

    expect(sessions, hasLength(1));
    expect(sessions.single.messages[0].kind, ChatKind.toolUse);
    expect(sessions.single.messages[1].kind, ChatKind.toolResult);
  });

  test('returns an empty list for missing or malformed data', () {
    expect(AgentSessionStore.decode(null), isEmpty);
    expect(AgentSessionStore.decode('not json'), isEmpty);
    expect(AgentSessionStore.decode('{}'), isEmpty);
  });

  test('preserves session metadata when persisted and decoded', () {
    final created = DateTime.utc(2026, 8, 4, 1, 2, 3);
    final updated = DateTime.utc(2026, 8, 4, 2, 3, 4);
    final session = AgentSession(
      id: 'meta',
      title: '元数据会话',
      hostId: 'host-1',
      preview: '最近一条消息',
      msgCount: 12,
      createdAt: created,
      updatedAt: updated,
      ovMaxRounds: 8,
      ovTemperature: 0.4,
      ovConfirm: 1,
      ovPrompt: '只看关键错误',
      messages: [ChatMessage(role: 'user', content: '检查状态')],
    );
    final restored = AgentSessionStore.decode(AgentSessionStore.encode([session])).single;

    expect(restored.id, 'meta');
    expect(restored.title, '元数据会话');
    expect(restored.hostId, 'host-1');
    expect(restored.preview, '最近一条消息');
    expect(restored.msgCount, 12);
    expect(restored.createdAt, created);
    expect(restored.updatedAt, updated);
    expect(restored.ovMaxRounds, 8);
    expect(restored.ovTemperature, 0.4);
    expect(restored.ovConfirm, 1);
    expect(restored.ovPrompt, '只看关键错误');
  });

  test('bounds persisted sessions, keeps latest messages, and bounds content', () {
    final sessions = List.generate(
      21,
      (sessionIndex) => AgentSession(
        id: 's$sessionIndex',
        title: 'Session $sessionIndex',
        messages: List.generate(
          81,
          (messageIndex) => ChatMessage(
            role: 'assistant',
            content: messageIndex == 80
                ? List.filled(12001, 'x').join()
                : 'message $messageIndex',
          ),
        ),
      ),
    );

    final encoded = jsonDecode(AgentSessionStore.encode(sessions)) as List<dynamic>;
    expect(encoded, hasLength(20));
    final messages = (encoded.first as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(messages, hasLength(80));
    expect((messages.first as Map<String, dynamic>)['content'], 'message 1');
    expect((messages[messages.length - 2] as Map<String, dynamic>)['content'], 'message 79');

    final content = (messages.last as Map<String, dynamic>)['content'] as String;
    expect(content.length, 12001);
    expect(content.endsWith('…'), isTrue);
  });
}
