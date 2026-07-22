import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Chat + proposed command cards (rssh: AI proposes, user Run).
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
        title: Text(
          state.selectedHostId == null ? '对话' : state.hostLabel,
          style: const TextStyle(fontSize: 15),
        ),
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
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return _Msg(
                        msg: state.agentMessages[i],
                        busy: _busy,
                        onRun: (stepId, cmd) async {
                          setState(() => _busy = true);
                          try {
                            // rssh: explicit Run always confirmed by click
                            await state.runAgentStep(
                              stepId: stepId,
                              command: cmd,
                              confirmed: true,
                            );
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
                    onPressed: (_busy || !state.backendOk || state.selectedHostId == null)
                        ? null
                        : () => _send(state),
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

class _Msg extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd) onRun;

  const _Msg({required this.msg, required this.busy, required this.onRun});

  Color _riskColor(String risk) {
    switch (risk) {
      case 'write':
        return Colors.orange;
      case 'destructive':
        return Colors.redAccent;
      case 'blocked':
        return Colors.grey;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Proposed command cards (rssh)
    if (msg.kind == ChatKind.plan) {
      final plan = msg.meta?['plan'] as Map<String, dynamic>? ?? {};
      final steps = (plan['steps'] as List?) ?? [];
      if (steps.isEmpty) return const SizedBox.shrink();
      final outputs = Map<String, dynamic>.from(msg.meta?['outputs'] as Map? ?? {});

      return Column(
        children: steps.map((raw) {
          if (raw is! Map) return const SizedBox.shrink();
          final st = Map<String, dynamic>.from(raw);
          final id = st['id'];
          final stepId = id is int ? id : int.tryParse('$id') ?? 0;
          final cmd = st['command']?.toString() ?? '';
          final title = st['title']?.toString() ?? '';
          final risk = st['risk']?.toString() ?? 'read';
          final outKey = 'step_$stepId';
          final ran = outputs.containsKey(outKey);
          final out = outputs[outKey]?.toString() ?? '';
          final blocked = risk == 'blocked';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _riskColor(risk),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title.isNotEmpty)
                              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            SelectableText(
                              cmd,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                            Text(
                              risk,
                              style: TextStyle(fontSize: 11, color: _riskColor(risk)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '复制',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cmd));
                        },
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      if (!blocked)
                        FilledButton(
                          onPressed: (busy || ran) ? null : () => onRun(stepId, cmd),
                          child: Text(ran ? '已运行' : '运行'),
                        ),
                    ],
                  ),
                  if (out.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        out,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    if (msg.kind == ChatKind.stepResult || msg.kind == ChatKind.status) {
      return const SizedBox.shrink();
    }

    final user = msg.role == 'user';
    final err = msg.kind == ChatKind.error;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : err
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(msg.content, style: const TextStyle(fontSize: 15, height: 1.35)),
      ),
    );
  }
}
