import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> with AutomaticKeepAliveClientMixin {
  String path = '/root';
  List<dynamic> entries = [];
  bool loading = false;
  String? err;
  String? hostId;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<AppState>();
    if (s.selectedHostId != null && s.selectedHostId != hostId && s.backendOk) {
      hostId = s.selectedHostId;
      _load();
    }
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    setState(() { loading = true; err = null; });
    try {
      final r = await s.api.fsList(id, path);
      setState(() {
        entries = (r['entries'] as List?) ?? [];
        path = (r['path'] as String?)?.isNotEmpty == true ? r['path'] as String : path;
      });
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _up() {
    if (path == '/' || path.isEmpty) return;
    final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final i = p.lastIndexOf('/');
    setState(() => path = i <= 0 ? '/' : p.substring(0, i));
    _load();
  }

  Future<void> _openFile(String p) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    try {
      final r = await s.api.fsRead(id, p);
      if (!mounted) return;
      final text = r['text']?.toString() ?? '';
      final ctrl = TextEditingController(text: text);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(p.split('/').last, style: const TextStyle(fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: TextField(controller: ctrl, maxLines: null, expands: true, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('关闭')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        await s.api.fsWrite(id, p, ctrl.text, confirmed: true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    if (state.selectedHostId == null) {
      return const Scaffold(body: Center(child: Text('先选主机')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件'),
        actions: [
          IconButton(onPressed: _up, icon: const Icon(Icons.arrow_upward)),
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFF161B22),
            child: ListTile(
              dense: true,
              title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              subtitle: Text(state.hostLabel, style: const TextStyle(fontSize: 11)),
            ),
          ),
          if (err != null) Padding(padding: const EdgeInsets.all(12), child: Text(err!, style: const TextStyle(color: Color(0xFFF85149)))),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i] as Map;
                      final isDir = e['isDir'] == true;
                      final name = e['name']?.toString() ?? '';
                      final p = e['path']?.toString() ?? name;
                      return ListTile(
                        leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined),
                        title: Text(name),
                        subtitle: Text('${e['mode'] ?? ''} · ${e['size'] ?? 0}', style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          if (isDir) {
                            setState(() => path = p);
                            _load();
                          } else {
                            _openFile(p);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
