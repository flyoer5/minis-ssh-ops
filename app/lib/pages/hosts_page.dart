import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  /// hostId -> probing
  final Set<String> _probing = {};
  /// hostId -> last probe summary line
  final Map<String, String> _probeHint = {};
  /// hostId -> ok/fail/null
  final Map<String, bool?> _probeOk = {};

  Future<void> _probe(BuildContext context, AppState state, String id, String title) async {
    setState(() {
      _probing.add(id);
      _probeHint[id] = '连接中…';
      _probeOk[id] = null;
    });
    state.selectHost(id);
    try {
      final summary = await state.runProbeSummary(id);
      if (!mounted) return;
      setState(() {
        _probing.remove(id);
        _probeOk[id] = summary.ok;
        _probeHint[id] = summary.oneLine;
      });
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _ProbeSheet(title: title, summary: summary),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probing.remove(id);
        _probeOk[id] = false;
        _probeHint[id] = '失败';
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('探测失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: state.backendOk ? () => state.refreshHosts() : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: state.backendOk ? () => _showAdd(context) : null,
        child: const Icon(Icons.add),
      ),
      body: state.startingBackend
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在启动本机后端…'),
                ],
              ),
            )
          : !state.backendOk
              ? _offline(context, state)
              : state.hosts.isEmpty
                  ? const Center(child: Text('还没有主机，点右下角添加'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: state.hosts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final h = state.hosts[i] as Map<String, dynamic>;
                        final id = h['id'] as String;
                        final selected = state.selectedHostId == id;
                        final name = (h['name'] as String?)?.isNotEmpty == true
                            ? h['name'] as String
                            : h['host'] as String;
                        final subtitle =
                            '${h['username']}@${h['host']}:${h['port']}';
                        final probing = _probing.contains(id);
                        final ok = _probeOk[id];
                        final hint = _probeHint[id];

                        return ListTile(
                          selected: selected,
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: probing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(
                                    ok == true
                                        ? Icons.check_circle
                                        : ok == false
                                            ? Icons.error_outline
                                            : Icons.dns,
                                    color: ok == true
                                        ? Colors.green
                                        : ok == false
                                            ? Colors.redAccent
                                            : null,
                                  ),
                          ),
                          title: Text(name),
                          subtitle: Text(
                            hint == null ? subtitle : '$subtitle\n$hint',
                            maxLines: 2,
                          ),
                          isThreeLine: hint != null,
                          onTap: () => state.selectHost(id),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'probe') {
                                await _probe(context, state, id, name);
                              } else if (v == 'select') {
                                state.selectHost(id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('已选中 $name'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              } else if (v == 'delete') {
                                final okDel = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('删除主机？'),
                                    content: Text('确定删除 $name ？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (okDel == true) await state.removeHost(id);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'select', child: Text('设为当前')),
                              PopupMenuItem(value: 'probe', child: Text('测试连接')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _offline(BuildContext context, AppState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            const Text('无法连接本机后端', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              state.backendError ?? state.backendNote ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => state.bootstrap(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdd(BuildContext context) async {
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
                TextFormField(controller: name, decoration: const InputDecoration(labelText: '显示名')),
                TextFormField(
                  controller: host,
                  decoration: const InputDecoration(labelText: '主机 IP/域名'),
                  validator: (v) => v == null || v.isEmpty ? '必填' : null,
                ),
                TextFormField(
                  controller: port,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: user,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: (v) => v == null || v.isEmpty ? '必填' : null,
                ),
                TextFormField(
                  controller: password,
                  decoration: const InputDecoration(labelText: '密码（与私钥二选一）'),
                  obscureText: true,
                ),
                TextFormField(
                  controller: key,
                  decoration: const InputDecoration(labelText: '私钥 PEM（可选）'),
                  maxLines: 4,
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
    };
    if (password.text.isNotEmpty) body['password'] = password.text;
    if (key.text.trim().isNotEmpty) body['privateKeyPem'] = key.text.trim();
    try {
      await context.read<AppState>().addHost(body);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _ProbeSheet extends StatelessWidget {
  final String title;
  final ProbeSummary summary;
  const _ProbeSheet({required this.title, required this.summary});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  summary.ok ? Icons.check_circle : Icons.error,
                  color: summary.ok ? Colors.green : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.ok ? '连接正常 · $title' : '连接失败 · $title',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...summary.lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        line.label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        line.value,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (summary.detail.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                '详情',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: SelectableText(
                    summary.detail,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}
