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
