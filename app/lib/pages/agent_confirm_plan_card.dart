part of 'agent_page.dart';

class _ConfirmPlanCard extends StatefulWidget {
  final ChatMessage msg;
  final double fontSize;

  const _ConfirmPlanCard({required this.msg, this.fontSize = 15});

  @override
  State<_ConfirmPlanCard> createState() => _ConfirmPlanCardState();
}

class _ConfirmPlanCardState extends State<_ConfirmPlanCard> {
  final Set<int> _running = {};
  bool _batchRunning = false;

  String _riskLabel(String risk) {
    switch (risk.toLowerCase()) {
      case 'destructive':
        return '破坏性';
      case 'write':
        return '写操作';
      case 'blocked':
        return '已阻断';
      case 'read':
        return '只读';
      default:
        return risk.isEmpty ? '写操作' : risk;
    }
  }

  Color _riskColor(String risk) {
    switch (risk.toLowerCase()) {
      case 'destructive':
        return AppColors.danger;
      case 'write':
        return AppColors.warning;
      case 'blocked':
        return AppColors.danger;
      default:
        return AppColors.accentSoft;
    }
  }

  int _stepIdOf(dynamic raw) {
    if (raw is Map) {
      final id = raw['id'];
      if (id is int) return id;
      if (id != null) return int.tryParse(id.toString()) ?? 0;
    }
    return 0;
  }

  String _stepCommandOf(dynamic raw) {
    if (raw is Map) {
      return raw['command']?.toString() ?? '';
    }
    return '';
  }

  String _stepRiskOf(dynamic raw) {
    if (raw is Map) {
      return raw['risk']?.toString() ?? 'write';
    }
    return 'write';
  }

  Map<String, dynamic>? _resultFor(AppState state, int stepId) {
    final res = state.stepResults[stepId];
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  String _resultText(Map<String, dynamic>? result) {
    if (result == null) return '';
    final stdout = (result['stdout'] ?? '').toString().trim();
    final stderr = (result['stderr'] ?? '').toString().trim();
    final exitCode = result['exitCode'];
    final parts = <String>[];
    if (stdout.isNotEmpty) parts.add(stdout);
    if (stderr.isNotEmpty && stderr != stdout) parts.add('stderr:\n$stderr');
    if (exitCode != null) parts.add('exitCode: $exitCode');
    return parts.join('\n\n');
  }

  bool _isBlocked(Map<String, dynamic>? result) {
    if (result == null) return false;
    final risk = (result['risk'] ?? '').toString().toLowerCase();
    final exitCode = result['exitCode'];
    final stderr = (result['stderr'] ?? '').toString().toLowerCase();
    if (risk == 'blocked') return true;
    if (stderr.contains('needs_confirm')) return true;
    if (exitCode is int && exitCode != 0) return false;
    return false;
  }

  Future<void> _runOne(
    BuildContext context,
    AppState state, {
    required int stepId,
    required String cmd,
    required bool continueAfter,
  }) async {
    if (_running.contains(stepId) || _batchRunning) return;
    setState(() => _running.add(stepId));
    try {
      if (state.hapticFeedback) {
        HapticFeedback.lightImpact();
      }
      final res = await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
      final result = Map<String, dynamic>.from(res);
      if (!context.mounted) return;
      if (_isBlocked(result)) {
        showSnack(context, '该步骤被阻断，未继续执行');
        return;
      }
      if (continueAfter) {
        final out = _resultText(result);
        final follow = StringBuffer()
          ..writeln('用户已确认并执行以下命令：')
          ..writeln('```bash')
          ..writeln(cmd)
          ..writeln('```')
          ..writeln('结果：')
          ..writeln('```')
          ..writeln(out.isEmpty ? '(无输出)' : (out.length > 6000 ? '${out.substring(0, 6000)}...' : out))
          ..writeln('```')
          ..write('请根据结果继续完成用户目标，不要重复询问是否执行该命令。');
        await state.agentChat(follow.toString());
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, cleanError(e));
      }
    } finally {
      if (mounted) setState(() => _running.remove(stepId));
    }
  }

