part of 'agent_page.dart';

extension _AgentPageLayout on _AgentPageState {
  Widget _buildEmptyChat(AppState state, BuildContext context) {
    return Center(
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
              state.selectedHostId == null ? '先选择一台主机' : '开始向这台主机发消息',
              style: TextStyle(
                fontSize: state.agentFontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.selectedHostId == null
                  ? '去主机页点选卡片，或添加后再回来'
                  : '当前是 ${state.hostLabel}\n可查状态、改配置、排故。生成中可点停止。',
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
                    '有哪些失败或重启过的服务',
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
    );
  }

  Widget _buildMessages(AppState state) {
    final generating = _busy || state.agentBusy;
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          cacheExtent: 480,
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: state.agentMessages.length + (generating ? 1 : 0),
          itemBuilder: (_, i) {
            if (generating && i == state.agentMessages.length) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
                child: TypingIndicator(hint: _busyHint),
              );
            }
            final m = state.agentMessages[i];
            final id = m.meta?['id']?.toString() ?? '${m.at.microsecondsSinceEpoch}';
            final part = m.meta?['part']?.toString() ?? m.kind.name;
            final streaming = generating && i == state.agentMessages.length - 1 &&
                (part == 'text_delta' || part == 'text' || part == 'reasoning');
            return RepaintBoundary(
              child: _AnimatedMsgEntry(
                index: i,
                child: _Bubble(
                  key: ValueKey('$id|$part|${m.role}'),
                  msg: m,
                  fontSize: state.agentFontSize,
                  streaming: streaming,
                  onRetry: (generating || state.selectedHostId == null) ? null : () => _retryLast(state),
                ),
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
    );
  }
}

/// One-shot fade+slide entrance for new messages.
class _AnimatedMsgEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedMsgEntry({required this.index, required this.child});

  @override
  State<_AnimatedMsgEntry> createState() => _AnimatedMsgEntryState();
}

class _AnimatedMsgEntryState extends State<_AnimatedMsgEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
