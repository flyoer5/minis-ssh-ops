part of 'hosts_page.dart';

extension HostsPageActions on _HostsPageState {
  void _showProbeDetail(
    BuildContext context,
    String name,
    String addr,
    ProbeSummary? s, {
    String? hostId,
    VoidCallback? onRetry,
  }) {
    if (s == null) {
      showSnack(context, '尚未探测，点“刷新”获取');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewPaddingOf(c).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(addr, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text(
                s.ok ? '在线 · ${s.oneLine}' : s.oneLine,
                style: TextStyle(color: s.ok ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final l in s.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(l.label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ),
                      Expanded(
                        child: SelectableText(
                          l.value,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textCode),
                        ),
                      ),
                    ],
                  ),
                ),
              if (s.detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('原始详情', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                SelectableText(s.detail, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!s.ok && onRetry != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        onRetry();
                      },
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('重试探针'),
                    ),
                  if (!s.ok && onRetry != null) const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final buf = StringBuffer()
                        ..writeln(name)
                        ..writeln(addr)
                        ..writeln(s.ok ? '在线' : s.oneLine)
                        ..writeln(s.detail.isNotEmpty ? s.detail : s.oneLine);
                      await Clipboard.setData(ClipboardData(text: buf.toString()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制错误详情'), duration: Duration(seconds: 1)),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('复制'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _hostMenu(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final name = (h['name'] as String?)?.isNotEmpty == true ? h['name'] as String : '${h['host']}';
    final addr = '${h['username']}@${h['host']}:${h['port']}';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('用 Agent 打开'),
              onTap: () => Navigator.pop(c, 'agent'),
            ),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('打开终端'),
              onTap: () => Navigator.pop(c, 'term'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('打开文件'),
              onTap: () => Navigator.pop(c, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: const Text('复制地址'),
              subtitle: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              onTap: () => Navigator.pop(c, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('删除', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'agent' || action == 'term' || action == 'files') {
      state.selectHost(id);
      final tab = switch (action) {
        'agent' => 1,
        'term' => 2,
        'files' => 3,
        _ => 0,
      };
      NavScope.maybeOf(context)?.go(tab);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: addr));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制主机地址'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    if (action == 'edit') {
      await _showEdit(context, state, h);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('删除 $name?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) {
        final savedHost = Map<String, dynamic>.from(h);
        await state.removeHost(id);
        if (!mounted) return;
        setState(() => _summary.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除 $name'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                if (mounted) {
                  state.addHost(savedHost).then((_) => _refreshAll(state));
                }
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _showEdit(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final result = await showHostEditor(context, title: '编辑主机', existing: h);
    if (result == null || !context.mounted) return;
    try {
      await state.updateHost(id, result.body);
      await _refreshProbe(state, id, force: true);
      if (context.mounted) {
        showSnack(context, '已保存');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, cleanError(e));
      }
    }
  }

  Future<void> _showAdd(BuildContext context, AppState state) async {
    final result = await showHostEditor(context, title: '添加主机');
    if (result == null || !context.mounted) return;
    try {
      final id = await state.addHost(result.body);
      if (!context.mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主机已添加，但未拿到 ID，请下拉刷新')),
        );
        return;
      }
      await _refreshProbe(state, id, force: true);
      if (!context.mounted) return;
      final s = _summary[id];
      if (s != null && !s.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            content: Text('已添加，但暂时连不上：${s.oneLine}'),
            action: SnackBarAction(
              label: '详情',
              onPressed: () {
                final h = state.hosts.cast<dynamic>().whereType<Map>().cast<Map<String, dynamic>>().firstWhere(
                      (e) => e['id'] == id,
                      orElse: () => <String, dynamic>{
                        'id': id,
                        'host': result.body['host'],
                        'username': result.body['username'],
                        'port': result.body['port'],
                      },
                    );
                final name = (h['name'] as String?)?.isNotEmpty == true ? h['name'] as String : '${h['host']}';
                final addr = '${h['username']}@${h['host']}:${h['port']}';
                _showProbeDetail(
                  context,
                  name,
                  addr,
                  s,
                  hostId: id,
                  onRetry: () => _refreshProbe(state, id, force: true),
                );
              },
            ),
          ),
        );
      } else if (s != null && s.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加并探测成功'), duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加主机'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, '添加失败：${cleanError(e)}', seconds: 4);
      }
    }
  }
}
