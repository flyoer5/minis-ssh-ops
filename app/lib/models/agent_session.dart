import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';

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
    this.ovMaxRounds,
    this.ovTemperature,
    this.ovConfirm,
    this.ovPrompt,
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

  /// Session overrides (null = inherit global).
  int? ovMaxRounds;
  double? ovTemperature;
  /// null inherit; 0 off; 1 on
  int? ovConfirm;
  String? ovPrompt;

  bool get hasOverrides =>
      ovMaxRounds != null ||
      ovTemperature != null ||
      ovConfirm != null ||
      (ovPrompt != null && ovPrompt!.trim().isNotEmpty);

  factory AgentSession.fromJson(Map<String, dynamic> j) {
    DateTime parseT(dynamic v) {
      if (v == null) return DateTime.now();
      return parseChinaInstant(v.toString()) ?? DateTime.now().toUtc();
    }

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
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
      ovMaxRounds: asInt(j['ovMaxRounds']),
      ovTemperature: asDouble(j['ovTemperature']),
      ovConfirm: asInt(j['ovConfirm']),
      ovPrompt: j['ovPrompt']?.toString(),
    );
  }
}
