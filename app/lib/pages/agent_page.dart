import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Normal chat UI — talk to agent like Claude/Codex CLI, not a "goal form".
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

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
      _toast('请先在主机页选一台机器');
      return;
    }
    _input.clear();
    setState(() => _busy = true);
    try {
      await state.agentChat(text);
    } catch (_) {
      // error already in transcript
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _jumpBottom();
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (state.agentMessages.isNotEmpty)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('清空对话？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
                          ],
                        ),
                      );
                      if (ok == true) state.clearAgentChat();
                    },
              child: const Text('清空'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.agentMessages.isEmpty
                ? _Welcome(
                    host: state.hostLabel,
                    onPick: (s) {
                      _input.text = s;
                      _focus.requestFocus();
                    },
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('思考中…', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ],
                          ),
                        );
                      }
                      return _ChatRow(
                        msg: state.agentMessages[i],
                        busy: _busy,
                        onRun: (stepId, cmd, confirmed) async {
                          setState(() => _busy = true);
                          try {
                            await state.runAgentStep(
                              stepId: stepId,
                              command: cmd,
                              confirmed: confirmed,
                            );
                          } catch (_) {
                          } finally {
                            if (mounted) {
                              setState(() => _busy = false);
                              _jumpBottom();
                            }
                          }
                        },
                        onRunReads: () async {
                          setState(() => _busy = true);
                          try {
                            await state.runAllReadSteps();
                          } finally {
                            if (mounted) {
                              setState(() => _busy = false);
                              _jumpBottom();
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
                crossAxisAlignment: CrossAxisAlignment.end,
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
                        hintText: state.selectedHostId == null
                            ? '先选主机，再发消息…'
                            : '发消息…',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy || !state.backendOk ? null : () => _send(state),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
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

class _Welcome extends StatelessWidget {
  final String host;
  final ValueChanged<String> onPick;
  const _Welcome({required this.host, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final tips = [
      '现在这台机器状态怎么样？',
      '磁盘快满了吗？帮我看看',
      '最近有没有异常日志？',
    ];
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.chat_bubble_outline, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            '和 Agent 对话',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            host,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '直接说你想做什么。需要改系统时会先让你确认。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          ...tips.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => onPick(t),
                child: Align(alignment: Alignment.centerLeft, child: Text(t)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd, bool confirmed) onRun;
  final Future<void> Function() onRunReads;

  const _ChatRow({
    required this.msg,
    required this.busy,
    required this.onRun,
    required this.onRunReads,
  });

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      return _PlanInChat(msg: msg, busy: busy, onRun: onRun, onRunReads: onRunReads);
    }
    if (msg.kind == ChatKind.stepResult) {
      return _ToolBlock(msg: msg);
    }
    if (msg.kind == ChatKind.status) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          msg.content,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final isUser = msg.role == 'user';
    final isError = msg.kind == ChatKind.error;
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : isError
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          msg.content,
          style: TextStyle(color: fg, fontSize: 15, height: 1.35),
        ),
      ),
    );
  }
}

class _PlanInChat extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd, bool confirmed) onRun;
  final Future<void> Function() onRunReads;

  const _PlanInChat({
    required this.msg,
    required this.busy,
    required this.onRun,
    required this.onRunReads,
  });

  @override
  Widget build(BuildContext context) {
    final plan = msg.meta?['plan'] as Map<String, dynamic>? ?? {};
    final steps = (plan['steps'] as List?) ?? [];
    final notes = plan['notes']?.toString() ?? '';
    final outputs = msg.meta?['outputs'] as Map<String, dynamic>? ?? {};
    final hasRead = steps.any((s) => s is Map && (s['risk']?.toString() ?? 'read') == 'read');

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
          Text(
            '建议步骤',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          ...steps.map((raw) {
            final st = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
            final id = st['id'];
            final stepId = id is int ? id : int.tryParse('$id') ?? 0;
            final risk = st['risk']?.toString() ?? 'read';
            final title = st['title']?.toString() ?? '';
            final command = st['command']?.toString() ?? '';
            final out = outputs['step_$stepId']?.toString() ?? '';
            final blocked = risk == 'blocked';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$stepId. $title', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        command,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    if (!blocked) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: busy
                                ? null
                                : () => onRun(stepId, command, risk != 'read'),
                            child: Text(risk == 'read' ? '执行' : '确认执行'),
                          ),
                          IconButton(
                            tooltip: '复制',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: command));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制'),
                                  duration: Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                        ],
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('已拦截（危险命令）', style: TextStyle(color: Colors.redAccent)),
                      ),
                    if (out.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        out,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (hasRead)
            TextButton(
              onPressed: busy ? null : onRunReads,
              child: const Text('执行全部只读步骤'),
            ),
        ],
      ),
    );
  }
}

class _ToolBlock extends StatelessWidget {
  final ChatMessage msg;
  const _ToolBlock({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cmd = msg.meta?['command']?.toString() ?? '';
    final exit = msg.meta?['exitCode'];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '执行结果 · exit $exit',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          if (cmd.isNotEmpty)
            Text(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 6),
          SelectableText(
            msg.content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}
