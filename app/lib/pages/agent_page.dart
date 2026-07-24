import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
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
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) {
        return StatefulBuilder(
          builder: (context, setModal) {
            final list = state.sessionsForHost(state.selectedHostId, onlyCurrent: _onlyCurrentHost);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.58,
              maxChildSize: 0.9,
              minChildSize: 0.35,
              builder: (_, sc) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('历史会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              SizedBox(height: 4),
                              Text(
                                '点「新会话」会归档当前对话；点条目恢复；可重命名或删除。',
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('仅当前主机', style: TextStyle(fontSize: 14)),
                    value: _onlyCurrentHost,
                    onChanged: (v) {
                      setState(() => _onlyCurrentHost = v);
                      setModal(() {});
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        list.isEmpty ? '暂无归档会话' : '共 ${list.length} 个',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '还没有历史。发几条消息后点「新会话」即可归档。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ),
                          )
                        : Builder(
                            builder: (_) {
                              // Group by host: [(label, [sessions...]), ...]
                              final groups = <String, List<AgentSession>>{};
                              final order = <String>[];
                              for (final s in list) {
                                final key = s.hostId ?? '';
                                final label = key.isEmpty
                                    ? '未绑定主机'
                                    : (state.hostLabelFor(key).isEmpty ? key : state.hostLabelFor(key));
                                if (!groups.containsKey(label)) {
                                  groups[label] = [];
                                  order.add(label);
                                }
                                groups[label]!.add(s);
                              }
                              // flat rows: header | tiles
                              final rows = <Object>[];
                              for (final label in order) {
                                rows.add(label);
                                rows.addAll(groups[label]!);
                              }
                              return ListView.builder(
                                controller: sc,
                                itemCount: rows.length,
                                itemBuilder: (_, i) {
                                  final row = rows[i];
                                  if (row is String) {
                                    return Container(
                                      width: double.infinity,
                                      color: AppColors.bg,
                                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                                      child: Text(
                                        row,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.chipBlue,
                                        ),
                                      ),
                                    );
                                  }
                                  final s = row as AgentSession;
                                  final hostHint = s.hostId == null ? '' : state.hostLabelFor(s.hostId);
                                  final open = state.agentSessionId == s.id;
                                  final when = s.updatedAt;
                                  final ts =
                                      '${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
                                      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
                                  return Column(
                                    children: [
                                      ListTile(
                                        dense: true,
                                        selected: open,
                                        selectedTileColor: AppColors.accentDeep.withAlpha(0x18),
                                        title: Text(
                                          s.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: open ? FontWeight.w700 : FontWeight.w500,
                                            color: open ? AppColors.accentSoft : null,
                                          ),
                                        ),
                                        subtitle: Text(
                                          [
                                            '${s.messages.length} 条',
                                            if (hostHint.isNotEmpty && _onlyCurrentHost) hostHint,
                                            ts,
                                            if (open) '当前',
                                          ].join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                        ),
                                        onTap: () {
                                          state.openAgentSession(s);
                                          Navigator.pop(c);
                                        },
                                        trailing: PopupMenuButton<String>(
                                          tooltip: '更多',
                                          icon: const Icon(Icons.more_vert, size: 20),
                                          color: AppColors.surface,
                                          onSelected: (v) async {
                                            if (v == 'rename') {
                                              final ctrl = TextEditingController(text: s.title);
                                              final name = await showDialog<String>(
                                                context: context,
                                                builder: (d) => AlertDialog(
                                                  title: const Text('重命名会话'),
                                                  content: TextField(
                                                    controller: ctrl,
                                                    autofocus: true,
                                                    maxLength: 48,
                                                    decoration: const InputDecoration(labelText: '标题'),
                                                    onSubmitted: (x) => Navigator.pop(d, x),
                                                  ),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                                                    FilledButton(
                                                      onPressed: () => Navigator.pop(d, ctrl.text),
                                                      child: const Text('保存'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (name != null && name.trim().isNotEmpty) {
                                                state.renameAgentSession(s.id, name);
                                                setModal(() {});
                                              }
                                            } else if (v == 'delete') {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (d) => AlertDialog(
                                                  title: const Text('删除会话？'),
                                                  content: Text(s.title, maxLines: 3),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                                    FilledButton(
                                                      onPressed: () => Navigator.pop(d, true),
                                                      child: const Text('删除'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                state.deleteAgentSession(s.id);
                                                setModal(() {});
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除', style: TextStyle(color: AppColors.danger)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1, color: AppColors.surface2),
                                    ],
                                  );
                                },
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        title: Text(
          state.selectedHostId == null ? 'Agent' : state.hostLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_busy || state.agentBusy)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.danger,
                ),
                onPressed: () => _stopGeneration(state),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('停止', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '历史会话',
            onPressed: (_busy || state.agentBusy) ? null : () => _showSessions(state),
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
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    itemCount: state.agentMessages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && i == state.agentMessages.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentSoft),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _busyHint,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: AppColors.danger,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () => _stopGeneration(state),
                                child: const Text('停止', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        );
                      }
                      final m = state.agentMessages[i];
                      // Stable key (no content hash) so token stream doesn't rebuild tree every delta
                      final id = m.meta?['id']?.toString() ?? '${m.at.microsecondsSinceEpoch}';
                      final part = m.meta?['part']?.toString() ?? m.kind.name;
                      final streaming = _busy &&
                          i == state.agentMessages.length - 1 &&
                          (part == 'text_delta' || part == 'text' || part == 'reasoning');
                      return _Bubble(
                        key: ValueKey('$id|$part|${m.role}'),
                        msg: m,
                        fontSize: state.agentFontSize,
                        streaming: streaming,
                      );
                    },
                  ),
          ),
          // Minis-like composer
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.surface2)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: !(_busy || state.agentBusy),
                      minLines: 1,
                      maxLines: 6,
                      style: TextStyle(fontSize: state.agentFontSize, color: AppColors.text),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (!(_busy || state.agentBusy)) _send(state);
                      },
                      decoration: InputDecoration(
                        hintText: state.selectedHostId == null
                            ? '先选主机'
                            : ((_busy || state.agentBusy) ? '生成中…点停止可中断' : '消息'),
                        hintStyle: const TextStyle(color: AppColors.textFaint),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: AppColors.linkFocus),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send ↔ Stop toggle
                  Material(
                    color: (_busy || state.agentBusy)
                        ? AppColors.danger
                        : ((!state.backendOk || state.selectedHostId == null)
                            ? AppColors.surface2
                            : AppColors.sendGreen),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: (_busy || state.agentBusy) ? '停止生成' : '发送',
                      onPressed: (!state.backendOk || state.selectedHostId == null)
                          ? null
                          : () {
                              if (_busy || state.agentBusy) {
                                _stopGeneration(state);
                              } else {
                                _send(state);
                              }
                            },
                      icon: Icon(
                        (_busy || state.agentBusy) ? Icons.stop_rounded : Icons.arrow_upward,
                        color: Colors.white,
                        size: 20,
                      ),
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

  void _stopGeneration(AppState state) {
    state.cancelAgentChat();
    if (mounted) setState(() {
      _busy = false;
      _busyHint = '已停止';
    });
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
  final double fontSize;
  const _ConfirmPlanCard({required this.msg, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final plan = msg.meta?['plan'];
    final steps = plan is Map ? (plan['steps'] as List?) ?? [] : <dynamic>[];
    final outputs = (msg.meta?['outputs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
    if (steps.isEmpty) return const SizedBox.shrink();
    final fs = fontSize;
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
          Text('需要确认的命令', style: TextStyle(fontWeight: FontWeight.w700, fontSize: fs - 2, color: AppColors.warning)),
          const SizedBox(height: 6),
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
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[$risk] $cmd', style: TextStyle(fontFamily: 'monospace', fontSize: fs - 3, color: AppColors.textCode)),
                        if (out != null) ...[
                          const SizedBox(height: 3),
                          Text(out, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 4, color: AppColors.textMuted)),
                        ] else
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              onPressed: () async {
                                try {
                                  await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                  }
                                }
                              },
                              child: Text('运行', style: TextStyle(fontSize: fs - 3)),
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
    final fs = fontSize;
    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg, fontSize: fs);
    }

    final isUser = msg.role == 'user';
    final part = _part;

    // —— USER bubble ——
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
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
      );
    }

    // —— memory / generic status line ——
    if (msg.kind == ChatKind.status && part != 'toolUse') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(msg.content, style: TextStyle(fontSize: fs - 2.5, color: AppColors.textMuted)),
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

    // —— reasoning (Minis messages.reasoning_content) ——
    if (msg.kind == ChatKind.reasoning || part == 'reasoning') {
      return _ReasoningBlock(
        content: msg.content,
        fontSize: fs,
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
        child: _MdBody(data: msg.content, baseColor: AppColors.dangerSoft, fontSize: fs - 1),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MdBody(data: msg.content, baseColor: AppColors.text, fontSize: fs),
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
        border: Border.all(color: AppColors.border),
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
                      size: (widget.fontSize - 1).clamp(12, 18).toDouble(),
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
                            fontSize: widget.fontSize - 3,
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
  final VoidCallback onCopy;
  const _ReasoningBlock({required this.content, required this.onCopy, this.fontSize = 15});

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
                        Text('思考', style: TextStyle(fontSize: widget.fontSize - 3, fontWeight: FontWeight.w700, color: AppColors.purple)),
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
                // Prefer soft wrap + normal font so English thinking is readable.
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
