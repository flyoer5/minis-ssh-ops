import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';

class AgentSessionStore {
  static const _prefsKey = 'agentSessionsJson';
  static const _maxSessions = 20;
  static const _maxMessages = 80;
  static const _maxContentLength = 12000;

  static List<AgentSession> load(SharedPreferences prefs) {
    return decode(prefs.getString(_prefsKey));
  }

  static Future<void> save(List<AgentSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encode(sessions));
  }

  static List<AgentSession> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <AgentSession>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <AgentSession>[];
      return [
        for (final entry in decoded)
          if (entry is Map) _decodeSession(entry),
      ];
    } catch (_) {
      return <AgentSession>[];
    }
  }

  static String encode(List<AgentSession> sessions) {
    final encoded = <Map<String, dynamic>>[
      for (final session in sessions.take(_maxSessions))
        {
          'id': session.id,
          'title': session.title,
          'hostId': session.hostId,
          'preview': session.preview,
          'msgCount': session.msgCount,
          'updatedAt': session.updatedAt.toIso8601String(),
          'createdAt': session.createdAt.toIso8601String(),
          if (session.ovMaxRounds != null) 'ovMaxRounds': session.ovMaxRounds,
          if (session.ovTemperature != null) 'ovTemperature': session.ovTemperature,
          if (session.ovConfirm != null) 'ovConfirm': session.ovConfirm,
          if (session.ovPrompt != null && session.ovPrompt!.trim().isNotEmpty) 'ovPrompt': session.ovPrompt,
          'messages': [
            for (final message in _latestMessages(session.messages))
              {
                'role': message.role,
                'content': _boundedContent(message.content),
                'kind': message.kind.name,
                if (message.meta != null) 'meta': message.meta,
              },
          ],
        },
    ];
    return jsonEncode(encoded);
  }

  static List<ChatMessage> _latestMessages(List<ChatMessage> messages) {
    if (messages.length <= _maxMessages) return messages;
    return messages.sublist(messages.length - _maxMessages);
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime parseT(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    return parseChinaInstant(value.toString()) ?? DateTime.now().toUtc();
  }

  static AgentSession _decodeSession(Map<dynamic, dynamic> raw) {
    final messages = <ChatMessage>[];
    final rawMessages = raw['messages'];
    if (rawMessages is List) {
      for (final entry in rawMessages) {
        if (entry is! Map) continue;
        final json = Map<String, dynamic>.from(entry);
        final meta = json['meta'];
        if (meta is Map) {
          final normalizedMeta = Map<String, dynamic>.from(meta);
          json['meta'] = normalizedMeta;
          final part = normalizedMeta['part']?.toString();
          final kind = json['kind']?.toString();
          if (part == 'toolUse' && kind != ChatKind.toolUse.name) {
            json['kind'] = ChatKind.toolUse.name;
          } else if (part == 'toolResult' || kind == ChatKind.stepResult.name) {
            if (kind != ChatKind.plan.name) json['kind'] = ChatKind.toolResult.name;
          }
        }
        messages.add(ChatMessage.fromJson(json));
      }
    }
    return AgentSession(
      id: raw['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: raw['title']?.toString() ?? '会话',
      hostId: raw['hostId']?.toString(),
      preview: raw['preview']?.toString() ?? '',
      msgCount: (raw['msgCount'] as num?)?.toInt() ?? messages.length,
      updatedAt: parseT(raw['updatedAt']),
      createdAt: parseT(raw['createdAt']),
      ovMaxRounds: _asInt(raw['ovMaxRounds']),
      ovTemperature: _asDouble(raw['ovTemperature']),
      ovConfirm: _asInt(raw['ovConfirm']),
      ovPrompt: raw['ovPrompt']?.toString(),
      messages: messages,
    );
  }

  static String _boundedContent(String content) {
    if (content.length <= _maxContentLength) return content;
    return '${content.substring(0, _maxContentLength)}…';
  }
}
