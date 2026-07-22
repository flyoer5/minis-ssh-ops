import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Host list with inline probe-status cards (no "测试连接" action).
class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  final Map<String, ProbeSummary?> _summary = {};
  final Set<String> _loading = {};
  bool _autoStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (!_autoStarted && state.backendOk && state.hosts.isNotEmpty) {
      _autoStarted = true;
      // probe hosts concurrently (each is now a single SSH round-trip)
      for (final h in state.hosts) {
        if (h is Map && h['id'] is String) {
          // fire-and-forget
          unawaited(_refreshProbe(state, h['id'] as String));
        }
      }
    }
  }

  Future<void> _refreshProbe(AppState state, String id) async {
    if (_loading.contains(id)) return;
    setState(() => _loading.add(id));
    try {
      final s = await state.runProbeSummary(id);
      if (mounted) setState(() => _summary[id] = s);
    } catch (_) {
      if (mounted) {
        setState(() {
          _summary[id] = ProbeSummary(
            ok: false,
            oneLine: '不可达',
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
    final futures = <Future>[];
    for (final h in state.hosts) {
      if (h is Map && h['id'] is String) {
        futures.add(_refreshProbe(state, h['id'] as String));
      }
    }
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: state.backendOk ? () => _refreshAll(state) : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: state.backendOk ? () => _showAdd(context, state) : null,
        child: const Icon(Icons.add),
      ),
      body: state.startingBackend
          ? const Center(child: CircularProgressIndicator())
          : !state.backendOk
              ? Center(
                  child: FilledButton(onPressed: () => state.bootstrap(), child: const Text('重试连接后端')),
                )
              : state.hosts.isEmpty
                  ? const Center(child: Text('还没有主机'))
                  : RefreshIndicator(
                      onRefresh: () => _refreshAll(state),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: state.hosts.length,
                        itemBuilder: (_, i) {
                          final h = state.hosts[i] as Map<String, dynamic>;
                          final id = h['id'] as String;
                          final name = (h['name'] as String?)?.isNotEmpty == true
                              ? h['name'] as String
                              : '${h['host']}';
                          final addr = '${h['username']}@${h['host']}:${h['port']}';
                          final selected = state.selectedHostId == id;
                          final sum = _summary[id];
                          final loading = _loading.contains(id);
                          return _HostStatusCard(
                            name: name,
                            addr: addr,
                            selected: selected,
                            loading: loading,
                            summary: sum,
                            onTap: () {
                              state.selectHost(id);
                            },
                            onRefresh: () => _refreshProbe(state, id),
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
                                setState(() {
                                  _summary.remove(id);
                                });
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
    final key = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加主机'),
        content: SingleChildScrollView(
          child: Form(
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
                TextFormField(controller: key, decoration: const InputDecoration(labelText: '私钥 PEM'), maxLines: 3),
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
    };
    if (password.text.isNotEmpty) body['password'] = password.text;
    if (key.text.trim().isNotEmpty) body['privateKeyPem'] = key.text.trim();
    try {
      await state.addHost(body);
      await state.refreshHosts();
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

class _HostStatusCard extends StatelessWidget {
  final String name;
  final String addr;
  final bool selected;
  final bool loading;
  final ProbeSummary? summary;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _HostStatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    required this.onTap,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ok = summary?.ok;
    final border = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;

    String chip(String label, String? v) {
      final t = (v == null || v.isEmpty || v == '-') ? '—' : v;
      // keep short
      final short = t.length > 28 ? '${t.substring(0, 28)}…' : t;
      return '$label $short';
    }

    Map<String, String> kv = {};
    if (summary != null) {
      for (final l in summary!.lines) {
        kv[l.label] = l.value;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: selected ? 1.5 : 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    loading
                        ? Icons.sync
                        : ok == true
                            ? Icons.circle
                            : ok == false
                                ? Icons.circle
                                : Icons.circle_outlined,
                    size: 12,
                    color: loading
                        ? Colors.amber
                        : ok == true
                            ? Colors.green
                            : ok == false
                                ? Colors.redAccent
                                : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('当前', style: TextStyle(fontSize: 11)),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: loading ? null : onRefresh,
                    icon: loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              Text(addr, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
              const SizedBox(height: 10),
              if (loading && summary == null)
                const LinearProgressIndicator(minHeight: 2)
              else if (summary == null)
                Text('下拉或点刷新获取状态', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(label: '系统', value: _short(kv['系统'] ?? '—', 22)),
                    _MetricChip(label: '负载', value: _short(kv['负载'] ?? '—', 16)),
                    _MetricChip(label: '磁盘', value: _short(kv['磁盘'] ?? '—', 16)),
                    _MetricChip(label: '内存', value: _short(kv['内存'] ?? '—', 20)),
                    _MetricChip(label: '运行', value: _short(kv['运行'] ?? '—', 18)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _short(String s, int n) {
    final t = s.trim();
    if (t.length <= n) return t;
    return '${t.substring(0, n)}…';
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
