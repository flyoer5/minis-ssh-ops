import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

part 'agent_widgets.dart';

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

  int _lastMsgCount = 0;
  int _lastTailLen = 0;

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Keep view pinned to bottom during streaming, but only when the user is
  /// already near the bottom (so manual scroll-up to read isn't yanked back).
  void _autoFollow(AppState state) {
    final msgs = state.agentMessages;
    final count = msgs.length;
    final tailLen = msgs.isEmpty ? 0 : msgs.last.content.length;
    final grew = count != _lastMsgCount || tailLen != _lastTailLen;
    _lastMsgCount = count;
    _lastTailLen = tailLen;
    if (!grew || !_busy) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final nearBottom = pos.maxScrollExtent - pos.pixels < 160;
    if (nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
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
    if (state.agentBusy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上一轮还在进行，可点停止')));
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
      } else if (mounted) {
        final short = msg
            .replaceFirst(RegExp(r'^Exception:\s*'), '')
            .replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(short.length > 160 ? '${short.substring(0, 160)}…' : short)),
        );
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
    _autoFollow(state);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        titleSpacing: 4,
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
          // Compact host / backend strip
          Material(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !state.backendOk
                          ? AppColors.danger
                          : (state.selectedHostId == null ? AppColors.textFaint : AppColors.success),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !state.backendOk
                          ? '后端未连接'
                          : (state.selectedHostId == null ? '未选主机' : state.hostLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                  if (state.selectedHostId == null)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.accentSoft,
                      ),
                      onPressed: () => NavScope.maybeOf(context)?.go(0),
                      child: const Text('选主机', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: state.agentMessages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.selectedHostId == null ? Icons.dns_outlined : Icons.auto_awesome,
                            size: 40,
                            color: AppColors.textFaint,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.selectedHostId == null ? '先选一台主机' : '向 Agent 发消息',
                            style: TextStyle(
                              fontSize: state.agentFontSize,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.selectedHostId == null
                                ? '在「主机」页点选卡片，或添加主机后再回来。'
                                : '当前：${state.hostLabel}\n可让它查状态、改配置、排错。生成中可点停止。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: state.agentFontSize - 2,
                              color: AppColors.textFaint,
                              height: 1.45,
                            ),
                          ),
                          if (state.selectedHostId == null) ...[
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () => NavScope.maybeOf(context)?.go(0),
                              icon: const Icon(Icons.dns_outlined, size: 18),
                              label: const Text('去选主机'),
                            ),
                          ],
                        ],
                      ),
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
          if (_canRetryLast(state))
            Material(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: Row(
                  children: [
                    const Icon(Icons.replay, size: 16, color: AppColors.accentSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '可重试：${_lastUserText(state) ?? ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.accentSoft,
                      ),
                      onPressed: () => _retryLast(state),
                      child: const Text('重试', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
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


  String? _lastUserText(AppState state) {
    for (var i = state.agentMessages.length - 1; i >= 0; i--) {
      final m = state.agentMessages[i];
      if (m.role == 'user' && m.content.trim().isNotEmpty) return m.content.trim();
    }
    return null;
  }

  bool _canRetryLast(AppState state) {
    if (_busy || state.agentBusy || state.selectedHostId == null) return false;
    if (_lastUserText(state) == null) return false;
    for (var i = state.agentMessages.length - 1; i >= 0; i--) {
      final m = state.agentMessages[i];
      if (m.role == 'user') return false;
      if (m.kind == ChatKind.error) return true;
      if (m.kind == ChatKind.status &&
          (m.content.contains('停止') || m.content.contains('取消') || m.meta?['interrupted'] == true)) {
        return true;
      }
      if (m.meta?['interrupted'] == true) return true;
      if (m.kind == ChatKind.text || m.kind == ChatKind.reasoning) continue;
    }
    return false;
  }

  Future<void> _retryLast(AppState state) async {
    final text = _lastUserText(state);
    if (text == null || _busy) return;
    setState(() {
      _busy = true;
      _busyHint = '重试中…';
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      if (mounted) {
        final short = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(short.length > 160 ? '${short.substring(0, 160)}…' : short)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom();
      }
    }
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
