import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/models/chat_message.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Minis-like agent transcript: chat + tool-call cards + running status.
class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _runningTool;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(AppState state) async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (!state.backendOk || state.selectedHostId == null) return;
    _input.clear();
    setState(() {
      _busy = true;
      _runningTool = null;
    });
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

  Future<void> _runStep(AppState state, int stepId, String cmd) async {
    setState(() {
      _busy = true;
      _runningTool = cmd;
    });
    try {
      await state.runAgentStep(stepId: stepId, command: cmd, confirmed: true);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _runningTool = null;
        });
        _bottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFE6EDF3),
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              state.selectedHostId == null ? '未选主机' : state.hostLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          if (state.agentMessages.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => state.clearAgentChat(),
              child: const Text('新会话'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Minis-like tool overlay strip when running
          if (_runningTool != null)
            Material(
              color: const Color(0xFF1F6FEB).withOpacity(0.15),
              child: ListTile(
                dense: true,
                leading: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(
                  'Running: $_runningTool',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          Expanded(
            child: state.agentMessages.isEmpty
                ? Center(
                    child: Text(
                      state.selectedHostId == null ? '先选主机' : '发消息',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    itemCount: state.agentMessages.length + (_busy && _runningTool == null ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_busy && _runningTool == null && i == state.agentMessages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 8),
                              Text('thinking…', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                            ],
                          ),
                        );
                      }
                      return _Turn(
                        msg: state.agentMessages[i],
                        busy: _busy,
                        onRun: (id, cmd) => _runStep(state, id, cmd),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xFF30363D)),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFF161B22),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 15),
                      cursorColor: const Color(0xFF2F81F7),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(state),
                      decoration: InputDecoration(
                        hintText: state.selectedHostId == null ? '先选主机' : 'Message',
                        hintStyle: const TextStyle(color: Color(0xFF6E7681)),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (_busy || !state.backendOk || state.selectedHostId == null)
                        ? null
                        : () => _send(state),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_upward),
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

class _Turn extends StatelessWidget {
  final ChatMessage msg;
  final bool busy;
  final Future<void> Function(int stepId, String cmd) onRun;

  const _Turn({required this.msg, required this.busy, required this.onRun});

  Color _edge(String risk) {
    switch (risk) {
      case 'write':
        return const Color(0xFFD29922);
      case 'destructive':
        return const Color(0xFFF85149);
      case 'blocked':
        return const Color(0xFF6E7681);
      default:
        return const Color(0xFF3FB950);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (msg.kind == ChatKind.plan) {
      final plan = msg.meta?['plan'] as Map<String, dynamic>? ?? {};
      final steps = (plan['steps'] as List?) ?? [];
      if (steps.isEmpty) return const SizedBox.shrink();
      final outputs = Map<String, dynamic>.from(msg.meta?['outputs'] as Map? ?? {});

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final raw in steps)
            if (raw is Map)
              _ToolCard(
                step: Map<String, dynamic>.from(raw),
                output: outputs['step_${raw['id']}']?.toString(),
                busy: busy,
                edge: _edge(raw['risk']?.toString() ?? 'read'),
                onRun: onRun,
              ),
        ],
      );
    }

    if (msg.kind == ChatKind.stepResult || msg.kind == ChatKind.status) {
      return const SizedBox.shrink();
    }

    final user = msg.role == 'user';
    final err = msg.kind == ChatKind.error;

    // Minis transcript style: left-aligned assistant with role label
    if (user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
          decoration: BoxDecoration(
            color: const Color(0xFF1F6FEB).withOpacity(0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F6FEB).withOpacity(0.35)),
          ),
          child: SelectableText(msg.content, style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 15, height: 1.35)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            err ? 'error' : 'assistant',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: err ? const Color(0xFFF85149) : const Color(0xFF8B949E),
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            msg.content,
            style: TextStyle(
              color: err ? const Color(0xFFFFA198) : const Color(0xFFE6EDF3),
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final Map<String, dynamic> step;
  final String? output;
  final bool busy;
  final Color edge;
  final Future<void> Function(int stepId, String cmd) onRun;

  const _ToolCard({
    required this.step,
    required this.output,
    required this.busy,
    required this.edge,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final id = step['id'];
    final stepId = id is int ? id : int.tryParse('$id') ?? 0;
    final cmd = step['command']?.toString() ?? '';
    final title = step['title']?.toString() ?? 'tool';
    final risk = step['risk']?.toString() ?? 'read';
    final blocked = risk == 'blocked';
    final ran = output != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, decoration: BoxDecoration(color: edge, borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal, size: 14, color: Color(0xFF8B949E)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE6EDF3)),
                          ),
                        ),
                        Text(risk, style: TextStyle(fontSize: 11, color: edge)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      cmd,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFF79C0FF)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Clipboard.setData(ClipboardData(text: cmd)),
                          icon: const Icon(Icons.copy, size: 16, color: Color(0xFF8B949E)),
                        ),
                        const Spacer(),
                        if (!blocked)
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: ran ? const Color(0xFF21262D) : const Color(0xFF238636),
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: (busy || ran) ? null : () => onRun(stepId, cmd),
                            child: Text(ran ? 'done' : 'run'),
                          ),
                      ],
                    ),
                    if (output != null && output!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF21262D)),
                        ),
                        child: SelectableText(
                          output!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFC9D1D9), height: 1.3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
