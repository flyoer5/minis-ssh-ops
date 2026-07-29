part of 'settings_page.dart';

extension _SettingsHostKeySheet on _SettingsPageState {
  Future<void> _openHostKeySheet(AppState state) async {
    try {
      final r = await state.api.listKnownHosts();
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
                initialChildSize: 0.62,
                maxChildSize: 0.92,
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
                                Text('HostKey（TOFU）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  '首次连接自动信任并记住指纹；重装系统后若指纹变化需删除旧记录再连。',
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
                          Text('${entries.length} 条信任记录', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const Spacer(),
                          if (entries.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: c,
                                  builder: (d) => AlertDialog(
                                    title: const Text('清空全部 HostKey？'),
                                    content: const Text('下次连接所有主机都会重新弹出信任流程。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('清空')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                final res = await state.api.clearKnownHosts();
                                final n = res['deleted'];
                                setLocal(() => entries = []);
                                if (mounted) _toast('已清空 $n 条');
                              },
                              child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
                            ),
                          IconButton(
                            tooltip: '刷新',
                            onPressed: () async {
                              final r2 = await state.api.listKnownHosts();
                              setLocal(() {
                                entries = List<Map>.from(((r2['entries'] as List?) ?? []).whereType<Map>());
                              });
                            },
                            icon: const Icon(Icons.refresh, size: 20),
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
                                    Icon(Icons.verified_user_outlined, size: 36, color: AppColors.textFaint),
                                    SizedBox(height: 10),
                                    Text('暂无信任主机指纹', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                    SizedBox(height: 6),
                                    Text(
                                      '首次连接新主机会提示 TOFU 信任指纹，确认后出现在这里。',
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
                                final host = e['host']?.toString() ?? '';
                                final port = e['port'] is int ? e['port'] as int : int.tryParse('${e['port']}') ?? 22;
                                final fp = e['fingerprint']?.toString() ?? '';
                                final kt = e['keyType']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text('$host:$port', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    [
                                      if (kt.isNotEmpty) kt,
                                      if (fp.isNotEmpty) 'SHA256:$fp',
                                    ].join(' · '),
                                    maxLines: 3,
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '删除并重信任',
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: c,
                                        builder: (d) => AlertDialog(
                                          title: Text('删除 $host:$port？'),
                                          content: const Text('下次连接该主机会按首次连接重新记录指纹。'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                      await state.api.deleteKnownHost(host, port);
                                      setLocal(() {
                                        entries = entries.where((x) {
                                          final h = x['host']?.toString() ?? '';
                                          final p = x['port'] is int ? x['port'] as int : int.tryParse('${x['port']}') ?? 22;
                                          return !(h == host && p == port);
                                        }).toList();
                                      });
                                      if (mounted) _toast('已删除 $host:$port');
                                    },
                                  ),
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
      _toast('读取可信主机记录失败：${cleanError(e)}');
    }
  }
}
