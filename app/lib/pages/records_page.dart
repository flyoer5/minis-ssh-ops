import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> with AutomaticKeepAliveClientMixin {
  String filter = 'all'; // all|read|write|destructive|blocked

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshAudit().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final all = state.audit.whereType<Map>().toList();
    final list = filter == 'all'
        ? all
        : all.where((e) => (e['risk']?.toString() ?? '') == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('审计'),
        actions: [
          IconButton(onPressed: () => state.refreshAudit(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final f in ['all', 'read', 'write', 'destructive', 'blocked'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('暂无记录'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = list[i];
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
                              title: Text(risk),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  '$cmd\n\n--- stdout ---\n${e['stdout'] ?? ''}\n--- stderr ---\n${e['stderr'] ?? ''}',
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
          ),
        ],
      ),
    );
  }
}
