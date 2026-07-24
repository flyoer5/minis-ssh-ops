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
        return '已拦截';
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
      await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
      if (continueAfter && context.mounted) {
        // Resume agent with the confirmed command result so the loop doesn't die at the wall.
        final out = state.stepOutputs['step_$stepId'] ?? '';
        final follow = StringBuffer()
          ..writeln('用户已确认并执行了以下命令：')
          ..writeln('```')
          ..writeln(cmd)
          ..writeln('```')
          ..writeln('结果：')
          ..writeln('```')
          ..writeln(out.isEmpty ? '(无输出)' : (out.length > 6000 ? '${out.substring(0, 6000)}…' : out))
          ..writeln('```')
          ..write('请根据结果继续完成用户目标，不要重复询问是否执行该命令。');
        await state.agentChat(follow.toString());
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
        if (raw is! Map) continue;
        final id = raw['id'];
        final stepId = id is int ? id : int.tryParse('$id') ?? 0;
        final cmd = raw['command']?.toString() ?? '';
        final out = (widget.msg.meta?['outputs'] as Map?)?['step_$stepId'];
        if (out == null && cmd.isNotEmpty) {
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
    final steps = plan is Map ? (plan['steps'] as List?) ?? [] : <dynamic>[];
    final outputs = (widget.msg.meta?['outputs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
    if (steps.isEmpty) return const SizedBox.shrink();
    final fs = widget.fontSize;
    final pendingCount = steps.where((raw) {
      if (raw is! Map) return false;
      final id = raw['id'];
      final stepId = id is int ? id : int.tryParse('$id') ?? 0;
      return outputs['step_$stepId'] == null;
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
                  onPressed: (_batchRunning || state.agentBusy)
                      ? null
                      : () => _runAll(context, state, steps),
                  child: Text(
                    _batchRunning ? '执行中…' : '全部运行',
                    style: TextStyle(fontSize: fs - 3, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (!allDone) ...[
            const SizedBox(height: 2),
            Text(
              state.confirmWrites
                  ? '开启了「写操作需确认」。点运行后会执行并让 Agent 继续。'
                  : '这些命令被策略标为需确认。点运行后会执行并让 Agent 继续。',
              style: TextStyle(fontSize: fs - 4, color: AppColors.textFaint, height: 1.3),
            ),
          ],
          const SizedBox(height: 8),
          for (final raw in steps)
            if (raw is Map)
              Builder(
                builder: (_) {
                  final id = raw['id'];
                  final stepId = id is int ? id : int.tryParse('$id') ?? 0;
                  final cmd = raw['command']?.toString() ?? '';
                  final risk = raw['risk']?.toString() ?? 'write';
                  final out = outputs['step_$stepId'];
                  final running = _running.contains(stepId) || (_batchRunning && out == null);
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
                        if (out != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SelectableText(
                              out,
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
                                                content: Text('已复制；可在终端自行执行'),
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

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final double fontSize;
  final bool streaming;
  const _Bubble({super.key, required this.msg, this.fontSize = 15, this.streaming = false});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// Minis part types: text | toolUse | toolResult | reasoning (kind first, meta legacy).
  String get _part {
    switch (msg.kind) {
      case ChatKind.toolUse:
        return 'toolUse';
      case ChatKind.toolResult:
      case ChatKind.stepResult:
        return 'toolResult';
      case ChatKind.reasoning:
        return 'reasoning';
      case ChatKind.error:
        return 'error';
      case ChatKind.plan:
        return 'plan';
      case ChatKind.status:
        final p = msg.meta?['part']?.toString();
        if (p == 'toolUse' || p == 'toolResult') return p!;
        return 'status';
      case ChatKind.text:
        final p = msg.meta?['part']?.toString();
        if (p == 'toolUse' || p == 'toolResult' || p == 'reasoning') return p!;
        return 'text';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = fontSize;
    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg, fontSize: fs);
    }

    final isUser = msg.role == 'user';
    final part = _part;

    // —— USER bubble ——
    if (isUser) {
      // Hide synthetic "continue after confirm" follow-ups from cluttering the chat.
      if (msg.content.startsWith('用户已确认并执行了以下命令：')) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已确认执行，Agent 继续中…',
                  style: TextStyle(fontSize: fs - 2.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        );
      }
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _copy(context, msg.content),
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            margin: const EdgeInsets.only(bottom: 8, left: 40),
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: fs > 16 ? 9 : 7),
            decoration: const BoxDecoration(
              color: AppColors.userBubble,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: SelectableText(
              msg.content,
              style: TextStyle(height: 1.35, color: Colors.white, fontSize: fs - 0.5),
            ),
          ),
        ),
      );
    }

    // —— toolUse / toolResult (Minis) ——
    if (part == 'toolUse' || part == 'toolResult') {
      return _MinisToolBlock(
        msg: msg,
        part: part,
        fontSize: fs,
        onCopy: () => _copy(context, _copyText),
      );
    }

    // —— memory / generic status line ——
    if (part == 'status' || msg.kind == ChatKind.status) {
      final stop = msg.meta?['interrupted'] == true || msg.content.contains('停止') || msg.content.contains('取消');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Row(
          children: [
            if (stop) ...[
              const Icon(Icons.stop_circle_outlined, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                msg.content,
                style: TextStyle(
                  fontSize: fs - 2.5,
                  color: stop ? AppColors.warning : AppColors.textMuted,
                  fontWeight: stop ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // —— reasoning (Minis messages.reasoning_content) ——
    if (msg.kind == ChatKind.reasoning || part == 'reasoning') {
      return _ReasoningBlock(
        content: msg.content,
        fontSize: fs,
        interrupted: msg.meta?['interrupted'] == true,
        onCopy: () => _copy(context, msg.content),
      );
    }

    // —— error ——
    if (msg.kind == ChatKind.error || part == 'error') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.errorPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.errorBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.dangerSoft),
                const SizedBox(width: 6),
                Text('出错了', style: TextStyle(fontSize: fs - 3, fontWeight: FontWeight.w700, color: AppColors.dangerSoft)),
                const Spacer(),
                InkWell(
                  onTap: () => _copy(context, msg.content),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _MdBody(data: msg.content, baseColor: AppColors.dangerSoft, fontSize: fs - 1),
          ],
        ),
      );
    }

    // Default: plain while streaming (less MD re-parse jitter). Final uses MD.
    // Settings → 流式 Markdown 可改为边流边渲。
    final streamMd = context.read<AppState>().streamMarkdown;
    final useMd = !streaming || streamMd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.meta?['interrupted'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('已中断', style: TextStyle(fontSize: fs - 4, color: AppColors.warning, fontWeight: FontWeight.w700)),
            ),
          if (useMd)
            _MdBody(data: msg.content, baseColor: AppColors.text, fontSize: fs)
          else
            SelectableText(
              msg.content,
              style: TextStyle(fontSize: fs, height: 1.45, color: AppColors.text),
            ),
          if (streaming)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _BlinkCursor(fontSize: fs),
            ),
        ],
      ),
    );
  }

  String get _copyText {
    final cmd = msg.meta?['command']?.toString() ?? '';
    if (cmd.isNotEmpty && msg.content.isNotEmpty) return '\$ $cmd\n${msg.content}';
    if (cmd.isNotEmpty) return cmd;
    return msg.content;
  }
}

/// Mirrors Minis message parts:
///   toolUse    → header: name + description, body: command (collapsed)
///   toolResult → header: name + success, body: output (expandable)
class _MinisToolBlock extends StatefulWidget {
  final ChatMessage msg;
  final String part;
  final double fontSize;
  final VoidCallback onCopy;
  const _MinisToolBlock({required this.msg, required this.part, required this.onCopy, this.fontSize = 15});

  @override
  State<_MinisToolBlock> createState() => _MinisToolBlockState();
}

class _MinisToolBlockState extends State<_MinisToolBlock> {
  late bool _open;
  bool _userToggled = false;

  /// Minis-like density:
  /// - toolUse (running): collapsed (header only: name + description)
  /// - toolResult success: collapsed by default (tap to see output)
  /// - toolResult failure: expanded so errors are visible
  bool _defaultOpen() {
    if (widget.part != 'toolResult') return false;
    final s = widget.msg.meta?['success'];
    final failed = s == false || s?.toString() == 'false';
    return failed;
  }

  @override
  void initState() {
    super.initState();
    _open = _defaultOpen();
  }

  @override
  void didUpdateWidget(covariant _MinisToolBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When stream merges toolUse → toolResult, re-apply default unless user toggled
    if (!_userToggled &&
        (oldWidget.part != widget.part ||
            oldWidget.msg.meta?['success'] != widget.msg.meta?['success'] ||
            oldWidget.msg.content != widget.msg.content)) {
      _open = _defaultOpen();
    }
  }

  String get _name {
    final raw = (widget.msg.meta?['name'] ?? 'tool').toString();
    switch (raw) {
      case 'run_command':
        return '执行命令';
      case 'probe_host':
        return '探测主机';
      default:
        return raw;
    }
  }

  String get _desc {
    final d = widget.msg.meta?['description']?.toString();
    if (d != null && d.isNotEmpty) return d;
    final c = widget.msg.meta?['command']?.toString() ?? '';
    if (c.isNotEmpty) return c.trim().split('\n').first;
    return widget.msg.content;
  }

  String get _command => (widget.msg.meta?['command'] ?? '').toString();

  bool? get _success {
    final s = widget.msg.meta?['success'];
    if (s is bool) return s;
    if (s == null) return null;
    return s.toString() == 'true';
  }

  bool get _pendingConfirm => widget.msg.meta?['pendingConfirm'] == true;

  String get _body {
    if (widget.part == 'toolUse') {
      // show command as body when present
      return _command;
    }
    // toolResult: content is pure output
    return widget.msg.content;
  }

  @override
  Widget build(BuildContext context) {
    final running = (widget.part == 'toolUse' || widget.msg.kind == ChatKind.toolUse) && !_pendingConfirm;
    final success = _success;
    final Color accent;
    if (_pendingConfirm) {
      accent = AppColors.warning;
    } else if (running && widget.part == 'toolUse') {
      accent = AppColors.warning;
    } else if (success == false) {
      accent = AppColors.danger;
    } else if (success == true) {
      accent = AppColors.success;
    } else {
      accent = AppColors.chipBlue;
    }

    final body = _body.trim();
    final hasBody = body.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _pendingConfirm ? AppColors.warning.withAlpha(0x66) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasBody
                ? () => setState(() {
                      _userToggled = true;
                      _open = !_open;
                    })
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: running
                        ? SizedBox(
                            width: (widget.fontSize - 1).clamp(12, 18).toDouble(),
                            height: (widget.fontSize - 1).clamp(12, 18).toDouble(),
                            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                          )
                        : Icon(
                            _pendingConfirm
                                ? Icons.shield_outlined
                                : (success == false ? Icons.error_outline : Icons.check_circle_outline),
                            size: (widget.fontSize - 1).clamp(12, 18).toDouble(),
                            color: accent,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // line1: tool name
                        Text(
                          _pendingConfirm ? '$_name · 待确认' : (running ? '$_name · 运行中' : _name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.fontSize - 3,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                        // line2: tool_title / description
                        if (_desc.isNotEmpty && _desc != _name) ...[
                          const SizedBox(height: 2),
                          Text(
                            _desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: widget.fontSize - 2.5, color: AppColors.textCode, height: 1.3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCopy,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                    ),
                  ),
                  if (hasBody)
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                ],
              ),
            ),
          ),
          if (hasBody && _open)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.surface2)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: SelectableText(
                body,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: widget.fontSize - 3,
                  height: 1.35,
                  color: AppColors.textCode,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Minis-like deep thinking: separate from answer, collapsed by default.
class _ReasoningBlock extends StatefulWidget {
  final String content;
  final double fontSize;
  final bool interrupted;
  final VoidCallback onCopy;
  const _ReasoningBlock({required this.content, required this.onCopy, this.fontSize = 15, this.interrupted = false});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = preview.length > 72 ? '${preview.substring(0, 72)}…' : preview;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.thinkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.thinkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 16, color: AppColors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('思考', style: TextStyle(fontSize: widget.fontSize - 3, fontWeight: FontWeight.w700, color: AppColors.purple)),
                            if (widget.interrupted) ...[
                              const SizedBox(width: 8),
                              Text('已中断', style: TextStyle(fontSize: widget.fontSize - 4, color: AppColors.warning, fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                        if (!_open && short.isNotEmpty)
                          Text(short, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: widget.fontSize - 3.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCopy,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.surface2)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: widget.fontSize - 2,
                  height: 1.45,
                  color: AppColors.monoGray,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MdBody extends StatelessWidget {
  final String data;
  final Color baseColor;
  final double fontSize;
  const _MdBody({required this.data, required this.baseColor, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, height: 1.55, color: baseColor);
    final style = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: base.copyWith(fontSize: fontSize + 6, fontWeight: FontWeight.w800),
      h2: base.copyWith(fontSize: fontSize + 4, fontWeight: FontWeight.w800),
      h3: base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
      strong: base.copyWith(fontWeight: FontWeight.w800),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: AppColors.textMuted),
      listIndent: 20,
      blockquote: base.copyWith(color: AppColors.textMuted),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize - 1.5,
        color: AppColors.codeRed,
        backgroundColor: AppColors.surface2,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      a: base.copyWith(color: AppColors.accentSoft, decoration: TextDecoration.underline),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: fontSize - 1),
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      blockSpacing: 8,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: style,
      shrinkWrap: true,
      fitContent: true,
      onTapLink: (text, href, title) {},
    );
  }
}

/// Blinking block cursor for streaming assistant text.
class _BlinkCursor extends StatefulWidget {
  final double fontSize;
  const _BlinkCursor({this.fontSize = 15});

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 530))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.15, end: 1.0).animate(_c),
      child: Text(
        '█',
        style: TextStyle(fontSize: widget.fontSize, color: AppColors.accentSoft, height: 1),
      ),
    );
  }
}
