import 'package:ssh_ai_agent/models/chat_message.dart';

class AgentSession {
  AgentSession({
    required this.id,
    required this.title,
    this.hostId,
    this.preview = '',
    this.msgCount = 0,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    DateTime? createdAt,
  })  : messages = messages ?? <ChatMessage>[],
        updatedAt = updatedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  String id;
  String title;
  String? hostId;
  String preview;
  int msgCount;
  final List<ChatMessage> messages;
  DateTime updatedAt;
  DateTime createdAt;

  factory AgentSession.fromJson(Map<String, dynamic> j) {
    DateTime parseT(dynamic v) {
      if (v == null) return DateTime.now();
      final d = DateTime.tryParse(v.toString());
      return d?.toLocal() ?? DateTime.now();
    }

    return AgentSession(
      id: j['id']?.toString() ?? '',
      title: (j['title'] as String?)?.trim().isNotEmpty == true
          ? j['title'].toString()
          : '会话',
      hostId: (j['hostId'] as String?)?.isNotEmpty == true ? j['hostId'].toString() : null,
      preview: j['preview']?.toString() ?? '',
      msgCount: (j['msgCount'] as num?)?.toInt() ?? 0,
      updatedAt: parseT(j['updatedAt']),
      createdAt: parseT(j['createdAt']),
    );
  }
}
