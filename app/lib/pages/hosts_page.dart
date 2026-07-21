import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class HostsPage extends StatelessWidget {
  const HostsPage({super.key});

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
                  : ListView.builder(
                      itemCount: state.hosts.length,
                      itemBuilder: (ctx, i) {
                        final h = state.hosts[i] as Map<String, dynamic>;
                        final id = h['id'] as String;
                        final selected = state.selectedHostId == id;
                        return ListTile(
                          selected: selected,
                          leading: Icon(selected ? Icons.radio_button_checked : Icons.dns),
                          title: Text((h['name'] as String?)?.isNotEmpty == true
                              ? h['name'] as String
                              : h['host'] as String),
                          subtitle: Text(
                            '${h['username']}@${h['host']}:${h['port']}'
                            '${h['hasPrivateKey'] == true ? ' · key' : ''}'
                            '${h['hasPassword'] == true ? ' · pwd' : ''}',
                          ),
                          onTap: () => state.selectHost(id),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: '健康探测',
                                icon: const Icon(Icons.monitor_heart_outlined),
                                onPressed: () async {
                                  state.selectHost(id);
                                  try {
                                    await state.runProbe(id);
                                    if (context.mounted) {
                                      showDialog(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('探测结果'),
                                          content: SingleChildScrollView(
                                            child: SelectableText(
                                              state.lastExecOutput,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('关闭'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('删除主机？'),
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
                                  if (ok == true) await state.removeHost(id);
                                },
                              ),
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
            const Text('无法连接本机 Go 后端', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              state.backendError ?? state.backendNote ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              '手机端会自动解压/拉起内置后端（127.0.0.1:17890）。\n'
              '若持续失败，点下方重试；开发期也可在「设置」手动填 Token。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => state.bootstrap(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试启动后端'),
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
          TextButton(
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
