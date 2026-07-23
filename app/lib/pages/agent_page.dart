import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// OpenClaw-style agent: chat + tool results (model-driven tool loop).
class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _onlyCurrentHost = true;

  @override
  bool get wantKeepAlive => true;

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

  String _busyHint = '处理中…';

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('后端未连接')));
      return;
    }
    if (state.selectedHostId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先选主机')));
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _busyHint = '思考 / 调工具中…';
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HOSTKEY_MISMATCH') || msg.toLowerCase().contains('hostkey_mismatch')) {
        if (mounted) await _handleHostKeyMismatch(state);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom();
      }
    }
  }

  Future<void> _showSessions(AppState state) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        return StatefulBuilder(
          builder: (context, setModal) {
            final list = state.sessionsForHost(state.selectedHostId, onlyCurrent: _onlyCurrentHost);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('仅当前主机'),
                    value: _onlyCurrentHost,
                    onChanged: (v) {
                      setState(() => _onlyCurrentHost = v);
                      setModal(() {});
                    },
                  ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无历史会话（点新会话会归档当前对话）'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final s = list[i];
                          final hostHint = s.hostId == null ? '' : state.hostLabelFor(s.hostId);
                          return ListTile(
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${s.messages.length} 条${hostHint.isEmpty ? '' : ' · $hostHint'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              state.openAgentSession(s);
                              Navigator.pop(c);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                state.deleteAgentSession(s.id);
                                setModal(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        title: Text(
          state.selectedHostId == null ? 'Agent' : state.hostLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_busy || state.agentBusy)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () {
                state.cancelAgentChat();
                setState(() => _busy = false);
              },
              child: const Text('取消', style: TextStyle(fontSize: 13)),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '历史会话',
            onPressed: () => _showSessions(state),
            icon: const Icon(Icons.history, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '新会话',
            onPressed: (_busy || state.agentBusy)
                ? null
                : () {
                    state.clearAgentChat();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已开新会话'), duration: Duration(seconds: 1)),
                    );
                  },
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
                      state.selectedHostId == null ? '先选主机' : '发消息',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text(_busyHint, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                            ],
                          ),
                        );
                      }
                      final m = state.agentMessages[i];
                      // Key by tool id+part so toolUse→toolResult rebuilds fold state
                      final id = m.meta?['id']?.toString() ?? '${m.at.microsecondsSinceEpoch}';
                      final part = m.meta?['part']?.toString() ?? m.kind.name;
                      return _Bubble(
                        key: ValueKey('$id|$part|${m.role}|${m.content.hashCode}'),
                        msg: m,
                      );
                    },
                  ),
          ),
          // Minis-like composer
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0D1117),
                border: Border(top: BorderSide(color: Color(0xFF21262D))),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 6,
                      style: const TextStyle(fontSize: 15, color: Color(0xFFE6EDF3)),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(state),
                      decoration: InputDecoration(
                        hintText: state.selectedHostId == null ? '先选主机' : '消息',
                        hintStyle: const TextStyle(color: Color(0xFF6E7681)),
                        filled: true,
                        fillColor: const Color(0xFF161B22),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFF388BFD)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: (_busy || !state.backendOk || state.selectedHostId == null)
                        ? const Color(0xFF21262D)
                        : const Color(0xFF238636),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: (_busy || !state.backendOk || state.selectedHostId == null) ? null : () => _send(state),
                      icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleHostKeyMismatch(AppState state) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('主机密钥已变化'),
        content: const Text(
          '服务器 SSH 指纹与本地记录不一致（可能重装过系统，或存在中间人风险）。\n确认环境安全后，可清除旧记录并在下次连接时重新信任。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清除并重信')),
        ],
      ),
    );
    if (go == true) {
      try {
        await state.resetHostKeyForSelected();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除，请重试')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }
}

class _ConfirmPlanCard extends StatelessWidget {
  final ChatMessage msg;
  const _ConfirmPlanCard({required this.msg});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final plan = msg.meta?['plan'];
    final steps = plan is Map ? (plan['steps'] as List?) ?? [] : <dynamic>[];
    final outputs = (msg.meta?['outputs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
    if (steps.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD29922)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('需要确认的命令', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD29922))),
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[$risk] $cmd', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        if (out != null) ...[
                          const SizedBox(height: 4),
                          Text(out, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF8B949E))),
                        ] else
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: () async {
                                try {
                                  await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                  }
                                }
                              },
                              child: const Text('运行'),
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
  const _Bubble({super.key, required this.msg});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// Minis part types we mirror: text | toolUse | toolResult | reasoning
  String get _part {
    final p = msg.meta?['part']?.toString();
    if (p != null && p.isNotEmpty) return p;
    if (msg.kind == ChatKind.reasoning) return 'reasoning';
    if (msg.kind == ChatKind.stepResult) return 'toolResult';
    if (msg.role == 'tool' || msg.kind == ChatKind.status) return 'toolUse';
    if (msg.kind == ChatKind.error) return 'error';
    return 'text';
  }

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg);
    }

    final isUser = msg.role == 'user';
    final part = _part;

    // —— USER bubble ——
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.only(bottom: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            msg.content,
            style: const TextStyle(height: 1.4, color: Colors.white, fontSize: 14.5),
          ),
        ),
      );
    }

    // —— memory / generic status line ——
    if (msg.kind == ChatKind.status && part != 'toolUse') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(msg.content, style: const TextStyle(fontSize: 12.5, color: Color(0xFF8B949E))),
      );
    }

    // —— toolUse / toolResult (Minis) ——
    if (part == 'toolUse' || part == 'toolResult') {
      return _MinisToolBlock(msg: msg, part: part, onCopy: () => _copy(context, _copyText));
    }

    // —— reasoning (Minis messages.reasoning_content) ——
    if (msg.kind == ChatKind.reasoning || part == 'reasoning') {
      return _ReasoningBlock(content: msg.content, onCopy: () => _copy(context, msg.content));
    }

    // —— error ——
    if (msg.kind == ChatKind.error || part == 'error') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1214),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF6E2A2E)),
        ),
        child: _MdBody(data: msg.content, baseColor: const Color(0xFFFFB4A9), fontSize: 14),
      );
    }

    // —— text (assistant): Markdown ——
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 4),
      child: _MdBody(data: msg.content, baseColor: const Color(0xFFE6EDF3), fontSize: 15),
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
  final VoidCallback onCopy;
  const _MinisToolBlock({required this.msg, required this.part, required this.onCopy});

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

  String get _name => (widget.msg.meta?['name'] ?? 'tool').toString();
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
    final running = widget.part == 'toolUse' || widget.msg.kind == ChatKind.status;
    final success = _success;
    final Color accent;
    if (running && widget.part == 'toolUse') {
      accent = const Color(0xFFD29922);
    } else if (success == false) {
      accent = const Color(0xFFF85149);
    } else if (success == true) {
      accent = const Color(0xFF3FB950);
    } else {
      accent = const Color(0xFF79C0FF);
    }

    final body = _body.trim();
    final hasBody = body.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
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
                    child: Icon(
                      running
                          ? Icons.play_circle_outline
                          : (success == false ? Icons.error_outline : Icons.check_circle_outline),
                      size: 15,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // line1: tool name (like Minis shell_execute)
                        Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                        // line2: tool_title / description (Minis description)
                        if (_desc.isNotEmpty && _desc != _name) ...[
                          const SizedBox(height: 2),
                          Text(
                            _desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFFC9D1D9), height: 1.3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCopy,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_all, size: 14, color: Color(0xFF8B949E)),
                    ),
                  ),
                  if (hasBody)
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: const Color(0xFF8B949E),
                    ),
                ],
              ),
            ),
          ),
          if (hasBody && _open)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0D1117),
                border: Border(top: BorderSide(color: Color(0xFF21262D))),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SelectableText(
                body,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFFC9D1D9),
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
  final VoidCallback onCopy;
  const _ReasoningBlock({required this.content, required this.onCopy});

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
        color: const Color(0xFF12151C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3140)),
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
                  const Icon(Icons.psychology_outlined, size: 16, color: Color(0xFFA78BFA)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('思考', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFA78BFA))),
                        if (!_open && short.isNotEmpty)
                          Text(short, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B949E))),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCopy,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_all, size: 14, color: Color(0xFF8B949E)),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: const Color(0xFF8B949E)),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0D1117),
                border: Border(top: BorderSide(color: Color(0xFF21262D))),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SelectableText(
                widget.content,
                style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF9CA3AF), fontFamily: 'monospace'),
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
      listBullet: base.copyWith(color: const Color(0xFF8B949E)),
      listIndent: 20,
      blockquote: base.copyWith(color: const Color(0xFF8B949E)),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF30363D), width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize - 1.5,
        color: const Color(0xFFFF7B72),
        backgroundColor: const Color(0xFF21262D),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      a: base.copyWith(color: const Color(0xFF58A6FF), decoration: TextDecoration.underline),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: fontSize - 1),
      tableBorder: TableBorder.all(color: const Color(0xFF30363D), width: 0.5),
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