  Future<void> _runAll(BuildContext context, AppState state, List steps) async {
    if (_batchRunning) return;
    setState(() => _batchRunning = true);
    try {
      final pending = <Map<String, dynamic>>[];
      for (final raw in steps) {
        final stepId = _stepIdOf(raw);
        final cmd = _stepCommandOf(raw);
        if (stepId <= 0 || cmd.isEmpty) continue;
        if (_resultFor(state, stepId) == null) {
          pending.add({'id': stepId, 'cmd': cmd});
        }
      }
      for (var i = 0; i < pending.length; i++) {
        final stepId = pending[i]['id'] as int;
        final cmd = pending[i]['cmd'] as String;
        final isLast = i == pending.length - 1;
        await _runOne(context, state, stepId: stepId, cmd: cmd, continueAfter: isLast);
        if (!context.mounted) return;
      }
    } finally {
      if (mounted) setState(() => _batchRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = widget.msg.meta?['plan'];
    final steps = plan is Map ? (plan['steps'] as List?) ?? const [] : const [];
    if (steps.isEmpty) return const SizedBox.shrink();

    final fs = widget.fontSize;
    final pendingCount = steps.where((raw) {
      final stepId = _stepIdOf(raw);
      return stepId > 0 && _resultFor(state, stepId) == null;
    }).length;
    final allDone = pendingCount == 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  allDone ? '已确认执行' : '需要确认的命令',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: fs - 2, color: AppColors.warning),
                ),
              ),
              if (!allDone && steps.length > 1)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: (_batchRunning || state.agentBusy) ? null : () => _runAll(context, state, steps),
                  child: Text(
                    _batchRunning ? '执行中...' : '全部运行',
                    style: TextStyle(fontSize: fs - 3, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (!allDone) ...[
            const SizedBox(height: 2),
            Text(
              state.confirmWrites
                  ? '已开启“写操作需确认”。点击运行后会执行并继续让 Agent 处理后续步骤。'
                  : '这些命令被策略标记为需要确认。点击运行后会执行并继续让 Agent 处理后续步骤。',
              style: TextStyle(fontSize: fs - 4, color: AppColors.textFaint, height: 1.3),
            ),
          ],
          const SizedBox(height: 8),
          for (final raw in steps)
            if (raw is Map)
              Builder(
                builder: (_) {
                  final stepId = _stepIdOf(raw);
                  final cmd = _stepCommandOf(raw);
                  final risk = _stepRiskOf(raw);
                  final result = _resultFor(state, stepId);
                  final running = _running.contains(stepId) || (_batchRunning && result == null);
                  final riskColor = _riskColor(risk);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.surface2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: riskColor.withAlpha(0x28),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _riskLabel(risk),
                                style: TextStyle(
                                  fontSize: fs - 5,
                                  fontWeight: FontWeight.w700,
                                  color: riskColor,
                                ),
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: cmd));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制命令'), duration: Duration(seconds: 1)),
                                  );
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          cmd,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: fs - 3,
                            color: AppColors.textCode,
                            height: 1.35,
                          ),
                        ),
                        if (result != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SelectableText(
                              _resultText(result),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: fs - 4,
                                color: AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: AppColors.textMuted,
                                  ),
                                  onPressed: running
                                      ? null
                                      : () async {
                                          await Clipboard.setData(ClipboardData(text: cmd));
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('已复制；可在终端手动执行'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          }
                                        },
                                  child: Text('仅复制', style: TextStyle(fontSize: fs - 3)),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: riskColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  onPressed: (running || state.agentBusy)
                                      ? null
                                      : () => _runOne(
                                            context,
                                            state,
                                            stepId: stepId,
                                            cmd: cmd,
                                            continueAfter: true,
                                          ),
                                  icon: running
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.play_arrow, size: 16),
                                  label: Text(
                                    running ? '执行中' : '运行并继续',
                                    style: TextStyle(fontSize: fs - 3, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
