import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/opsd_service.dart';

class NativeHostsPage extends StatefulWidget {
  final OpsdService opsd;
  const NativeHostsPage({super.key, required this.opsd});

  @override
  State<NativeHostsPage> createState() => _NativeHostsPageState();
}

class _NativeHostsPageState extends State<NativeHostsPage> {
  List<dynamic> _hosts = [];
  bool _loading = true;
  String? _error;
  String? _probeOut;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.opsd.ensureRunning();
      final data = await widget.opsd.getJson('/api/hosts');
      setState(() {
        _hosts = (data['hosts'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connect(String id) async {
    try {
      final r = await widget.opsd.postJson('/api/hosts/$id/connect', {});
      if (!mounted) return;
      final banner = (r['banner'] ?? '').toString().split('\n').first;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接成功: $banner')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  Future<void> _probe(String id) async {
    try {
      final r = await widget.opsd.postJson('/api/probe', {'host_id': id});
      setState(() => _probeOut = const JsonEncoder.withIndent('  ').convert(r));
    } catch (e) {
      setState(() => _probeOut = e.toString());
    }
  }

  Future<void> _showAdd() async {
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final user = TextEditingController(text: 'root');
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加主机'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
              TextField(controller: host, decoration: const InputDecoration(labelText: '地址')),
              TextField(
                controller: port,
                decoration: const InputDecoration(labelText: '端口'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: user, decoration: const InputDecoration(labelText: '用户')),
              TextField(
                controller: pass,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.opsd.postJson('/api/hosts', {
        'name': name.text.trim(),
        'host': host.text.trim(),
        'port': int.tryParse(port.text) ?? 22,
        'user': user.text.trim(),
        'password': pass.text,
        'auth_type': 'password',
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('主机 (${_hosts.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
              FilledButton.tonal(onPressed: _showAdd, child: const Text('添加')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _hosts.length,
            itemBuilder: (ctx, i) {
              final h = _hosts[i] as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text('${h['name']}'),
                  subtitle: Text('${h['user']}@${h['host']}:${h['port']}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: '连接',
                        icon: const Icon(Icons.link),
                        onPressed: () => _connect(h['id'] as String),
                      ),
                      IconButton(
                        tooltip: '探测',
                        icon: const Icon(Icons.monitor_heart_outlined),
                        onPressed: () => _probe(h['id'] as String),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_probeOut != null)
          SizedBox(
            height: 160,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(_probeOut!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
      ],
    );
  }
}
