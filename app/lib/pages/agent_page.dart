import 'package:flutter/material.dart';
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

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk || state.selectedHostId == null) return;
    _input.clear();
    setState(() => _busy = true);
    try {
      await state.agentChat(text);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _bottom();
        _focus.requestFocus();
      }
    }
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
          if (state.agentMessages.isNotEmpty)
            IconButton(
              onPressed: _busy ? null : () => state.clearAgentChat(),
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
                        return const Padding(
                          padding: EdgeInsets.all(10),
                          child: Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('thinking…', style: TextStyle(fontSize: 12, color: Colors.white54)),
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
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) return const SizedBox.shrink();
    if (msg.kind == ChatKind.status) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          '› ${msg.content}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E), fontFamily: 'monospace'),
        ),
      );
    }
    if (msg.kind == ChatKind.stepResult) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: SelectableText(
          msg.content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, color: Color(0xFFC9D1D9)),
        ),
      );
    }
    final user = msg.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          color: user ? const Color(0xFF1F6FEB) : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(msg.content, style: const TextStyle(fontSize: 15, height: 1.35)),
      ),
    );
  }
}
