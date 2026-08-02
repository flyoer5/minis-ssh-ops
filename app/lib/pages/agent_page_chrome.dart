part of 'agent_page.dart';

extension _AgentPageChrome on _AgentPageState {
  PreferredSizeWidget _buildAppBar(BuildContext context, AppState state) {
    return AppBar(
      toolbarHeight: 48,
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
              onPressed: () {
                hapticConfirm(state.hapticFeedback);
                _stopGeneration(state);
              },
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
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '历史会话',
              onPressed: () => _showSessions(state),
              icon: const Icon(Icons.history, size: 20),
            ),
            if (_sessionsLoading)
              const Positioned(
                right: 4,
                bottom: 4,
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(strokeWidth: 1.4, color: AppColors.accentSoft),
                ),
              ),
          ],
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '新会话',
          onPressed: () async {
            if (!await _confirmInterrupt(state, action: '开新会话')) return;
            state.clearAgentChat();
            try {
              final r = await state.api.createAgentSession(hostId: state.selectedHostId);
              final sid = r['sessionId'] ?? r['id'] ?? '';
              if (sid is String && sid.isNotEmpty) {
                state.setAgentSessionMeta(sid, '新会话');
              }
            } catch (_) {}
            if (context.mounted) {
              showSnack(context, '已开新会话');
            }
          },
          icon: const Icon(Icons.add_comment_outlined, size: 20),
        ),
      ],
    );
  }

  Widget _buildHostStrip(BuildContext context, AppState state) {
    final canPick = state.backendOk && state.hosts.isNotEmpty;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: canPick
            ? () => _pickHostSheet(context, state)
            : (state.selectedHostId == null
                ? () => NavScope.maybeOf(context)?.go(0)
                : null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              PulseRing(
                active: state.backendOk && state.selectedHostId != null,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !state.backendOk
                        ? AppColors.danger
                        : (state.selectedHostId == null ? AppColors.textFaint : AppColors.success),
                  ),
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
              if (canPick)
                const Icon(Icons.swap_horiz, size: 14, color: AppColors.textFaint),
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
    );
  }

  /// Quick host switcher bottom sheet — switch the agent's target host
  /// without leaving the chat.
  Future<void> _pickHostSheet(BuildContext context, AppState state) async {
    final hosts = state.hosts.toList();
    if (hosts.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('切换主机', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: hosts.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
                itemBuilder: (_, i) {
                  final h = hosts[i];
                  if (h is! Map) return const SizedBox.shrink();
                  final id = h['id']?.toString() ?? '';
                  final name = (h['name']?.toString() ?? '').isNotEmpty
                      ? h['name'].toString()
                      : '${h['host']}';
                  final addr = '${h['username']}@${h['host']}:${h['port']}';
                  final selected = state.selectedHostId == id;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: AppColors.accentDeep.withAlpha(0x14),
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.dns_outlined,
                      size: 20,
                      color: selected ? AppColors.accentSoft : AppColors.textMuted,
                    ),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(c, id);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && picked != state.selectedHostId) {
      if (!await _confirmInterrupt(state, action: '切换主机')) return;
      hapticTap(state.hapticFeedback);
      state.selectHost(picked);
      showSnack(context, '已切换到该主机，新消息将发往它');
    }
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
            if (state.sessionOvMaxRounds != null) _OvChip(label: '轮数 ${state.sessionOvMaxRounds}'),
            if (state.sessionOvTemperature != null)
              _OvChip(
                label: state.sessionOvTemperature == 0
                    ? '温度 默认'
                    : '温度 ${state.sessionOvTemperature!.toStringAsFixed(1)}',
              ),
            if (state.sessionOvConfirm != null) _OvChip(label: state.sessionOvConfirm == 1 ? '强制确认' : '确认关'),
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
    );
  }
}
