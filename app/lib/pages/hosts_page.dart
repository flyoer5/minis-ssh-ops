import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/pages/host_editor.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

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
                                    onReorder: (oldIndex, newIndex) {
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

class _StatusCard extends StatelessWidget {
  final String name;
  final String addr;
  final bool selected;
  final bool loading;
  final ProbeSummary? summary;
  final DateTime? probedAt;
  final double fontSize;
  /// When true, only MEM + HDD rows (no CPU / uptime footer).
  final bool compact;
  /// `password` | `key` | empty
  final String authKind;
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onMenu;
  final VoidCallback? onShowDetail;
  /// When false, long-press is free for reorder drag (menu only via ⋮).
  final bool longPressOpensMenu;

  const _StatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    this.probedAt,
    this.fontSize = 14,
    this.compact = false,
    this.authKind = '',
    required this.onSelect,
    required this.onRefresh,
    required this.onMenu,
    this.onShowDetail,
    this.longPressOpensMenu = true,
  });

  String get _ageText {
    final at = probedAt;
    if (at == null || summary == null) return '';
    final sec = DateTime.now().difference(at).inSeconds;
    if (sec < 5) return '刚刚';
    if (sec < 60) return '$sec 秒前';
    final min = sec ~/ 60;
    if (min < 60) return '$min 分钟前';
    final h = min ~/ 60;
    if (h < 48) return '$h 小时前';
    return '${h ~/ 24} 天前';
  }

  String _v(String label) {
    if (summary == null) return '—';
    for (final l in summary!.lines) {
      if (l.label == label) {
        final t = l.value.trim();
        return (t.isEmpty || t == '-') ? '—' : t;
      }
    }
    return '—';
  }

  double? _pct(String s) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(s);
    if (m != null) return (double.tryParse(m.group(1)!) ?? 0).clamp(0, 100) / 100.0;
    // used/total like 1.2Gi/3.7Gi
    final parts = s.split('/');
    if (parts.length == 2) {
      double? parse(String x) {
        x = x.trim().toUpperCase();
        final m2 = RegExp(r'([\d.]+)\s*([KMGT]?I?B?)').firstMatch(x);
        if (m2 == null) return null;
        var n = double.tryParse(m2.group(1)!) ?? 0;
        final u = m2.group(2) ?? '';
        if (u.startsWith('T')) {
          n *= 1024 * 1024;
        } else if (u.startsWith('G')) {
          n *= 1024;
        } else if (u.startsWith('K')) {
          n /= 1024;
        }
        return n;
      }
      final a = parse(parts[0]);
      final b = parse(parts[1]);
      if (a != null && b != null && b > 0) return (a / b).clamp(0.0, 1.0);
    }
    return null;
  }

  Color _barColor(double? p) {
    if (p == null) return AppColors.slate;
    if (p >= 0.9) return AppColors.dangerAlt;
    if (p >= 0.75) return AppColors.warnAlt;
    return AppColors.metricGreen;
  }

  Color get _status {
    if (loading) return AppColors.warnBright;
    if (summary == null) return AppColors.slate;
    if (!summary!.ok) return AppColors.dangerAlt;
    return AppColors.metricGreen;
  }

  String get _statusText {
    if (loading) return '探测中';
    if (summary == null) return '未探测';
    if (summary!.ok) return '在线';
    // Never dump raw SSH errors into the status chip; details live in 探针详情.
    final o = summary!.oneLine.trim();
    if (o.isEmpty || o == '—' || o == '离线' || o.toLowerCase() == 'offline') return '离线';
    if (o.startsWith('错误') || o.toLowerCase().contains('ssh') || o.length > 24) return '离线';
    // Short friendly reasons only (e.g. 认证失败)
    return o;
  }

  @override
  Widget build(BuildContext context) {
    // CPU% + MEM + HDD
    final cpuPctS = _v('CPU%');
    final cpuFull = _v('CPU');
    final diskPctS = _v('磁盘%');
    final diskFull = _v('磁盘');
    final memMain = _v('内存主');
    final memFull = _v('内存');
    final up = _v('运行');
    final sys = _v('系统');

    final diskP = _pct(diskPctS) ?? _pct(diskFull);
    final memP = _pct(memMain) ?? _pct(memFull);
    final cpuP = _pct(cpuPctS) ?? _pct(cpuFull);

    return Material(
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.selectBlue2 : AppColors.slateDeep,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        onLongPress: longPressOpensMenu ? onMenu : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // compact header: dot · name · status · actions
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: _status, shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: _status.withAlpha(0x66), blurRadius: 6),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  ),
                  Text(
                    _statusText,
                    style: TextStyle(fontSize: fontSize - 3, fontWeight: FontWeight.w700, color: _status),
                  ),
                  if (onShowDetail != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: '探针详情',
                      onPressed: onShowDetail,
                      icon: const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
                    ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, right: 6),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onRefresh,
                      icon: const Icon(Icons.sync, size: 16, color: AppColors.slate),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onMenu,
                      icon: const Icon(Icons.more_vert, size: 16, color: AppColors.slate),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        addr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.slate, fontFamily: 'monospace'),
                      ),
                    ),
                    if (authKind == 'key' || authKind == 'password')
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 4),
                        child: Icon(
                          authKind == 'key' ? Icons.vpn_key : Icons.password,
                          size: 12,
                          color: AppColors.slateMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (summary == null && !loading)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('下拉或点同步获取探针数据', style: TextStyle(fontSize: 12, color: AppColors.slateMuted)),
                )
              else ...[
                // ServerStatus style: label | value (no duplicate %) | bar
                if (!compact) ...[
                  // CPU utilization % (sampled /proc/stat)
                  _metricRow(
                    'CPU',
                    cpuPctS == '—' ? cpuFull : cpuPctS,
                    cpuP,
                    AppColors.metricBlue,
                  ),
                  const SizedBox(height: 5),
                ],
                // MEM: prefer "used/total" only; % comes from bar + optional once
                _metricRow(
                  'MEM',
                  () {
                    // memFull like "42% (1.2Gi/3.7Gi)" or memMain "42%" / "1.2Gi"
                    final full = memFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!; // used/total
                    if (memMain.contains('/') ) return memMain;
                    if (full.contains('/')) {
                      final parts = full.split(RegExp(r'\s+'));
                      for (final p in parts) {
                        if (p.contains('/') && !p.contains('%')) return p;
                      }
                    }
                    return memMain == '—' ? full : memMain;
                  }(),
                  memP,
                  AppColors.purple,
                ),
                const SizedBox(height: 5),
                _metricRow(
                  'HDD',
                  () {
                    final full = diskFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!;
                    if (diskPctS != '—' && full != '—' && full != diskPctS) {
                      // strip leading "51% " if present
                      final cleaned = full.replaceFirst(RegExp(r'^\d+%\s*'), '').replaceAll(RegExp(r'[()]'), '');
                      if (cleaned.contains('/')) return cleaned;
                    }
                    return diskPctS == '—' ? full : diskPctS;
                  }(),
                  diskP,
                  AppColors.metricTeal,
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  // uptime + OS + probe age
                  Text(
                    [
                      if (up != '—') '⏱ $up',
                      if (sys != '—') sys,
                      if (_ageText.isNotEmpty) _ageText,
                    ].join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize - 4,
                      color: () {
                        final at = probedAt;
                        if (at == null) return AppColors.slateText;
                        final sec = DateTime.now().difference(at).inSeconds;
                        if (sec > 120) return AppColors.warnAlt; // stale
                        return AppColors.slateText;
                      }(),
                      fontFamily: 'monospace',
                      height: 1.25,
                    ),
                  ),
                ] else if (_ageText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _ageText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: fontSize - 4, color: AppColors.slateText, fontFamily: 'monospace'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value, double? progress, Color accent, {bool showPct = true}) {
    final c = progress == null ? accent : _barColor(progress);
    // Only append % when value itself has none (avoids "51% 51% (19G/40G) 51%")
    final hasPct = value.contains('%');
    final pctText = (showPct && progress != null && !hasPct)
        ? '  ${(progress * 100).toStringAsFixed(0)}%'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(label, style: TextStyle(fontSize: fontSize - 3, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.5)),
            ),
            Expanded(
              child: Text(
                value + pctText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: fontSize - 2, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: AppColors.slateLine),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress?.clamp(0.0, 1.0) ?? 0,
            minHeight: 4,
            backgroundColor: AppColors.slateDeep,
            color: progress == null ? AppColors.slateBar : c,
          ),
        ),
      ],
    );
  }
}
