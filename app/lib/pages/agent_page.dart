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

  int _lastMsgCount = 0;
  int _lastTailLen = 0;
  /// User scrolled away from the bottom — pause auto-follow so history is readable.
  bool _userPausedFollow = false;
  /// Generation start (UTC) — null when idle.
  DateTime? _genStarted;
  Timer? _genTimer;
  int _generationId = 0;

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
    _genTimer?.cancel();
    _genTimer = null;
    super.dispose();
  }

  void _onScrollPos() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final near = pos.maxScrollExtent - pos.pixels < 160;
    final show = !near && pos.maxScrollExtent > 80;
    // 用户离开底部时暂停自动跟随，便于翻看历史（回到底部恢复）。
    _userPausedFollow = !near;
    if (_showJumpBottom != show && mounted) {
      setState(() => _showJumpBottom = show);
    }
  }

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
      // 回到底部后恢复自动跟随。
      _userPausedFollow = false;
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
    // 用户已上翻查看历史时，不强制拉回底部。
    if (_userPausedFollow) return;
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
    if (text.isEmpty) return;
    if (!state.backendOk) {
      showSnack(context, '本地后端未连接', seconds: 2);
      return;
    }
    if (state.selectedHostId == null) {
      showSnack(context, '先选主机', seconds: 3, action: SnackBarAction(label: '去主机', onPressed: () => NavScope.maybeOf(context)?.go(0)));
      return;
    }
    if (_busy || state.agentBusy) {
      showSnack(context, '当前回复仍在生成，请先停止或等待完成', seconds: 2);
      return;
    }
    _input.clear();
    hapticTap(state.hapticFeedback);
    if (!state.agentKeepKeyboard) {
      _focus.unfocus();
    }
    final generationId = ++_generationId;
    setState(() {
      _busy = true;
      _genStarted = DateTime.now();
      _busyHint = '思考 / 调工具...';
    });
    // Keep elapsed time visible without rebuilding on every stream token.
    _genTimer?.cancel();
    _genTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_busy || generationId != _generationId || _genStarted == null) return;
      final sec = DateTime.now().difference(_genStarted!).inSeconds;
      setState(() => _busyHint = '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')} 思考中');
    });
    try {
      await state.agentChat(text);
    } catch (e) {
      if (generationId != _generationId) return;
      final msg = e.toString();
      if (msg.contains('HOSTKEY_MISMATCH') || msg.toLowerCase().contains('hostkey_mismatch')) {
        if (mounted) await _handleHostKeyMismatch(state);
      } else if (mounted) {
        showErrorSnack(context, msg);
      }
    } finally {
      // A stopped request may finish after a newer one starts; never let the
      // stale completion clear the new request's busy/timer state.
      if (generationId == _generationId) {
        _genTimer?.cancel();
        _genTimer = null;
        _genStarted = null;
        if (mounted) {
          setState(() => _busy = false);
          _bottom(force: true);
          if (state.agentKeepKeyboard) {
            _focus.requestFocus();
          }
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
