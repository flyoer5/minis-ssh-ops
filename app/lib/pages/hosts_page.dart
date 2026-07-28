import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/pages/host_editor.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

part 'host_status_card.dart';

/// Host status cards (probe metrics). State kept in page + IndexedStack.
class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> with AutomaticKeepAliveClientMixin {
  final Map<String, ProbeSummary?> _summary = {};
  final Set<String> _loading = {};
  bool _autoStarted = false;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  Timer? _autoProbeTimer;
  int _autoProbeSecBound = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _autoProbeTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _syncAutoProbeTimer(AppState state) {
    final sec = state.hostAutoProbeSec;
    if (sec == _autoProbeSecBound) return;
    _autoProbeSecBound = sec;
    _autoProbeTimer?.cancel();
    _autoProbeTimer = null;
    if (sec <= 0) return;
    _autoProbeTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      final s = context.read<AppState>();
      if (!s.backendOk || s.hosts.isEmpty) return;
      unawaited(_probeMany(s, force: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context.select/watch only legal in build() — side effects moved to build.
  }

  Future<void> _probeMany(AppState state, {required bool force}) async {
    final ids = <String>[
      for (final h in state.hosts)
        if (h is Map && h['id'] is String) h['id'] as String,
    ];
    if (ids.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= ids.length) return;
        await _refreshProbe(state, ids[i], force: force);
      }
    }
    // From settings (1–6); clamp again defensively.
    final limit = state.probeConcurrency.clamp(1, 6);
    final n = ids.length < limit ? ids.length : limit;
    await Future.wait([for (var k = 0; k < n; k++) worker()]);
  }

