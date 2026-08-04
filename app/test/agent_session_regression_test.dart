import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/agent_chat_controller.dart';
import 'package:ssh_ai_agent/state/agent_session_store.dart';

/// Minimal in-memory [AgentChatController] harness (no real network).
class _Harness extends ChangeNotifier with AgentChatController {
  // 测试不访问网络；仅满足 mixin 的类型契约。
  @override
  ApiClient get api => ApiClient();
  String? _selectedHostId = 'host-1';
  @override
  String? get selectedHostId => _selectedHostId;
  @override
  set selectedHostId(String? v) => _selectedHostId = v;
  @override
  bool get confirmWrites => false;
  @override
  int get agentMaxRounds => 12;
  @override
  double get agentTemperature => 0.7;
  @override
  String get agentCustomPrompt => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('会话快照与保留', () {
    test('保存的本地会话保留最近 80 条消息', () {
      final msgs = <ChatMessage>[
        for (var i = 1; i <= 90; i++)
          ChatMessage(role: 'assistant', content: '第 $i 条'),
      ];
      final sessions = [
        AgentSession(
          id: 's1',
          title: '会话',
          hostId: 'h',
          preview: '最近一条',
          msgCount: 90,
          messages: msgs,
        ),
      ];
      final encoded = jsonDecode(AgentSessionStore.encode(sessions)) as List;
      expect(encoded, hasLength(1));
      final stored = (encoded.first as Map)['messages'] as List;
      expect(stored, hasLength(80));
      expect((stored.first as Map)['content'], '第 11 条');
      expect((stored.last as Map)['content'], '第 90 条');
    });

    test('保存的会话元数据完整，且超大工具输出会被裁剪', () {
      final big = 'x' * 20000;
      final session = AgentSession(
        id: 's-meta',
        title: '元数据',
        preview: '预览内容',
        msgCount: 3,
        updatedAt: DateTime.utc(2026, 8, 4),
        createdAt: DateTime.utc(2026, 8, 3),
        ovMaxRounds: 6,
        ovTemperature: 0.4,
        ovConfirm: 1,
        ovPrompt: '只看错误',
        messages: [
          ChatMessage(
            role: 'tool',
            content: 'run',
            kind: ChatKind.toolResult,
            meta: {'part': 'toolResult', 'success': true, 'output': big},
          ),
        ],
      );
      final restored =
          AgentSessionStore.decode(AgentSessionStore.encode([session])).single;
      expect(restored.msgCount, 3);
      expect(restored.ovMaxRounds, 6);
      expect(restored.ovTemperature, 0.4);
      expect(restored.ovConfirm, 1);
      expect(restored.ovPrompt, '只看错误');
      final storedOutput =
          (restored.messages.first.meta?['output'] as String?) ?? '';
      expect(storedOutput.length, 12001);
      expect(storedOutput.endsWith('…'), isTrue);
    });

    test('清理当前会话会保存快照到历史列表', () async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness();
      for (var i = 1; i <= 2; i++) {
        h.agentMessages.add(ChatMessage(
          role: 'user',
          content: '问题 $i',
          at: DateTime.utc(2026, 8, 4),
        ));
        h.agentMessages.add(ChatMessage(
          role: 'assistant',
          content: '回答 $i',
          at: DateTime.utc(2026, 8, 4),
        ));
      }
      h.agentSessionTitle = '我的会话';
      h.clearAgentChat();
      expect(h.agentSessions, isNotEmpty);
      final snap = h.agentSessions.first;
      expect(snap.title, '我的会话');
      expect(snap.msgCount, 4);
      expect(snap.preview, isNotEmpty);
    });
  });
}
