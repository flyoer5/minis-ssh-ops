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
                        onDelete: () async {
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
                        },
                      );
                    },
                  ),
                ),
    );
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
  final VoidCallback onDelete;

  const _StatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    required this.onSelect,
    required this.onRefresh,
    required this.onDelete,
  });

  Color get _dot {
    if (loading) return const Color(0xFFD29922);
    if (summary == null) return const Color(0xFF6E7681);
    return summary!.ok ? const Color(0xFF3FB950) : const Color(0xFFF85149);
  }

  String _v(String label) {
    if (summary == null) return '—';
    for (final l in summary!.lines) {
      if (l.label == label) {
        final t = l.value.trim();
        if (t.isEmpty || t == '-') return '—';
        return t.length > 28 ? '${t.substring(0, 28)}…' : t;
      }
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF161B22) : const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? const Color(0xFF2F81F7) : const Color(0xFF30363D),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _dot, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(addr, style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E), fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onRefresh,
                      icon: const Icon(Icons.sync, size: 18, color: Color(0xFF8B949E)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (summary == null && !loading)
                const Text('下拉或点同步刷新状态', style: TextStyle(fontSize: 12, color: Color(0xFF6E7681)))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.memory, '负载', _v('负载')),
                    _chip(Icons.storage_outlined, '磁盘', _v('磁盘')),
                    _chip(Icons.sd_card_outlined, '内存', _v('内存')),
                    _chip(Icons.schedule, '运行', _v('运行')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8B949E)),
          const SizedBox(width: 6),
          Text(k, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              v,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
