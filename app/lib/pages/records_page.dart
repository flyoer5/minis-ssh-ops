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

  /// Backend stores UTC RFC3339; show device local wall clock.
  String _fmtLocal(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final dt0 = DateTime.tryParse(s);
    if (dt0 == null) return s;
    final dt = dt0.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'destructive':
        return const Color(0xFFF85149);
      case 'write':
        return const Color(0xFFD29922);
      case 'blocked':
        return const Color(0xFFA371F7);
      case 'read':
        return const Color(0xFF3FB950);
      default:
        return const Color(0xFF8B949E);
    }
  }

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
    final fs = state.recordsFontSize;
    final all = state.audit.whereType<Map>().toList();
    final list = filter == 'all'
        ? all
        : all.where((e) => (e['risk']?.toString() ?? '') == filter).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        backgroundColor: const Color(0xFF0D1117),
        title: Text(
          '记录',
          style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '刷新',
            onPressed: () => state.refreshAudit(),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: Row(
              children: [
                for (final f in const [
                  ['all', '全部'],
                  ['read', '读'],
                  ['write', '写'],
                  ['destructive', '破坏'],
                  ['blocked', '拦截'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      label: Text(f[1], style: TextStyle(fontSize: fs - 1.5)),
                      selected: filter == f[0],
                      onSelected: (_) => setState(() => filter = f[0]),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                list.isEmpty ? '暂无记录' : '共 ${list.length} 条',
                style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E)),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text('暂无审计记录', style: TextStyle(fontSize: fs, color: const Color(0xFF8B949E))),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF21262D)),
                    itemBuilder: (ctx, i) {
                      final e = list[i];
                      final risk = e['risk']?.toString() ?? '';
                      final cmd = e['command']?.toString() ?? '';
                      final exit = e['exitCode'];
                      final at = _fmtLocal(e['createdAt']?.toString() ?? '');
                      final rc = _riskColor(risk);
                      return InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF161B22),
                              title: Text(
                                risk.isEmpty ? '详情' : risk,
                                style: TextStyle(fontSize: fs + 1, color: rc, fontWeight: FontWeight.w700),
                              ),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    '$cmd\n\n--- stdout ---\n${e['stdout'] ?? ''}\n--- stderr ---\n${e['stderr'] ?? ''}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: fs - 1,
                                      height: 1.35,
                                      color: const Color(0xFFC9D1D9),
                                    ),
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('关闭', style: TextStyle(fontSize: fs)),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cmd,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: fs,
                                  height: 1.3,
                                  color: const Color(0xFFE6EDF3),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: rc.withAlpha(0x22),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: rc.withAlpha(0x66)),
                                    ),
                                    child: Text(
                                      risk.isEmpty ? '?' : risk,
                                      style: TextStyle(fontSize: fs - 2.5, color: rc, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'exit $exit',
                                    style: TextStyle(
                                      fontSize: fs - 2,
                                      fontFamily: 'monospace',
                                      color: (exit is int && exit != 0)
                                          ? const Color(0xFFF85149)
                                          : const Color(0xFF8B949E),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    at,
                                    style: TextStyle(
                                      fontSize: fs - 2.5,
                                      fontFamily: 'monospace',
                                      color: const Color(0xFF6E7681),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
