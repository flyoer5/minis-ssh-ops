import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Agent chat — transcript UI inspired by agent CLIs (claude/codex style).
class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('后端未连接')));
      return;
    }
    if (state.selectedHostId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在「主机」页选择主机')));
      return;
    }
    _input.clear();
    setState(() => _busy = true);
    try {
      await state.agentChat(text);
      _scrollToEnd();
    } catch (_) {
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final host = state.hostLabel;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFE6EDF3),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              host,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '清空会话',
            onPressed: () => state.clearAgentChat(),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          // session bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF21262D),
            child: Text(
              state.agentSessionId == null
                  ? 'session: (new)  ·  model: ${state.llm?['model'] ?? '-'}'
                  : 'session: ${state.agentSessionId!.substring(0, 8)}…  ·  model: ${state.llm?['model'] ?? '-'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: state.agentMessages.isEmpty
                ? _EmptyHint(onExample: (s) {
                    _input.text = s;
                  })
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return const _TypingRow();
                      }
                      final m = state.agentMessages[i];
                      return _MessageBlock(
                        message: m,
                        busy: _busy,
                        onRunStep: (stepId, cmd, confirmed) async {
                          setState(() => _busy = true);
                          try {
                            await state.runAgentStep(
                              stepId: stepId,
                              command: cmd,
                              confirmed: confirmed,
                            );
                            _scrollToEnd();
                          } catch (_) {
                            _scrollToEnd();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                        onRunAllRead: () async {
                          setState(() => _busy = true);
                          try {
                            await state.runAllReadSteps();
                            _scrollToEnd();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                      );
                    },
                  ),
          ),
          // composer
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(top: BorderSide(color: Color(0xFF30363D))),
            ),
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 8,
              bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14),
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(state),
                    decoration: InputDecoration(
                      hintText: state.selectedHostId == null
                          ? '先选择主机，再描述运维目标…'
                          : '描述目标，例如：磁盘满了帮我只读排查…',
                      hintStyle: const TextStyle(color: Color(0xFF6E7681), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: cs.primary),
                      ),
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
                      : const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final ValueChanged<String> onExample;
  const _EmptyHint({required this.onExample});

  @override
  Widget build(BuildContext context) {
    const examples = [
      '只读检查：系统版本、磁盘与内存，给一句健康结论',
      '查一下谁占用磁盘最多（不要删除）',
      'nginx 是否在跑？最近错误日志最后 30 行',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.smart_toy_outlined, size: 40, color: Color(0xFF58A6FF)),
        const SizedBox(height: 12),
        const Text(
          'Agent 会话',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFE6EDF3), fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '用自然语言描述目标。Agent 会规划步骤，\n变更类命令需你确认后才会执行。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        ...examples.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF30363D)),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(12),
              ),
              onPressed: () => onExample(e),
              child: Text(e, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)),
          ),
          SizedBox(width: 10),
          Text('agent 思考 / 规划中…', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  final ChatMessage message;
  final bool busy;
  final Future<void> Function(int stepId, String cmd, bool confirmed) onRunStep;
  final Future<void> Function() onRunAllRead;

  const _MessageBlock({
    required this.message,
    required this.busy,
    required this.onRunStep,
    required this.onRunAllRead,
  });

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case ChatKind.plan:
        return _PlanCard(message: message, busy: busy, onRunStep: onRunStep, onRunAllRead: onRunAllRead);
      case ChatKind.stepResult:
        return _ToolResultCard(message: message);
      case ChatKind.error:
        return _Bubble(
          role: 'system',
          accent: const Color(0xFFF85149),
          child: SelectableText(message.content, style: const TextStyle(color: Color(0xFFF85149), fontSize: 13)),
        );
      case ChatKind.status:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '— ${message.content} —',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6E7681), fontSize: 11),
          ),
        );
      case ChatKind.text:
        final isUser = message.role == 'user';
        return _Bubble(
          role: isUser ? 'you' : 'agent',
          accent: isUser ? const Color(0xFF238636) : const Color(0xFF58A6FF),
          child: SelectableText(
            message.content,
            style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14, height: 1.4),
          ),
        );
    }
  }
}

