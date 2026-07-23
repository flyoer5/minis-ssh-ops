import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      appBar: AppBar(
        title: Text(
          state.selectedHostId == null ? 'Agent' : state.hostLabel,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (_busy || state.agentBusy)
            TextButton(
              onPressed: () {
                state.cancelAgentChat();
                setState(() => _busy = false);
              },
              child: const Text('取消'),
            ),
          IconButton(
            tooltip: '历史会话',
            onPressed: () => _showSessions(state),
            icon: const Icon(Icons.history, size: 20),
          ),
          IconButton(
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
                      return _Bubble(msg: state.agentMessages[i]);
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
                      maxLines: 5,
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
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg);
    }

    final isUser = msg.role == 'user';
    final isToolResult = msg.kind == ChatKind.stepResult || (msg.role == 'tool' && msg.kind != ChatKind.status);
    final isStatus = msg.kind == ChatKind.status;
    final isErr = msg.kind == ChatKind.error;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(msg.content, style: const TextStyle(height: 1.4, color: Colors.white, fontSize: 15)),
        ),
      );
    }

    // Parse tool output " $ cmd\nresult"
    String? toolCmd;
    String body = msg.content;
    if (isToolResult || msg.role == 'tool') {
      final lines = msg.content.split('\n');
      if (lines.isNotEmpty && (lines.first.startsWith(r'$ ') || lines.first.startsWith('›'))) {
        toolCmd = lines.first.replaceFirst(RegExp(r'^[›$]\s*'), '');
        body = lines.skip(1).join('\n');
      }
    }

    if (isStatus && toolCmd == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle))),
            const SizedBox(width: 8),
            Expanded(child: Text(msg.content, style: const TextStyle(fontSize: 12, color: Color(0xFFD97706)))),
          ],
        ),
      );
    }

    // Minis-style assistant / tool card
    final accent = isErr
        ? const Color(0xFFEF4444)
        : (isToolResult || msg.role == 'tool')
            ? const Color(0xFF38BDF8)
            : const Color(0xFF22C55E);
    final label = isErr
        ? 'error'
        : (isToolResult || msg.role == 'tool')
            ? 'tool'
            : 'assistant';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF111827),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(0x33),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withAlpha(0x66)),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
                ),
                if (toolCmd != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      toolCmd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ] else
                  const Spacer(),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: msg.content));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
                  child: const Icon(Icons.copy_all, size: 15, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          if (body.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SelectableText(
                body,
                style: TextStyle(
                  height: 1.45,
                  fontSize: (isToolResult || msg.role == 'tool') ? 12.5 : 14.5,
                  fontFamily: (isToolResult || msg.role == 'tool') ? 'monospace' : null,
                  color: isErr ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
