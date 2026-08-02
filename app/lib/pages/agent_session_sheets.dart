part of 'agent_page.dart';

Future<void> showAgentSessionsSheet(BuildContext context, _AgentPageState page, AppState state) async {
  Future<List<AgentSession>> load() async {
    final raw = await state.api.listAgentSessions(
      hostId: page._onlyCurrentHost ? state.selectedHostId : null,
      q: page._sessionsQuery.isNotEmpty ? page._sessionsQuery : null,
    );
    return [for (final item in raw) AgentSession.fromJson(item)];
  }
  var sessionsFuture = load();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.8,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(children: [
                  const Expanded(child: Text('历史会话', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => setSheetState(() => sessionsFuture = load()), icon: const Icon(Icons.refresh), tooltip: '刷新'),
                  IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close), tooltip: '关闭'),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        page._onlyCurrentHost
                            ? '仅显示当前主机：${state.hostLabel}'
                            : '显示全部主机的会话',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        page._onlyCurrentHost = !page._onlyCurrentHost;
                        setSheetState(() => sessionsFuture = load());
                      },
                      child: Text(
                        page._onlyCurrentHost ? '显示全部' : '只看当前主机',
                        style: const TextStyle(fontSize: 12, color: AppColors.accentSoft, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<AgentSession>>(
                  future: sessionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('加载会话失败：${cleanError(snapshot.error!)}'));
                    }
                    final sessions = snapshot.data ?? const <AgentSession>[];
                    if (sessions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 40, color: AppColors.textFaint),
                            const SizedBox(height: 10),
                            const Text('暂无历史会话', style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            const Text('发送第一条消息会自动创建会话', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                state.clearAgentChat();
                              },
                              icon: const Icon(Icons.add_comment_outlined, size: 18),
                              label: const Text('开新会话'),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final isCurrent = state.agentSessionId == session.id;
                          final rel = formatChinaRelativeDt(session.updatedAt);
                          return ListTile(
                            selected: isCurrent,
                            selectedTileColor: AppColors.accentDeep.withAlpha(0x14),
                            leading: Icon(
                              isCurrent ? Icons.forum : Icons.chat_bubble_outline,
                              color: isCurrent ? AppColors.accentSoft : AppColors.textMuted,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    session.title.isEmpty ? '未命名会话' : session.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                      color: isCurrent ? AppColors.accentSoft : AppColors.text,
                                    ),
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentDeep.withAlpha(0x28),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text('当前', style: TextStyle(fontSize: 10, color: AppColors.accentSoft, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                                if (session.hasOverrides) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.tune, size: 13, color: AppColors.warning),
                                ],
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                if (session.msgCount > 0) ...[
                                  Text('${session.msgCount} 条', style: const TextStyle(fontSize: 11)),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    session.preview.isNotEmpty ? session.preview : rel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                                  ),
                                ),
                                Text(
                                  rel,
                                  style: const TextStyle(fontSize: 10, color: AppColors.textFaint, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await page._openSession(state, session.id, title: session.title);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: '删除会话',
                              onPressed: () async {
                                final go = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('删除会话？'),
                                    content: Text(
                                      '将删除“${session.title.isEmpty ? '未命名会话' : session.title}”，此操作不可恢复。',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (go == true) {
                                  state.deleteAgentSession(session.id);
                                  if (isCurrent) {
                                    state.clearAgentChat();
                                  }
                                  if (context.mounted) {
                                    showSnack(context, '已删除会话');
                                  }
                                  setSheetState(() => sessionsFuture = load());
                                }
                              },
                            ),
                          );
                        },
                      );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showAgentSessionSettingsSheet(BuildContext context, AppState state) async {
  final id = state.agentSessionId;
  if (id == null) {
    showSnack(context, '请先开启或打开一个会话');
    return;
  }

  var rounds = state.sessionOvMaxRounds?.toDouble();
  var temp = state.sessionOvTemperature;
  var confirm = state.sessionOvConfirm;
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
                    '仅影响当前会话“${state.agentSessionTitle}”，留空则使用全局设置。',
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
                      hintText: '追加到全局自定义提示词之后',
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

  if (ok != true || !context.mounted) {
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
    if (context.mounted) {
      showSnack(context, clearAll ? '已恢复全局设置' : '本会话设置已保存');
    }
  } catch (e) {
    if (context.mounted) {
      showSnack(context, '保存失败：${cleanError(e)}');
    }
  }
  promptCtrl.dispose();
}

Future<void> showAgentSessionMemorySheet(BuildContext context, AppState state) async {
  final id = state.agentSessionId;
  if (id == null) {
    showSnack(context, '请先开启或打开一个会话');
    return;
  }

  Map<String, dynamic>? mem;
  try {
    mem = await state.api.getAgentSessionMemory(id);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, '读取记忆失败：${cleanError(e)}');
    }
    return;
  }

  if (!context.mounted) return;
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
                              content: const Text('将清除会话摘要和事实记忆，但保留聊天记录。'),
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
                  child: const Text('清除记忆'),
                ),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
              ],
            ),
            Text(
              '当前会话：${state.agentSessionTitle}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (summary.isEmpty && facts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '暂无摘要或事实记忆\n会话内容较多后将自动生成',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textFaint, height: 1.4),
                  ),
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