class _Bubble extends StatelessWidget {
  final String role;
  final Color accent;
  final Widget child;
  const _Bubble({required this.role, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  role,
                  style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ChatMessage message;
  final bool busy;
  final Future<void> Function(int stepId, String cmd, bool confirmed) onRunStep;
  final Future<void> Function() onRunAllRead;

  const _PlanCard({
    required this.message,
    required this.busy,
    required this.onRunStep,
    required this.onRunAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final plan = message.meta?['plan'] as Map<String, dynamic>? ?? {};
    final steps = (plan['steps'] as List?) ?? [];
    final summary = plan['summary']?.toString() ?? message.content;
    final notes = plan['notes']?.toString() ?? '';
    final outputs = message.meta?['outputs'] as Map<String, dynamic>? ?? {};

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFF58A6FF)),
                SizedBox(width: 6),
                Text('plan', style: TextStyle(color: Color(0xFF58A6FF), fontFamily: 'monospace', fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(summary, style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14, fontWeight: FontWeight.w500)),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(notes, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ],
            const SizedBox(height: 10),
            ...steps.map((raw) {
              final st = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
              final id = st['id'];
              final stepId = id is int ? id : int.tryParse('$id') ?? 0;
              final risk = st['risk']?.toString() ?? 'read';
              final title = st['title']?.toString() ?? '';
              final command = st['command']?.toString() ?? '';
              final reason = st['reason']?.toString() ?? '';
              final out = outputs['step_$stepId']?.toString() ?? '';
              final riskColor = switch (risk) {
                'blocked' || 'destructive' => const Color(0xFFF85149),
                'write' => const Color(0xFFD29922),
                _ => const Color(0xFF3FB950),
              };
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF21262D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('#$stepId', style: const TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace', fontSize: 12)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: riskColor.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(risk, style: TextStyle(color: riskColor, fontSize: 10, fontFamily: 'monospace')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(title, style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(reason, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        '\$ $command',
                        style: const TextStyle(color: Color(0xFF79C0FF), fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    if (risk != 'blocked') ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (risk == 'read')
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFF21262D),
                                foregroundColor: const Color(0xFFE6EDF3),
                              ),
                              onPressed: busy ? null : () => onRunStep(stepId, command, false),
                              child: const Text('run'),
                            )
                          else ...[
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFF21262D),
                                foregroundColor: const Color(0xFFD29922),
                              ),
                              onPressed: busy ? null : () => onRunStep(stepId, command, true),
                              child: const Text('confirm & run'),
                            ),
                          ],
                          IconButton(
                            tooltip: '复制命令',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: command));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16, color: Color(0xFF8B949E)),
                          ),
                        ],
                      ),
                    ],
                    if (out.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        out,
                        style: const TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace', fontSize: 11),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (steps.any((s) => s is Map && (s['risk']?.toString() ?? 'read') == 'read'))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : onRunAllRead,
                  icon: const Icon(Icons.playlist_play, size: 18),
                  label: const Text('运行全部只读步骤'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolResultCard extends StatelessWidget {
  final ChatMessage message;
  const _ToolResultCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final exit = message.meta?['exitCode'];
    final risk = message.meta?['risk']?.toString() ?? '';
    final cmd = message.meta?['command']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF21262D)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'tool · exec  exit=$exit  risk=$risk',
              style: const TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace', fontSize: 11),
            ),
            if (cmd.isNotEmpty)
              Text('\$ $cmd', style: const TextStyle(color: Color(0xFF79C0FF), fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 6),
            SelectableText(
              message.content,
              style: const TextStyle(color: Color(0xFFC9D1D9), fontFamily: 'monospace', fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
