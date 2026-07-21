import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Natural language Agent: plan → confirm → execute.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final goal = TextEditingController(text: '只读检查：系统版本、磁盘与内存，给一句健康结论，禁止修改。');
  final cmd = TextEditingController(text: 'uname -a');
  bool busy = false;
  String mode = 'agent'; // agent | cmd

  @override
  void dispose() {
    goal.dispose();
    cmd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hostLabel = _hostLabel(state);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 运维'),
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'agent', label: Text('Agent'), icon: Icon(Icons.smart_toy, size: 16)),
              ButtonSegment(value: 'cmd', label: Text('命令'), icon: Icon(Icons.terminal, size: 16)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('当前主机：$hostLabel', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (mode == 'agent') ...[
              Text(
                '用自然语言描述目标 → 生成计划 → 逐步确认执行（写操作会要求确认，危险命令拦截）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: goal,
                decoration: const InputDecoration(
                  labelText: '运维目标',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (!state.backendOk || busy || state.selectedHostId == null)
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await state.runAgentPlan(goal.text.trim());
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(busy ? '规划中…' : '生成计划'),
              ),
              const SizedBox(height: 12),
              Expanded(child: _PlanView(state: state, busy: busy, onBusy: (v) => setState(() => busy = v))),
            ] else ...[
              TextField(
                controller: cmd,
                decoration: const InputDecoration(labelText: 'Shell 命令', border: OutlineInputBorder()),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (!state.backendOk || busy || state.selectedHostId == null)
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await state.runExec(cmd.text.trim(), confirmed: false);
                        } catch (_) {
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.play_arrow),
                label: const Text('执行（只读直跑 / 变更需确认）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: (!state.backendOk || busy || state.selectedHostId == null)
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await state.runExec(cmd.text.trim(), confirmed: true);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('确认并执行（变更类）'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      state.lastExecOutput.isEmpty ? '输出在此显示' : state.lastExecOutput,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _hostLabel(AppState state) {
    if (state.selectedHostId == null) return '未选择';
    for (final h in state.hosts) {
      if (h is Map && h['id'] == state.selectedHostId) {
        return '${h['name'] ?? ''} (${h['username']}@${h['host']}:${h['port']})';
      }
    }
    return state.selectedHostId!;
  }
}

class _PlanView extends StatelessWidget {
  final AppState state;
  final bool busy;
  final ValueChanged<bool> onBusy;
  const _PlanView({required this.state, required this.busy, required this.onBusy});

  @override
  Widget build(BuildContext context) {
    final plan = state.lastPlan;
    if (plan == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(state.lastExecOutput.isEmpty ? '计划生成后显示在这里' : state.lastExecOutput),
      );
    }
    final steps = (plan['steps'] as List?) ?? [];
    final summary = plan['summary']?.toString() ?? '';
    final notes = plan['notes']?.toString() ?? '';
    return ListView(
      children: [
        if (summary.isNotEmpty) Text(summary, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(notes, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        ...steps.map((raw) {
          final st = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
          final id = st['id'];
          final risk = st['risk']?.toString() ?? 'read';
          final title = st['title']?.toString() ?? '';
          final command = st['command']?.toString() ?? '';
          final reason = st['reason']?.toString() ?? '';
          final outKey = 'step_$id';
          final out = state.stepOutputs[outKey] ?? '';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('#$id [$risk] $title', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (reason.isNotEmpty) Text(reason, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  SelectableText(command, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: busy
                            ? null
                            : () async {
                                onBusy(true);
                                try {
                                  await state.runAgentStep(
                                    stepId: id is int ? id : int.tryParse('$id') ?? 0,
                                    command: command,
                                    confirmed: false,
                                  );
                                } finally {
                                  onBusy(false);
                                }
                              },
                        child: const Text('执行'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                onBusy(true);
                                try {
                                  await state.runAgentStep(
                                    stepId: id is int ? id : int.tryParse('$id') ?? 0,
                                    command: command,
                                    confirmed: true,
                                  );
                                } finally {
                                  onBusy(false);
                                }
                              },
                        child: const Text('确认执行'),
                      ),
                    ],
                  ),
                  if (out.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(out, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