  Future<void> _refreshProbe(AppState state, String id, {bool force = false}) async {
    if (_loading.contains(id)) return;
    if (!force) {
      final c = state.getProbeCache(id);
      if (c != null) {
        setState(() => _summary[id] = c);
        return;
      }
    }
    setState(() => _loading.add(id));
    try {
      final s = await state.runProbeSummary(id, force);
      if (mounted) setState(() => _summary[id] = s);
    } catch (e) {
      if (mounted) {
        final f = state.friendlyProbeError(e);
        setState(() {
          _summary[id] = ProbeSummary(
            ok: false,
            oneLine: f['short']!,
            lines: [
              ProbeLine('错误', f['short']!),
              if ((f['detail'] ?? '').isNotEmpty) ProbeLine('详情', f['detail']!),
            ],
            detail: '$e',
          );
        });
      }
    } finally {
      // Always clear the in-flight flag even if the page was disposed/kept-alive
      // mid-probe, or this host can never be probed again (contains() guard).
      _loading.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshAll(AppState state) async {
    await state.refreshHosts();
    await _probeMany(state, force: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Rebuild only when these change (not every Agent stream tick).
    final hostCount = context.select((AppState s) => s.hosts.length);
    context.select((AppState s) => s.selectedHostId);
    context.select((AppState s) => s.probeGen);
    context.select((AppState s) => s.uiFontSize);
    context.select((AppState s) => s.hostCardCompact);
    final backendOk = context.select((AppState s) => s.backendOk);
    context.select((AppState s) => s.probeConcurrency);
    context.select((AppState s) => s.hostAutoProbeSec);
    final state = context.read<AppState>();
    if (!_autoStarted && backendOk && hostCount > 0) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_probeMany(state, force: false));
      });
    }
    _syncAutoProbeTimer(state);
    final total = state.hosts.length;
    final online = state.hosts.where((h) {
      final id = h['id']?.toString();
      if (id == null) return false;
      final s = _summary[id];
      return s != null && s.ok;
    }).length;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        titleSpacing: 4,
        title: Text(
          total == 0 ? '主机' : '主机 · $online/$total 在线',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _refreshAll(state) : null,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _showAdd(context, state) : null,
            icon: const Icon(Icons.add, size: 22),
          ),
        ],
      ),
      body: !state.backendOk
          ? Center(child: FilledButton(onPressed: () => state.bootstrap(), child: const Text('连接后端')))
          : state.hosts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dns_outlined, size: 44, color: AppColors.textFaint),
                        const SizedBox(height: 12),
                        const Text(
                          '还没有主机',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '添加后可在 Agent、终端、文件中使用。支持密码或密钥登录。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.textFaint, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: state.backendOk ? () => _showAdd(context, state) : null,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加主机'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '搜索名称 / IP / 用户 · 无搜索时长按排序',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: AppColors.slateFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.slateDeep),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.slateDeep),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final q = _query;
                          final list = state.hosts.where((raw) {
                            if (q.isEmpty) return true;
                            final h = raw as Map<String, dynamic>;
                            final name = (h['name']?.toString() ?? '').toLowerCase();
                            final host = (h['host']?.toString() ?? '').toLowerCase();
                            final user = (h['username']?.toString() ?? '').toLowerCase();
                            final note = (h['note']?.toString() ?? h['remark']?.toString() ?? '').toLowerCase();
                            final addr = '$user@$host:${h['port']}';
                            return name.contains(q) ||
                                host.contains(q) ||
                                user.contains(q) ||
                                note.contains(q) ||
                                addr.contains(q);
                          }).toList();
                          if (list.isEmpty) {
                            // Scrollable so pull-to-refresh still works in the
                            // no-match state (Center alone can't be pulled).
                            return LayoutBuilder(
                              builder: (c, cons) => RefreshIndicator(
                                onRefresh: () => _refreshAll(state),
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minHeight: cons.maxHeight),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('无匹配主机', style: TextStyle(color: AppColors.slate)),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () {
                                            _search.clear();
                                            setState(() => _query = '');
                                          },
                                          child: const Text('清除搜索'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          // Search results: plain list. Full list: long-press drag to reorder.
                          final canReorder = q.isEmpty && list.length > 1;
                          Widget cardAt(int i) {
                            final h = list[i] as Map<String, dynamic>;
                            final id = h['id'] as String;
                            final name = (h['name'] as String?)?.isNotEmpty == true
                                ? h['name'] as String
                                : '${h['host']}';
                            final addr = '${h['username']}@${h['host']}:${h['port']}';
                            final auth = h['hasPrivateKey'] == true
                                ? 'key'
                                : (h['hasPassword'] == true ? 'password' : '');
                            final card = RepaintBoundary(child: _StatusCard(
                              name: name,
                              addr: addr,
                              selected: state.selectedHostId == id,
                              loading: _loading.contains(id),
                              summary: _summary[id],
                              probedAt: state.probeCacheTime(id),
                              fontSize: state.uiFontSize,
                              compact: state.hostCardCompact,
                              authKind: auth,
                              // When reorderable, long-press is reserved for drag; menu via ⋮ only.
                              onSelect: () => state.selectHost(id),
                              onRefresh: () => _refreshProbe(state, id, force: true),
                              onMenu: () => _hostMenu(context, state, h),
                              longPressOpensMenu: !canReorder,
                              onShowDetail: () => _showProbeDetail(
                                context,
                                name,
                                addr,
                                _summary[id],
                                hostId: id,
                                onRetry: () => _refreshProbe(state, id, force: true),
                              ),
                            ));
                            if (!canReorder) return card;
                            // Delayed listener = long-press then drag (not immediate press-drag).
                            return ReorderableDelayedDragStartListener(
                              key: ValueKey(id),
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: card,
                              ),
                            );
                          }

                          return RefreshIndicator(
                            onRefresh: () => _refreshAll(state),
                            child: canReorder
                                ? ReorderableListView.builder(
                                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                                    itemCount: list.length,
                                    buildDefaultDragHandles: false,
                                    proxyDecorator: (child, index, animation) {
                                      return Material(
                                        elevation: 4,
                                        color: Colors.transparent,
                                        child: child,
                                      );
                                    },
                                    onReorderItem: (oldIndex, newIndex) {
                                      // When filtering is off, list mirrors state.hosts order.
                                      state.reorderHosts(oldIndex, newIndex);
                                    },
                                    itemBuilder: (_, i) => cardAt(i),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (_, i) => cardAt(i),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }


  void _showProbeDetail(
    BuildContext context,
    String name,
    String addr,
    ProbeSummary? s, {
    String? hostId,
    VoidCallback? onRetry,
  }) {
    if (s == null) {
      showSnack(context, '尚未探测，点「刷新」获取');
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
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
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
                      SizedBox(width: 48, child: Text(l.label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                      Expanded(child: SelectableText(l.value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textCode))),
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
                          const SnackBar(content: Text('已复制错误/详情'), duration: Duration(seconds: 1)),
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
          title: Text('删除 $name？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) {
        await state.removeHost(id);
        if (!mounted) return;
        setState(() => _summary.remove(id));
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
          const SnackBar(content: Text('主机已添加，但未拿到 ID；请下拉刷新')),
        );
        return;
      }
      // Probe must never leave the page — failures show on the card / snackbar only.
      await _refreshProbe(state, id, force: true);
      if (!context.mounted) return;
      final s = _summary[id];
      if (s != null && !s.ok) {
        // SnackBars with actions stay forever unless duration is set — auto-dismiss.
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
