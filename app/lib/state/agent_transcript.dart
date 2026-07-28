import 'package:ssh_ai_agent/agent/reasoning_merge.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';

class AgentTranscript {
  AgentTranscript(this.messages);

  static const maxLiveMessages = 200;

  final List<ChatMessage> messages;

  void add(ChatMessage message) {
    messages.add(message);
    trim();
  }

  void trim() {
    if (messages.length <= maxLiveMessages) return;
    messages.removeRange(0, messages.length - maxLiveMessages);
  }

  int get lastReasoningIndexInTurn {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role == 'user') break;
      if (message.kind == ChatKind.reasoning) return i;
    }
    return -1;
  }

  bool get turnHasAssistantText {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role == 'user') break;
      if (message.role == 'assistant' && message.kind == ChatKind.text) return true;
    }
    return false;
  }

  void pushReasoning(String reasoning) {
    final text = reasoning.trim();
    if (text.isEmpty) return;
    final index = lastReasoningIndexInTurn;
    if (index >= 0) {
      final previous = messages[index];
      messages[index] = ChatMessage(
        role: 'assistant',
        content: mergeReasoningForTurn(previous.content, text),
        kind: ChatKind.reasoning,
        meta: const {'part': 'reasoning'},
        at: previous.at,
      );
      return;
    }
    final message = ChatMessage(
      role: 'assistant',
      content: text,
      kind: ChatKind.reasoning,
      meta: const {'part': 'reasoning'},
    );
    if (turnHasAssistantText) {
      messages.insert(_firstAssistantTextIndexInTurn(), message);
    } else {
      messages.add(message);
    }
  }

  void appendAssistantDelta(String piece) {
    if (piece.isEmpty) return;
    if (messages.isNotEmpty) {
      final last = messages.last;
      final part = last.meta?['part']?.toString();
      final isOpenText = last.role == 'assistant' &&
          last.kind == ChatKind.text &&
          (part == null || part == 'text' || part == 'text_delta');
      if (isOpenText) {
        messages[messages.length - 1] = ChatMessage(
          role: 'assistant',
          content: last.content + piece,
          kind: ChatKind.text,
          meta: const {'part': 'text_delta'},
          at: last.at,
        );
        return;
      }
    }
    messages.add(ChatMessage(
      role: 'assistant',
      content: piece,
      kind: ChatKind.text,
      meta: const {'part': 'text_delta'},
    ));
    trim();
  }

  void appendReasoningDelta(String piece) {
    if (piece.isEmpty) return;
    final index = lastReasoningIndexInTurn;
    if (index >= 0) {
      final previous = messages[index];
      messages[index] = ChatMessage(
        role: 'assistant',
        content: previous.content + piece,
        kind: ChatKind.reasoning,
        meta: const {'part': 'reasoning'},
        at: previous.at,
      );
      return;
    }
    final message = ChatMessage(
      role: 'assistant',
      content: piece,
      kind: ChatKind.reasoning,
      meta: const {'part': 'reasoning'},
    );
    if (turnHasAssistantText) {
      messages.insert(_firstAssistantTextIndexInTurn(), message);
    } else {
      messages.add(message);
    }
  }

  void coalesceAssistantFull(String content) {
    final text = content.trimRight();
    if (text.isEmpty) return;
    final index = _lastAssistantTextIndex();
    if (index >= 0) {
      final previous = messages[index];
      final currentNormalized = _normalize(previous.content);
      final fullNormalized = _normalize(text);
      var body = text;
      if (currentNormalized == fullNormalized ||
          fullNormalized.startsWith(currentNormalized) ||
          currentNormalized.startsWith(fullNormalized) ||
          currentNormalized.contains(fullNormalized) ||
          fullNormalized.contains(currentNormalized)) {
        body = text.length >= previous.content.length ? text : previous.content;
      }
      messages[index] = ChatMessage(
        role: 'assistant',
        content: body,
        kind: ChatKind.text,
        meta: const {'part': 'text'},
        at: previous.at,
      );
      return;
    }
    messages.add(ChatMessage(
      role: 'assistant',
      content: text,
      kind: ChatKind.text,
      meta: const {'part': 'text'},
    ));
  }

  int findOpenToolUse({required String name, required String command}) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (!_isOpenToolUse(message)) continue;
      final toolName = (message.meta?['name'] ?? '').toString();
      if (name.isNotEmpty && toolName.isNotEmpty && toolName != name) continue;
      final toolCommand = (message.meta?['command'] ?? '').toString();
      if (command.isNotEmpty && toolCommand.isNotEmpty && toolCommand.trim() != command.trim()) {
        continue;
      }
      return i;
    }
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (!_isOpenToolUse(message)) continue;
      final toolName = (message.meta?['name'] ?? '').toString();
      if (name.isEmpty || toolName == name) return i;
    }
    return -1;
  }

  void pushToolUse({
    required String name,
    required String command,
    required String description,
  }) {
    messages.add(ChatMessage(
      role: 'tool',
      content: description,
      kind: ChatKind.toolUse,
      meta: {
        'part': 'toolUse',
        'id': _newToolId(),
        'name': name,
        'command': command,
        'description': description,
        'success': null,
      },
    ));
  }

  void completeToolResult({
    required String name,
    required String command,
    required String output,
    required bool success,
    required String description,
  }) {
    final index = findOpenToolUse(name: name, command: command);
    final previous = index >= 0 ? messages[index] : null;
    final id = previous?.meta?['id']?.toString() ?? _newToolId();
    final resolvedDescription = description.isNotEmpty
        ? description
        : (previous?.meta?['description']?.toString() ??
            (command.isNotEmpty ? command.trim().split('\n').first : name));
    final resolvedCommand = command.isNotEmpty ? command : (previous?.meta?['command']?.toString() ?? '');
    final resolvedName = name.isNotEmpty ? name : (previous?.meta?['name']?.toString() ?? 'tool');
    var resolvedOutput = output;
    final lower = resolvedOutput.toLowerCase();
    if (lower.contains('context deadline exceeded') ||
        (lower.contains('deadline exceeded') && lower.contains('error'))) {
      resolvedOutput = '远程命令超时（主机忙或命令过慢）。可拆短命令后重试。\n原始错误: $resolvedOutput';
      success = false;
    }
    final result = ChatMessage(
      role: 'tool',
      content: resolvedOutput,
      kind: ChatKind.toolResult,
      meta: {
        'part': 'toolResult',
        'id': id,
        'name': resolvedName,
        'command': resolvedCommand,
        'description': resolvedDescription,
        'success': success,
        'output': resolvedOutput,
      },
      at: previous?.at,
    );
    if (index >= 0) {
      messages[index] = result;
    } else {
      messages.add(result);
    }
  }

  void sealPendingToolUse(String command, {required bool success, required String output}) {
    final normalizedCommand = command.trim();
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.kind != ChatKind.toolUse) continue;
      if (message.meta?['pendingConfirm'] != true && message.meta?['success'] != null) continue;
      final storedCommand = (message.meta?['command'] ?? '').toString().trim();
      if (normalizedCommand.isNotEmpty && storedCommand.isNotEmpty && storedCommand != normalizedCommand) {
        continue;
      }
      messages[i] = ChatMessage(
        role: message.role,
        content: success ? (output.isEmpty ? '完成' : output) : output,
        kind: ChatKind.toolUse,
        meta: {
          ...?message.meta,
          'pendingConfirm': false,
          'success': success,
          'output': output,
          'interrupted': false,
        },
        at: message.at,
      );
      if (normalizedCommand.isNotEmpty) break;
    }
  }

  int _firstAssistantTextIndexInTurn() {
    var index = messages.length;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role == 'user') break;
      if (message.role == 'assistant' && message.kind == ChatKind.text) index = i;
    }
    return index;
  }

  int _lastAssistantTextIndex() {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role == 'assistant' && message.kind == ChatKind.text) return i;
      if (message.role == 'user') break;
      if (message.kind == ChatKind.status || message.kind == ChatKind.reasoning) continue;
      break;
    }
    return -1;
  }

  bool _isOpenToolUse(ChatMessage message) {
    if (message.meta?['pendingConfirm'] == true) return false;
    if (message.kind == ChatKind.toolUse) return message.meta?['success'] == null;
    return message.meta?['part']?.toString() == 'toolUse' && message.meta?['success'] == null;
  }

  String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _newToolId() => 't${DateTime.now().microsecondsSinceEpoch}';
}
