import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/agent_transcript.dart';

void main() {
  test('coalesces streamed assistant text with the final frame', () {
    final messages = <ChatMessage>[ChatMessage(role: 'user', content: 'hello')];
    final transcript = AgentTranscript(messages);

    transcript.appendAssistantDelta('Hello');
    transcript.appendAssistantDelta(' world');
    transcript.coalesceAssistantFull('Hello world');

    expect(messages, hasLength(2));
    expect(messages.last.content, 'Hello world');
    expect(messages.last.meta?['part'], 'text');
  });

  test('keeps reasoning above answer text and merges the final reasoning', () {
    final messages = <ChatMessage>[ChatMessage(role: 'user', content: 'hello')];
    final transcript = AgentTranscript(messages);

    transcript.appendAssistantDelta('Answer');
    transcript.appendReasoningDelta('Theusersaidhello.');
    transcript.pushReasoning('The user said hello.');

    expect(messages.map((message) => message.kind), [
      ChatKind.text,
      ChatKind.reasoning,
      ChatKind.text,
    ]);
    expect(messages[1].content, 'The user said hello.');
  });

  test('pairs a tool result with the matching open tool card', () {
    final messages = <ChatMessage>[];
    final transcript = AgentTranscript(messages);

    transcript.pushToolUse(name: 'run_command', command: 'uptime', description: 'uptime');
    final id = messages.single.meta?['id'];
    transcript.completeToolResult(
      name: 'run_command',
      command: 'uptime',
      output: 'up 1 day',
      success: true,
      description: 'uptime',
    );

    expect(messages, hasLength(1));
    expect(messages.single.kind, ChatKind.toolResult);
    expect(messages.single.meta?['id'], id);
    expect(messages.single.meta?['success'], isTrue);
  });

  test('seals a pending confirmation after manual execution', () {
    final messages = <ChatMessage>[
      ChatMessage(
        role: 'tool',
        content: '等待确认',
        kind: ChatKind.toolUse,
        meta: const {
          'part': 'toolUse',
          'command': 'systemctl restart nginx',
          'pendingConfirm': true,
          'success': null,
        },
      ),
    ];
    final transcript = AgentTranscript(messages);

    transcript.sealPendingToolUse(
      'systemctl restart nginx',
      success: true,
      output: 'done',
    );

    expect(messages.single.meta?['pendingConfirm'], isFalse);
    expect(messages.single.meta?['success'], isTrue);
    expect(messages.single.content, 'done');
  });

  test('bounds the live transcript to the newest messages', () {
    final messages = <ChatMessage>[];
    final transcript = AgentTranscript(messages);

    for (var i = 0; i < AgentTranscript.maxLiveMessages + 5; i++) {
      transcript.add(ChatMessage(role: 'user', content: '$i'));
    }

    expect(messages, hasLength(AgentTranscript.maxLiveMessages));
    expect(messages.first.content, '5');
  });
}
