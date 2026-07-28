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

  test('bounds persisted sessions, messages, and content', () {
    final sessions = List.generate(
      21,
      (sessionIndex) => AgentSession(
        id: 's$sessionIndex',
        title: 'Session $sessionIndex',
        messages: List.generate(
          81,
          (messageIndex) => ChatMessage(
            role: 'assistant',
            content: messageIndex == 0
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
    final content = (messages.first as Map<String, dynamic>)['content'] as String;
    expect(content.length, 12001);
    expect(content.endsWith('…'), isTrue);
  });
}
