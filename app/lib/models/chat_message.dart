/// One line in the Agent chat transcript (CLI-style agent session).
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
  /// Optional structured payload (plan steps, exec result, etc.)
  final Map<String, dynamic>? meta;
  final DateTime at;
}

enum ChatKind {
  text,
  plan,
  stepResult,
  error,
  status,
  reasoning,
}
