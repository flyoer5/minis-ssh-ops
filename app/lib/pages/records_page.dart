import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshAudit().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('审计记录'),
        actions: [
          IconButton(
            onPressed: () => state.refreshAudit(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.audit.isEmpty
          ? const Center(child: Text('暂无审计记录（执行命令后显示）'))
          : ListView.separated(
              itemCount: state.audit.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final e = state.audit[i] as Map<String, dynamic>;
                final risk = e['risk']?.toString() ?? '';
                final cmd = e['command']?.toString() ?? '';
                final exit = e['exitCode'];
                final at = e['createdAt']?.toString() ?? '';
                return ListTile(
                  title: Text(cmd, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('[$risk] exit=$exit · $at'),
                  isThreeLine: true,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text('审计 #$i'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            'risk=$risk exit=$exit\n$cmd\n\n--- stdout ---\n${e['stdout'] ?? ''}\n--- stderr ---\n${e['stderr'] ?? ''}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
