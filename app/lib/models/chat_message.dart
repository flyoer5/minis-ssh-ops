/// One line in the Agent chat transcript (Minis-style session).
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.kind = ChatKind.text,
    this.meta,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// user | assistant | system | tool
  final String role;
  final String content;
  final ChatKind kind;
  /// Optional structured payload (plan steps, tool name/command/success, etc.)
  final Map<String, dynamic>? meta;
  final DateTime at;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final role = j['role']?.toString() ?? 'assistant';
    final content = j['content']?.toString() ?? '';
    DateTime at = DateTime.now();
    final rawAt = j['createdAt'] ?? j['at'] ?? j['timestamp'];
    if (rawAt != null) {
      at = DateTime.tryParse(rawAt.toString())?.toLocal() ?? DateTime.now();
    }
    // Server currently stores plain role/content; map tool roles to toolResult kind.
    ChatKind kind = ChatKind.text;
    if (role == 'tool') {
      kind = ChatKind.toolResult;
    } else if (role == 'system') {
      kind = ChatKind.status;
    }
    Map<String, dynamic>? meta;
    final m = j['meta'];
    if (m is Map) meta = Map<String, dynamic>.from(m);
    return ChatMessage(role: role, content: content, kind: kind, meta: meta, at: at);
  }
}

enum ChatKind {
  text,
  plan,
  /// Completed tool output (legacy name; same as toolResult).
  stepResult,
  /// Tool started (Minis toolUse part).
  toolUse,
  /// Tool finished (Minis toolResult part).
  toolResult,
  error,
  status,
  reasoning,
}
