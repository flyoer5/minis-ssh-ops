import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';
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
  bool _showJumpBottom = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollPos);
  }

  void _onScrollPos() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final near = pos.maxScrollExtent - pos.pixels < 160;
    final show = !near && pos.maxScrollExtent > 80;
    if (_showJumpBottom != show && mounted) {
      setState(() => _showJumpBottom = show);
    }
  }

  String _relTime(DateTime when) => formatChinaRelativeDt(when);

  @override
  void dispose() {
    _scroll.removeListener(_onScrollPos);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    _sessionsSearch.dispose();
    super.dispose();
  }

  int _lastMsgCount = 0;
  int _lastTailLen = 0;

  void _bottom({bool force = false}) {
    final state = context.read<AppState>();
    if (!force && !state.agentAutoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      // animate when user taps jump; jump while streaming (cheaper).
      if (force && !_busy) {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(max);
      }
      if (_showJumpBottom && mounted) setState(() => _showJumpBottom = false);
    });
  }

  /// Keep view pinned to bottom during streaming, but only when the user is
  /// already near the bottom (so manual scroll-up to read isn't yanked back).
  void _autoFollow(AppState state) {
    if (!state.agentAutoScroll) return;
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
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  String _busyHint = '处理中…';

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地后端未连接'), duration: Duration(seconds: 2)),
      );
      return;
    }
    if (state.selectedHostId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('先选主机'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: '去主机', onPressed: () => NavScope.maybeOf(context)?.go(0)),
        ),
      );
      return;
    }
    if (_busy || state.agentBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上一轮还在进行，可点停止'), duration: Duration(seconds: 2)),
      );
      return;
    }
    _input.clear();
    if (state.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    if (!state.agentKeepKeyboard) {
      _focus.unfocus();
    }
    setState(() {
      _busy = true;
      _busyHint = '思考 / 调工具… 可点停止';
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HOSTKEY_MISMATCH') || msg.toLowerCase().contains('hostkey_mismatch')) {
        if (mounted) await _handleHostKeyMismatch(state);
      } else if (mounted) {
        final short = cleanError(msg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(short.length > 160 ? '${short.substring(0, 160)}…' : short),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom(force: true);
        if (state.agentKeepKeyboard) {
          _focus.requestFocus();
        }
      }
    }
  }

  List<AgentSession> _cachedSessions = [];
  bool _sessionsLoading = false;
  String _sessionsQuery = '';
  final _sessionsSearch = TextEditingController();

  void _loadSessions(AppState state) {
    setState(() => _sessionsLoading = true);
    _doLoad(state);
  }

  Future<void> _doLoad(AppState state) async {
    try {
      final raw = await state.api.listAgentSessions(
        hostId: _onlyCurrentHost ? state.selectedHostId : null,
        q: _sessionsQuery.isNotEmpty ? _sessionsQuery : null,
      );
      if (mounted) {
        final sessions = [for (final j in raw) AgentSession.fromJson(j)];
        setState(() {
          _cachedSessions = sessions;
          _sessionsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _openSession(AppState state, String id, {String? title}) async {
    try {
      if (_busy || state.agentBusy) {
        _stopGeneration(state);
      }
      // Meta + messages are independent — fetch in parallel (halves wait on
      // slow networks) and show a transient loading hint.
      setState(() => _sessionsLoading = true);
      try {
        final results = await Future.wait([
          state.api.getAgentSession(id),
          state.api.getAgentSessionMessages(id),
        ]);
        final sess = AgentSession.fromJson(results[0] as Map<String, dynamic>);
        final raw = results[1] as List<Map<String, dynamic>>;
        final msgs = [for (final j in raw) ChatMessage.fromJson(j)];
        // Align selected host with the session so follow-up tools hit the right box.
        final sidHost = sess.hostId;
        if (sidHost != null && sidHost.isNotEmpty && state.selectedHostId != sidHost) {
          state.selectHost(sidHost);
        }
        state.openAgentSessionRaw(
          id,
          msgs,
          title: title ?? sess.title,
          ovMaxRounds: sess.ovMaxRounds,
          ovTemperature: sess.ovTemperature,
          ovConfirm: sess.ovConfirm,
          ovPrompt: sess.ovPrompt,
        );
      } finally {
        if (mounted) setState(() => _sessionsLoading = false);
      }
    } catch (e) {
      if (mounted) showSnack(context, '加载会话失败: ${cleanError(e)}', seconds: 3);
    }
  }

  Future<void> _showSessionSettings(AppState state) async {
    final id = state.agentSessionId;
    if (id == null) {
      showSnack(context, '请先开启或打开一个会话');
      return;
    }
    var rounds = state.sessionOvMaxRounds?.toDouble();
    var temp = state.sessionOvTemperature;
    var confirm = state.sessionOvConfirm; // null / 0 / 1
    final promptCtrl = TextEditingController(text: state.sessionOvPrompt ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) {
        return StatefulBuilder(
          builder: (ctx, setM) {
            return ImeInset(
              left: 16,
              right: 16,
              top: 12,
              extraBottom: 16,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('本会话设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        TextButton(
                          onPressed: () {
                            setM(() {
                              rounds = null;
                              temp = null;
                              confirm = null;
                              promptCtrl.clear();
                            });
                          },
                          child: const Text('恢复全局'),
                        ),
                        IconButton(onPressed: () => Navigator.pop(c, false), icon: const Icon(Icons.close)),
                      ],
                    ),
                    Text(
                      '仅影响当前会话「${state.agentSessionTitle}」。留空/恢复 = 跟随设置页全局值。',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Text('工具轮数', style: TextStyle(fontWeight: FontWeight.w600))),
                        Text(
                          rounds == null ? '全局 ${state.agentMaxRounds}' : '${rounds!.round()}',
                          style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue),
                        ),
                      ],
                    ),
                    Slider(
                      value: (rounds ?? state.agentMaxRounds.toDouble()).clamp(1, 99),
                      min: 1,
                      max: 99,
                      divisions: 98,
                      label: rounds == null ? '全局' : '${rounds!.round()}',
                      onChanged: (v) => setM(() => rounds = v),
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('温度', style: TextStyle(fontWeight: FontWeight.w600))),
                        Text(
                          temp == null
                              ? (state.agentTemperature == 0 ? '全局 默认' : '全局 ${state.agentTemperature.toStringAsFixed(1)}')
                              : (temp == 0 ? '默认' : temp!.toStringAsFixed(1)),
                          style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue),
                        ),
                      ],
                    ),
                    Slider(
                      value: (temp ?? state.agentTemperature).clamp(0, 2),
                      min: 0,
                      max: 2,
                      divisions: 20,
                      onChanged: (v) => setM(() => temp = v),
                    ),
                    const Text('写操作确认', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('跟随全局'),
                          selected: confirm == null,
                          onSelected: (_) => setM(() => confirm = null),
                        ),
                        ChoiceChip(
                          label: const Text('强制确认'),
                          selected: confirm == 1,
                          onSelected: (_) => setM(() => confirm = 1),
                        ),
                        ChoiceChip(
                          label: const Text('强制关闭'),
                          selected: confirm == 0,
                          onSelected: (_) => setM(() => confirm = 0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('本会话附加提示词', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: promptCtrl,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: '追加在全局自定义提示词之后',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('保存本会话设置'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) {
      promptCtrl.dispose();
      return;
    }
    final clearAll = rounds == null && temp == null && confirm == null && promptCtrl.text.trim().isEmpty;
    try {
      final body = await state.api.patchAgentSession(
        id,
        clearOverrides: clearAll,
        ovMaxRounds: clearAll ? null : rounds?.round(),
        clearMaxRounds: !clearAll && rounds == null,
        ovTemperature: clearAll ? null : temp,
        clearTemperature: !clearAll && temp == null,
        ovConfirm: clearAll ? null : confirm,
        clearConfirm: !clearAll && confirm == null,
        ovPrompt: clearAll ? null : promptCtrl.text,
        clearPrompt: !clearAll && promptCtrl.text.trim().isEmpty,
      );
      final sess = AgentSession.fromJson(body);
      state.applySessionOverrides(
        maxRounds: sess.ovMaxRounds,
        temperature: sess.ovTemperature,
        confirm: sess.ovConfirm,
        prompt: sess.ovPrompt,
        clearAll: clearAll,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(clearAll ? '已恢复全局设置' : '本会话设置已保存'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, '保存失败: ${cleanError(e)}');
      }
    }
    promptCtrl.dispose();
  }

  Future<void> _showSessionMemory(AppState state) async {
    final id = state.agentSessionId;
    if (id == null) {
      showSnack(context, '请先开启或打开一个会话');
      return;
    }
    Map<String, dynamic>? mem;
    try {
      mem = await state.api.getAgentSessionMemory(id);
    } catch (e) {
      if (mounted) {
        showSnack(context, '读取记忆失败: ${cleanError(e)}');
      }
      return;
    }
    if (!mounted) return;
    final summary = (mem['summary'] ?? '').toString().trim();
    final facts = (mem['facts'] ?? '').toString().trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('本会话记忆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: summary.isEmpty && facts.isEmpty
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                title: const Text('清除本会话记忆？'),
                                content: const Text('摘要与事实会被删除，聊天记录仍保留。'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('清除')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                await state.api.deleteAgentSessionMemory(id);
                              } catch (_) {}
                              if (c.mounted) Navigator.pop(c);
                            }
                          },
                    child: const Text('清除'),
                  ),
                  IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                ],
              ),
              Text(
                '会话：${state.agentSessionTitle}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              if (summary.isEmpty && facts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('暂无摘要/事实\n对话足够长后会自动沉淀', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint, height: 1.4)),
                  ),
                )
              else ...[
                if (summary.isNotEmpty) ...[
                  const Text('摘要', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  SelectableText(summary, style: const TextStyle(fontSize: 13, height: 1.4)),
                  const SizedBox(height: 14),
                ],
                if (facts.isNotEmpty) ...[
                  const Text('事实', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  SelectableText(facts, style: const TextStyle(fontSize: 13, height: 1.4, fontFamily: 'monospace')),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSessions(AppState state) async {
    setState(() => _sessionsLoading = true);
    await _doLoad(state);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final list = _cachedSessions;
            final loading = _sessionsLoading;
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
                                  '服务端持久化。可搜索、重命名、删除或打开续聊。',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: SizedBox(
                        height: 30,
                        child: TextField(
                          controller: _sessionsSearch,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '搜索会话…',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            suffixIcon: _sessionsQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      _sessionsSearch.clear();
                                      setState(() {
                                        _sessionsQuery = '';
                                        _sessionsLoading = true;
                                      });
                                      setModal(() {});
                                      await _doLoad(state);
                                      setModal(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) async {
                            setState(() {
                              _sessionsQuery = v.trim();
                              _sessionsLoading = true;
                            });
                            setModal(() {});
                            await _doLoad(state);
                            setModal(() {});
                          },
                          onSubmitted: (v) async {
                            setState(() {
                              _sessionsQuery = v.trim();
                              _sessionsLoading = true;
                            });
                            setModal(() {});
                            await _doLoad(state);
                            setModal(() {});
                          },
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            dense: true,
                            title: const Text('仅当前主机', style: TextStyle(fontSize: 14)),
                            value: _onlyCurrentHost,
                            onChanged: (v) async {
                              setState(() {
                                _onlyCurrentHost = v;
                                _sessionsLoading = true;
                              });
                              setModal(() {});
                              await _doLoad(state);
                              setModal(() {});
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            loading ? '加载中…' : '${list.length} 个',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  Divider(height: 1, color: AppColors.border, indent: 16, endIndent: 16),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : list.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 28),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _sessionsQuery.isNotEmpty ? Icons.search_off : Icons.history,
                                        size: 40,
                                        color: AppColors.textFaint,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _sessionsQuery.isNotEmpty ? '没有匹配的会话' : '还没有历史会话',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700, color: AppColors.textMuted),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _sessionsQuery.isNotEmpty
                                            ? '换个关键词试试'
                                            : '发消息后自动写入服务端；点「新会话」开始空白对话。',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () async {
                                  await _doLoad(state);
                                  setModal(() {});
                                },
                                child: ListView.builder(
                                  controller: sc,
                                  padding: const EdgeInsets.only(bottom: 16),
                                  itemCount: list.length,
                                  itemBuilder: (_, i) {
                                    final s = list[i];
                                    final hostHint = s.hostId == null ? '' : state.hostLabelFor(s.hostId);
                                    final open = state.agentSessionId == s.id;
                                    final ts = _relTime(s.updatedAt);
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
                                              '${s.msgCount} 条',
                                              if (hostHint.isNotEmpty) hostHint,
                                              ts,
                                              if (open) '当前',
                                            ].join(' · '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                          ),
                                          onTap: () {
                                            _openSession(state, s.id, title: s.title);
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
                                                  try {
                                                    await state.api.renameAgentSession(s.id, name.trim());
                                                  } catch (_) {}
                                                  await _doLoad(state);
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
                                                try {
                                                  await state.api.deleteAgentSessionRemote(s.id);
                                                } catch (_) {}
                                                _loadSessions(state);
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
                              ),
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
    // Shell already resizeToAvoidBottomInset:false. Do not freeze whole Scaffold
    // (forms elsewhere need real viewInsets). Freeze only the message list.
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        titleSpacing: 4,
        title: InkWell(
          // Rename allowed even while generating — only send/input is locked.
          onTap: state.agentSessionId == null
              ? null
              : () async {
                  final ctrl = TextEditingController(text: state.agentSessionTitle);
                  final name = await showDialog<String>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('会话标题'),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        maxLength: 48,
                        decoration: const InputDecoration(labelText: '标题'),
                        onSubmitted: (x) => Navigator.pop(d, x),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('保存')),
                      ],
                    ),
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await state.renameOpenSessionTitle(name);
                  }
                },
          borderRadius: BorderRadius.circular(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      state.agentSessionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (state.agentSessionId != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.edit_outlined, size: 14, color: AppColors.textFaint),
                    ),
                ],
              ),
              Text(
                state.selectedHostId == null ? '未选主机' : state.hostLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
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
          PopupMenuButton<String>(
            tooltip: '会话',
            icon: const Icon(Icons.tune, size: 20),
            color: AppColors.surface,
            onSelected: (v) {
              if (v == 'settings') _showSessionSettings(state);
              if (v == 'memory') _showSessionMemory(state);
              if (v == 'rename' && state.agentSessionId != null) {
                final ctrl = TextEditingController(text: state.agentSessionTitle);
                showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('会话标题'),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      maxLength: 48,
                      decoration: const InputDecoration(labelText: '标题'),
                      onSubmitted: (x) => Navigator.pop(d, x),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('保存')),
                    ],
                  ),
                ).then((name) {
                  if (name != null && name.trim().isNotEmpty) {
                    state.renameOpenSessionTitle(name);
                  }
                });
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('本会话设置')),
              const PopupMenuItem(value: 'memory', child: Text('本会话记忆')),
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
            ],
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
            onPressed: () async {
              // Opening a new chat while generating: stop first so stream doesn't leak.
              if (_busy || state.agentBusy) {
                _stopGeneration(state);
              }
              state.clearAgentChat();
              try {
                final r = await state.api.createAgentSession(
                  hostId: state.selectedHostId,
                );
                final sid = r['sessionId'] ?? r['id'] ?? '';
                if (sid is String && sid.isNotEmpty) {
                  state.setAgentSessionMeta(sid, '新会话');
                }
              } catch (_) {}
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已开新会话'), duration: Duration(seconds: 1)),
                );
              }
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
                          ? '本地后端未连接'
                          : (state.selectedHostId == null ? '尚未选择主机' : state.hostLabel),
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
          if (state.sessionOvMaxRounds != null ||
              state.sessionOvTemperature != null ||
              state.sessionOvConfirm != null ||
              (state.sessionOvPrompt != null && state.sessionOvPrompt!.trim().isNotEmpty))
            Material(
              color: AppColors.bg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (state.sessionOvMaxRounds != null)
                      _OvChip(label: '轮数 ${state.sessionOvMaxRounds}'),
                    if (state.sessionOvTemperature != null)
                      _OvChip(
                        label: state.sessionOvTemperature == 0
                            ? '温度 默认'
                            : '温度 ${state.sessionOvTemperature!.toStringAsFixed(1)}',
                      ),
                    if (state.sessionOvConfirm != null)
                      _OvChip(label: state.sessionOvConfirm == 1 ? '强制确认' : '确认关'),
                    if (state.sessionOvPrompt != null && state.sessionOvPrompt!.trim().isNotEmpty)
                      const _OvChip(label: '附加提示词'),
                    GestureDetector(
                      onTap: () => _showSessionSettings(state),
                      child: const Text(
                        '编辑',
                        style: TextStyle(fontSize: 11, color: AppColors.accentSoft, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: WithoutViewInsets(
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
                            state.selectedHostId == null ? '先选一台主机' : '向 机枢 发消息',
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
                          ] else ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final s in const [
                                  '看一下负载、内存和磁盘',
                                  '有哪些失败或重启过的服务？',
                                  '检查最近系统日志里的错误',
                                  '当前监听了哪些端口？',
                                ])
                                  ActionChip(
                                    label: Text(s, style: TextStyle(fontSize: state.agentFontSize - 3)),
                                    onPressed: (_busy || state.agentBusy)
                                        ? null
                                        : () {
                                            _input.text = s;
                                            _send(state);
                                          },
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        // ignore: deprecated_member_use
                        cacheExtent: 480,
                        physics: const ClampingScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                          return RepaintBoundary(
                            child: _Bubble(
                              key: ValueKey('$id|$part|${m.role}'),
                              msg: m,
                              fontSize: state.agentFontSize,
                              streaming: streaming,
                            ),
                          );
                        },
                      ),
                      if (_showJumpBottom)
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: Material(
                            color: AppColors.surface2,
                            elevation: 2,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: '回到底部',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _bottom(force: true),
                              icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.accentSoft),
                            ),
                          ),
                        ),
                    ],
                  ),
            ), // WithoutViewInsets (list only)
          ), // Expanded
          // Don't stack retry while a turn is still running (looks like 重试中 + 运行中 + 停止).
          if (!_busy && !state.agentBusy && _canRetryLast(state))
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
          // Composer OUTSIDE list freeze so TextField gets real viewInsets.
          // usePadding:false → translate only, list Expanded does not reflow.
          // reservedBottom = shell NavigationBar height so we do not hide the
          // bar (setState mid-IME dismisses the keyboard on this page).
          ImeInset(
            usePadding: false,
            reservedBottom: kBottomNavigationBarHeight,
            fillColor: AppColors.bg,
            child: Material(
              color: AppColors.bg,
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
                        // Never disable — enabled:false drops IME focus immediately.
                        // Send is gated by the button / onSubmitted instead.
                        minLines: 1,
                        maxLines: 6,
                        style: TextStyle(fontSize: state.agentFontSize, color: AppColors.text),
                        textInputAction:
                            state.agentEnterToSend ? TextInputAction.send : TextInputAction.newline,
                        onSubmitted: (_) {
                          if (state.agentEnterToSend && !(_busy || state.agentBusy)) {
                            _send(state);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: state.selectedHostId == null
                              ? '先选主机'
                              : ((_busy || state.agentBusy)
                                  ? '生成中… 点右侧停止'
                                  : (state.agentEnterToSend ? '输入消息 · 回车发送' : '输入消息 · 回车换行')),
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
          ),
        ],
      ),
    );
  }

  void _stopGeneration(AppState state) {
    state.cancelAgentChat();
    if (mounted) {
      setState(() {
        _busy = false;
        _busyHint = '已停止';
      });
    }
  }


  String? _lastUserText(AppState state) {
    for (var i = state.agentMessages.length - 1; i >= 0; i--) {
      final m = state.agentMessages[i];
      if (m.role != 'user') continue;
      final t = m.content.trim();
      if (t.isEmpty) continue;
      // Synthetic follow-up after user confirms a write command — not retriable intent.
      if (t.startsWith('用户已确认并执行了以下命令：')) continue;
      return t;
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
        showSnack(context, shortError(e));
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
        if (mounted) showSnack(context, '已清除，请重试');
      } catch (e) {
        if (mounted) showSnack(context, cleanError(e));
      }
    }
  }
}
