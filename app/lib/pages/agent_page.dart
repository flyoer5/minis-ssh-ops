import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

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
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk || state.selectedHostId == null) return;
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(state.selectedHostId == null ? '对话' : state.hostLabel, style: const TextStyle(fontSize: 15)),
        actions: [
          if (state.agentMessages.isNotEmpty)
            IconButton(
              onPressed: _busy ? null : () => state.clearAgentChat(),
              icon: const Icon(Icons.add_comment_outlined, size: 20),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.agentMessages.isEmpty
                ? Center(
                    child: Text(
                      state.selectedHostId == null ? '先选主机' : '',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      return _Row(
                        msg: state.agentMessages[i],
                        busy: _busy,
                        onConfirm: (id, cmd) async {
                          setState(() => _busy = true);
                          try {
                            await state.runAgentStep(stepId: id, command: cmd, confirmed: true);
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(state),
                      decoration: InputDecoration(
                        hintText: state.selectedHostId == null ? '先选主机' : null,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (_busy || !state.backendOk || state.selectedHostId == null) ? null : () => _send(state),
                    icon: const Icon(Icons.arrow_upward),
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

class _Row extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd) onConfirm;
  const _Row({required this.msg, required this.busy, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      final plan = msg.meta?['plan'] as Map<String, dynamic>? ?? {};
      final steps = (plan['steps'] as List?) ?? [];
      final writes = steps.where((s) {
        if (s is! Map) return false;
        final r = s['risk']?.toString() ?? '';
        return r == 'write' || r == 'destructive';
      }).toList();
      if (writes.isEmpty) return const SizedBox.shrink();
      return Column(
        children: writes.map((raw) {
          final st = Map<String, dynamic>.from(raw as Map);
          final id = st['id'];
          final stepId = id is int ? id : int.tryParse('$id') ?? 0;
          final cmd = st['command']?.toString() ?? '';
          return Card(
            child: ListTile(
              title: Text(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              trailing: FilledButton(
                onPressed: busy ? null : () => onConfirm(stepId, cmd),
                child: const Text('确认'),
              ),
            ),
          );
        }).toList(),
      );
    }

    if (msg.kind == ChatKind.stepResult) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(msg.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      );
    }

    if (msg.kind == ChatKind.status) {
      return const SizedBox.shrink();
    }

    final user = msg.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(msg.content, style: const TextStyle(fontSize: 15, height: 1.35)),
      ),
    );
  }
}
