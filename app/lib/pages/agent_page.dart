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
      backgroundColor: const Color(0xFF0D1117),
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
  const _Bubble({required this.msg});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg);
    }

    final isUser = msg.role == 'user';
    final isTool = msg.role == 'tool' || msg.kind == ChatKind.stepResult;
    final isStatus = msg.kind == ChatKind.status;
    final isErr = msg.kind == ChatKind.error;

    // —— USER (Minis-like right bubble) ——
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          margin: const EdgeInsets.only(bottom: 12, left: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF2B5CFF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            msg.content,
            style: const TextStyle(height: 1.4, color: Colors.white, fontSize: 15),
          ),
        ),
      );
    }

    // —— STATUS (compact Minis "working" line) ——
    if (isStatus && !isTool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFFD97706)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg.content,
                style: const TextStyle(fontSize: 13, color: Color(0xFFD97706), height: 1.3),
              ),
            ),
          ],
        ),
      );
    }

    // —— TOOL call / result (Minis tool block) ——
    if (isTool || (isStatus && msg.meta != null)) {
      final name = msg.meta?['name']?.toString() ?? 'tool';
      final command = msg.meta?['command']?.toString() ?? '';
      String headerCmd = command;
      String body = msg.content;
      if (msg.content.startsWith(r'$ ')) {
        final nl = msg.content.indexOf('\n');
        if (nl >= 0) {
          headerCmd = msg.content.substring(2, nl);
          body = msg.content.substring(nl + 1);
        } else {
          headerCmd = msg.content.substring(2);
          body = '';
        }
      } else if (msg.kind == ChatKind.status) {
        body = '';
      }
      final running = msg.kind == ChatKind.status || body.isEmpty && command.isNotEmpty;
      final title = name == 'probe_host' ? 'probe_host' : (name.isEmpty ? 'run_command' : name);

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // tool chrome — like Minis skill/tool strip
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F6FEB).withAlpha(0x33),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1F6FEB).withAlpha(0x66)),
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF79C0FF), fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerCmd.isEmpty ? (running ? 'running…' : '') : headerCmd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF8B949E)),
                    ),
                  ),
                  if (msg.content.trim().isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _copy(context, msg.content),
                      icon: const Icon(Icons.copy_all, size: 14, color: Color(0xFF8B949E)),
                    ),
                ],
              ),
            ),
            if (body.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                color: const Color(0xFF0D1117),
                child: SelectableText(
                  body,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFFC9D1D9),
                  ),
                ),
              )
            else if (running)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Text('…', style: TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace')),
              ),
          ],
        ),
      );
    }

    // —— ASSISTANT / ERROR (Minis prose, minimal chrome) ——
    if (isErr) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1214),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6E2A2E)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: Color(0xFFF85149)),
                const SizedBox(width: 6),
                const Text('error', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF85149))),
                const Spacer(),
                InkWell(
                  onTap: () => _copy(context, msg.content),
                  child: const Icon(Icons.copy_all, size: 14, color: Color(0xFF8B949E)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              msg.content,
              style: const TextStyle(height: 1.45, fontSize: 14.5, color: Color(0xFFFFB4A9)),
            ),
          ],
        ),
      );
    }

    // plain assistant — Minis style: avatar-less, clean left text block
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Center(
              child: Text('A', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF3FB950))),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Assistant', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B949E))),
                    const Spacer(),
                    InkWell(
                      onTap: () => _copy(context, msg.content),
                      child: const Icon(Icons.copy_all, size: 14, color: Color(0xFF8B949E)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  msg.content,
                  style: const TextStyle(height: 1.5, fontSize: 15, color: Color(0xFFE6EDF3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
