import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/agent_session.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';
import 'package:ssh_ai_agent/widgets/animations.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

part 'agent_widgets.dart';
part 'agent_confirm_plan_card.dart';
part 'agent_page_layout.dart';
part 'agent_page_chrome.dart';
part 'agent_page_composer.dart';
part 'agent_session_sheets.dart';
part 'agent_page_actions.dart';
part 'agent_message_visuals.dart';
part 'agent_message_reasoning.dart';
part 'agent_message_blocks.dart';

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
  final _sessionsSearch = TextEditingController();

  bool _busy = false;
  bool _expanding = false;
  bool _onlyCurrentHost = true;
  bool _showJumpBottom = false;
  bool _sessionsLoading = false;
  String _sessionsQuery = '';
  String _busyHint = '处理中...';
  List<AgentSession> _cachedSessions = [];

  int _lastMsgCount = 0;
  int _lastTailLen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollPos);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScrollPos);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    _sessionsSearch.dispose();
    super.dispose();
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

  void _bottom({bool force = false}) {
    final state = context.read<AppState>();
    if (!force && !state.agentAutoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (force && !_busy) {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(max);
      }
      if (_showJumpBottom && mounted) setState(() => _showJumpBottom = false);
    });
  }

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

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk) {
      showSnack(context, '本地后端未连接', seconds: 2);
      return;
    }
    if (state.selectedHostId == null) {
      showSnack(context, '先选主机', seconds: 3, action: SnackBarAction(label: '去主机', onPressed: () => NavScope.maybeOf(context)?.go(0)));
      return;
    }
    if (_busy || state.agentBusy) {
      showSnack(context, '上一轮还在进行，可点停止', seconds: 2);
      return;
    }
    _input.clear();
    hapticTap(state.hapticFeedback);
    if (!state.agentKeepKeyboard) {
      _focus.unfocus();
    }
    setState(() {
      _busy = true;
      _busyHint = '思考 / 调工具... 可点停止';
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HOSTKEY_MISMATCH') || msg.toLowerCase().contains('hostkey_mismatch')) {
        if (mounted) await _handleHostKeyMismatch(state);
      } else if (mounted) {
        showErrorSnack(context, msg);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Narrow rebuild scope: ignore unrelated AppState changes (probes, prefs, hosts).
    context.select((AppState s) => Object.hash(
      s.agentMessages.length,
      s.agentMessages.isNotEmpty ? s.agentMessages.last.content.length : 0,
    ));
    context.select((AppState s) => s.agentBusy);
    context.select((AppState s) => s.selectedHostId);
    context.select((AppState s) => s.hostLabel);
    context.select((AppState s) => s.agentSessionId);
    context.select((AppState s) => s.agentSessionTitle);
    context.select((AppState s) => s.backendOk);
    context.select((AppState s) => s.agentAutoScroll);
    context.select((AppState s) => s.agentKeepKeyboard);
    final state = context.read<AppState>();
    _autoFollow(state);
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(context, state),
      body: Column(
        children: [
          _buildHostStrip(context, state),
          _buildOverrideStrip(context, state),
          Expanded(
            child: WithoutViewInsets(
              child: state.agentMessages.isEmpty ? _buildEmptyChat(state, context) : _buildMessages(state),
            ),
          ),
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
          _buildComposer(state),
        ],
      ),
    );
  }
}
