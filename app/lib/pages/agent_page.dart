import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Pure chat with agent.
class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk) {
      _toast('后端未连接');
      return;
    }
    if (state.selectedHostId == null) {
      _toast('请先选择主机');
      return;
    }
    _input.clear();
    setState(() => _busy = true);
    try {
      await state.agentChat(text);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom();
        _focus.requestFocus();
      }
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('对话'),
            Text(
              state.hostLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (state.agentMessages.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => state.clearAgentChat(),
              child: const Text('新会话'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.agentMessages.isEmpty
                ? const _Empty()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('…', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        );
                      }
                      return _Bubble(
                        msg: state.agentMessages[i],
                        busy: _busy,
                        onConfirm: (stepId, cmd) async {
                          setState(() => _busy = true);
                          try {
                            await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
                          } catch (_) {
                          } finally {
                            if (mounted) {
                              setState(() => _busy = false);
                              _bottom();
                            }
                          }
                        },
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(state),
                      decoration: InputDecoration(
                        hintText: state.selectedHostId == null ? '先选主机…' : '输入消息',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy || !state.backendOk ? null : () => _send(state),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '发消息开始',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd) onConfirm;

  const _Bubble({required this.msg, required this.busy, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.status) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          msg.content,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    // Pending write actions as compact confirm chips
    if (msg.kind == ChatKind.plan) {
      final plan = msg.meta?['plan'] as Map<String, dynamic>? ?? {};
      final steps = (plan['steps'] as List?) ?? [];
      final writes = steps.where((s) {
        if (s is! Map) return false;
        final r = s['risk']?.toString() ?? '';
        return r == 'write' || r == 'destructive';
      }).toList();
      if (writes.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...writes.map((raw) {
              final st = Map<String, dynamic>.from(raw as Map);
              final id = st['id'];
              final stepId = id is int ? id : int.tryParse('$id') ?? 0;
              final cmd = st['command']?.toString() ?? '';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: FilledButton(
                  onPressed: busy ? null : () => onConfirm(stepId, cmd),
                  child: const Text('确认'),
                ),
              );
            }),
          ],
        ),
      );
    }

    if (msg.kind == ChatKind.stepResult) {
      // show as collapsed code-like assistant tool output
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            msg.content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.3),
          ),
        ),
      );
    }

    final isUser = msg.role == 'user';
    final isErr = msg.kind == ChatKind.error;
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : isErr
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : isErr
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(msg.content, style: TextStyle(color: fg, fontSize: 15, height: 1.35)),
      ),
    );
  }
}
