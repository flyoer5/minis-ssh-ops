import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (!_autoStarted && state.backendOk && state.hosts.isNotEmpty) {
      _autoStarted = true;
      for (final h in state.hosts) {
        if (h is Map && h['id'] is String) {
          unawaited(_refreshProbe(state, h['id'] as String));
        }
      }
    }
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _summary[id] = ProbeSummary(
            ok: false,
            oneLine: '离线',
            lines: [ProbeLine('状态', '探测失败')],
            detail: '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  Future<void> _refreshAll(AppState state) async {
    await state.refreshHosts();
    await Future.wait([
      for (final h in state.hosts)
        if (h is Map && h['id'] is String) _refreshProbe(state, h['id'] as String),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
          IconButton(
            onPressed: state.backendOk ? () => _refreshAll(state) : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: state.backendOk ? () => _showAdd(context, state) : null,
        child: const Icon(Icons.add),
      ),
      body: !state.backendOk
          ? Center(child: FilledButton(onPressed: () => state.bootstrap(), child: const Text('连接后端')))
          : state.hosts.isEmpty
              ? const Center(child: Text('无主机'))
              : RefreshIndicator(
                  onRefresh: () => _refreshAll(state),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
                    itemCount: state.hosts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final h = state.hosts[i] as Map<String, dynamic>;
                      final id = h['id'] as String;
                      final name = (h['name'] as String?)?.isNotEmpty == true
                          ? h['name'] as String
                          : '${h['host']}';
                      final addr = '${h['username']}@${h['host']}:${h['port']}';
                      return _StatusCard(
                        name: name,
                        addr: addr,
                        selected: state.selectedHostId == id,
                        loading: _loading.contains(id),
                        summary: _summary[id],
                        onSelect: () => state.selectHost(id),
                        onRefresh: () => _refreshProbe(state, id, force: true),
                        onMenu: () => _hostMenu(context, state, h),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _hostMenu(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final name = (h['name'] as String?)?.isNotEmpty == true ? h['name'] as String : '${h['host']}';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新状态'),
              onTap: () => Navigator.pop(c, 'probe'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF85149)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFF85149))),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'probe') {
      await _refreshProbe(state, id, force: true);
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
        setState(() => _summary.remove(id));
      }
    }
  }

  Future<void> _showEdit(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final name = TextEditingController(text: (h['name'] as String?) ?? '');
    final host = TextEditingController(text: (h['host'] as String?) ?? '');
    final port = TextEditingController(text: '${h['port'] ?? 22}');
    final user = TextEditingController(text: (h['username'] as String?) ?? 'root');
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑主机'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                TextFormField(
                  controller: host,
                  decoration: const InputDecoration(labelText: '地址'),
                  validator: (v) => v == null || v.isEmpty ? '必填' : null,
                ),
                TextFormField(
                  controller: port,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(controller: user, decoration: const InputDecoration(labelText: '用户')),
                TextFormField(
                  controller: password,
                  decoration: const InputDecoration(labelText: '密码（留空不改）'),
                  obscureText: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(c, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'host': host.text.trim(),
      'port': int.tryParse(port.text.trim()) ?? 22,
      'username': user.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
    };
    try {
      await state.updateHost(id, body);
      await _refreshProbe(state, id, force: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAdd(BuildContext context, AppState state) async {
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final user = TextEditingController(text: 'root');
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加主机'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: '名称')),
              TextFormField(
                controller: host,
                decoration: const InputDecoration(labelText: '地址'),
                validator: (v) => v == null || v.isEmpty ? '必填' : null,
              ),
              TextFormField(controller: port, decoration: const InputDecoration(labelText: '端口'), keyboardType: TextInputType.number),
              TextFormField(controller: user, decoration: const InputDecoration(labelText: '用户')),
              TextFormField(controller: password, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(c, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'host': host.text.trim(),
      'port': int.tryParse(port.text.trim()) ?? 22,
      'username': user.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
    };
    try {
      await state.addHost(body);
      String? id;
      for (final h in state.hosts) {
        if (h is Map && h['id'] is String) id = h['id'] as String;
      }
      if (id != null) await _refreshProbe(state, id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onMenu;

  const _StatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    required this.onSelect,
    required this.onRefresh,
    required this.onMenu,
  });

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

  Color get _status {
    if (loading) return const Color(0xFFFFB020);
    if (summary == null) return const Color(0xFF6B7280);
    return summary!.ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final load1 = _v('负载1');
    final diskPct = _v('磁盘%');
    final memMain = _v('内存主');
    final up = _v('运行');
    final sys = _v('系统');
    final diskFull = _v('磁盘');
    final memFull = _v('内存');

    return Material(
      color: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? const Color(0xFF38BDF8) : const Color(0xFF1F2937), width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onSelect,
        onLongPress: onMenu,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _status.withAlpha(0x22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _status.withAlpha(0x66)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: _status, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(
                          loading ? '探测中' : (summary == null ? '未探测' : (summary!.ok ? '在线' : '异常')),
                          style: TextStyle(fontSize: 11, color: _status, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(addr, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else ...[
                    IconButton(visualDensity: VisualDensity.compact, onPressed: onRefresh, icon: const Icon(Icons.sync, size: 18, color: Color(0xFF94A3B8))),
                    IconButton(visualDensity: VisualDensity.compact, onPressed: onMenu, icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8))),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (summary == null && !loading)
                const Text('下拉或点同步刷新', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))
              else ...[
                // probe-service style big tiles
                Row(
                  children: [
                    Expanded(child: _big('LOAD', load1, '1m', const Color(0xFF38BDF8))),
                    const SizedBox(width: 8),
                    Expanded(child: _big('DISK', diskPct, diskFull == '—' ? 'root' : diskFull, const Color(0xFFA78BFA))),
                    const SizedBox(width: 8),
                    Expanded(child: _big('MEM', memMain, memFull == '—' ? 'used' : memFull, const Color(0xFF34D399))),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1F2937)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UP  $up', style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontFamily: 'monospace')),
                      if (sys != '—') ...[
                        const SizedBox(height: 4),
                        Text(sys, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontFamily: 'monospace', height: 1.25)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _big(String k, String v, String sub, Color c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withAlpha(0x28), const Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withAlpha(0x55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
