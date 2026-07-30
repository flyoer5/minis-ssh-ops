part of 'settings_page.dart';

extension _SettingsLongMemSheet on _SettingsPageState {
  Future<void> _openLongMemSheet(AppState state) async {
    try {
      final r = await state.api.listSessionMemory();
      var entries = List<Map>.from(((r['entries'] as List?) ?? []).whereType<Map>());
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (c) {
          return StatefulBuilder(
            builder: (c, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.65,
                maxChildSize: 0.94,
                minChildSize: 0.4,
                builder: (_, sc) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Agent 长期记忆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  '会话变长后会把旧轮次折叠成 summary/facts，供后续对话引用。可按会话查看或清空。',
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
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          Text('${entries.length} 条', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const Spacer(),
                          if (entries.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: c,
                                  builder: (d) => AlertDialog(
                                    title: const Text('清空所有长期记忆？'),
                                    content: const Text('会删除所有折叠后的 summary / facts。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('清空')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await state.api.deleteSessionMemory(all: true);
                                setLocal(() => entries = []);
                                if (mounted) _toast('已清空长期记忆');
                              },
                              child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history_outlined, size: 36, color: AppColors.textFaint),
                                    SizedBox(height: 10),
                                    Text('暂无长期记忆', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                    SizedBox(height: 6),
                                    Text(
                                      '当对话变长时，系统会把旧内容压缩进这里，便于后续回忆。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: sc,
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final updated = e['updatedAt']?.toString() ?? '';
                                final sum = e['summary']?.toString() ?? '';
                                final facts = e['facts']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    updated.isEmpty ? '记忆条目 ${i + 1}' : updated,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (sum.isNotEmpty) sum,
                                      if (facts.isNotEmpty) facts,
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  ),
                                  onTap: () async {
                                    await showDialog<void>(
                                      context: c,
                                      builder: (d) => AlertDialog(
                                        title: Text(updated.isEmpty ? '记忆条目 ${i + 1}' : updated),
                                        content: SingleChildScrollView(
                                          child: SelectableText(
                                            [
                                              if (updated.isNotEmpty) '更新: $updated',
                                              if (sum.isNotEmpty) 'SUMMARY:\n$sum',
                                              if (facts.isNotEmpty) 'FACTS:\n$facts',
                                            ].join('\n\n'),
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: 'SUMMARY:\n$sum\n\nFACTS:\n$facts'));
                                              Navigator.pop(d);
                                            },
                                            child: const Text('复制'),
                                          ),
                                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('关闭')),
                                        ],
                                      ),
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
    } catch (e) {
      _toast('读取长期记忆失败：${cleanError(e)}');
    }
  }
}
