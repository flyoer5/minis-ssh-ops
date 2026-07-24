import 'package:ssh_ai_agent/models/chat_message.dart';

class AgentSession {
  AgentSession({required this.id, required this.title, required this.hostId, List<ChatMessage>? messages})
      : messages = messages ?? <ChatMessage>[],
        updatedAt = DateTime.now();

  String id;
  String title;
  String? hostId;
  final List<ChatMessage> messages;
  DateTime updatedAt;
}
