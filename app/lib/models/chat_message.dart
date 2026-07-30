import 'package:ssh_ai_agent/util/time_fmt.dart';

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
      at = parseChinaInstant(rawAt.toString()) ?? DateTime.now().toUtc();
    }

    Map<String, dynamic>? meta;
    final m = j['meta'];
    if (m is Map) meta = Map<String, dynamic>.from(m);

    final kindStr = (j['kind'] ?? meta?['part'] ?? '').toString().toLowerCase();
    ChatKind kind = ChatKind.text;
    switch (kindStr) {
      case 'reasoning':
        kind = ChatKind.reasoning;
        break;
      case 'tooluse':
      case 'tool_use':
        kind = ChatKind.toolUse;
        break;
      case 'toolresult':
      case 'tool_result':
      case 'stepresult':
        kind = ChatKind.toolResult;
        break;
      case 'plan':
        kind = ChatKind.plan;
        break;
      case 'error':
        kind = ChatKind.error;
        break;
      case 'status':
        kind = ChatKind.status;
        break;
      case 'text':
      case '':
        if (role == 'tool') {
          kind = ChatKind.toolResult;
        } else if (role == 'system') {
          kind = ChatKind.status;
        } else {
          kind = ChatKind.text;
        }
        break;
      default:
        if (role == 'tool') {
          kind = ChatKind.toolResult;
        } else {
          kind = ChatKind.text;
        }
    }

    // Ensure tool cards have part meta for _Bubble / _MinisToolBlock.
    if (kind == ChatKind.toolUse || kind == ChatKind.toolResult) {
      meta = {
        ...?meta,
        'part': kind == ChatKind.toolUse ? 'toolUse' : 'toolResult',
        if (meta?['success'] == null && kind == ChatKind.toolResult && content.isNotEmpty)
          'output': content,
      };
      // Infer success when missing
      final m0 = meta;
      if (kind == ChatKind.toolResult && m0['success'] == null && m0['pendingConfirm'] != true) {
        final low = content.toLowerCase();
        final failed = low.startsWith('error:') || low.contains('needs_confirm');
        m0['success'] = !failed;
      }
    }
    if (kind == ChatKind.reasoning) {
      meta = {...?meta, 'part': 'reasoning'};
    }

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
