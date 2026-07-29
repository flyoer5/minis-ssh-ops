part of 'agent_page.dart';

extension _AgentPageChrome on _AgentPageState {
  Widget _buildAppBar(BuildContext context, AppState state) {
    return AppBar(
      toolbarHeight: 44,
      leading: NavMenuButton.leadingOf(context),
      leadingWidth: NavMenuButton.leadingWidthOf(context),
      titleSpacing: 4,
      title: InkWell(
        onTap: state.agentSessionId == null
            ? null
            : () async {
                final ctrl = TextEditingController(text: state.agentSessionTitle);
                final name = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Session title'),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      maxLength: 48,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onSubmitted: (x) => Navigator.pop(d, x),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Save')),
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
              state.selectedHostId == null ? 'No host selected' : state.hostLabel,
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
              label: const Text('Stop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Session',
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
                  title: const Text('Session title'),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 48,
                    decoration: const InputDecoration(labelText: 'Title'),
                    onSubmitted: (x) => Navigator.pop(d, x),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Save')),
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
            const PopupMenuItem(value: 'settings', child: Text('Session settings')),
            const PopupMenuItem(value: 'memory', child: Text('Session memory')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
          ],
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'History',
          onPressed: () => _showSessions(state),
          icon: const Icon(Icons.history, size: 20),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'New session',
          onPressed: () async {
            if (_busy || state.agentBusy) {
              _stopGeneration(state);
            }
            state.clearAgentChat();
            try {
              final r = await state.api.createAgentSession(hostId: state.selectedHostId);
              final sid = r['sessionId'] ?? r['id'] ?? '';
              if (sid is String && sid.isNotEmpty) {
                state.setAgentSessionMeta(sid, 'New session');
              }
            } catch (_) {}
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New session created'), duration: Duration(seconds: 1)),
              );
            }
          },
          icon: const Icon(Icons.add_comment_outlined, size: 20),
        ),
      ],
    );
  }

  Widget _buildHostStrip(BuildContext context, AppState state) {
    return Material(
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
                    ? 'Local backend disconnected'
                    : (state.selectedHostId == null ? 'No host selected' : state.hostLabel),
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
                child: const Text('Pick host', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverrideStrip(BuildContext context, AppState state) {
    if (state.sessionOvMaxRounds == null &&
        state.sessionOvTemperature == null &&
        state.sessionOvConfirm == null &&
        (state.sessionOvPrompt == null || state.sessionOvPrompt!.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (state.sessionOvMaxRounds != null) _OvChip(label: 'Rounds ${state.sessionOvMaxRounds}'),
            if (state.sessionOvTemperature != null)
              _OvChip(
                label: state.sessionOvTemperature == 0
                    ? 'Temp default'
                    : 'Temp ${state.sessionOvTemperature!.toStringAsFixed(1)}',
              ),
            if (state.sessionOvConfirm != null) _OvChip(label: state.sessionOvConfirm == 1 ? 'Force confirm' : 'Confirm off'),
            if (state.sessionOvPrompt != null && state.sessionOvPrompt!.trim().isNotEmpty)
              const _OvChip(label: 'Extra prompt'),
            GestureDetector(
              onTap: () => _showSessionSettings(state),
              child: const Text(
                'Edit',
                style: TextStyle(fontSize: 11, color: AppColors.accentSoft, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
