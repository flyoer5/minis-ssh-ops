import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/pages/host_editor.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

part 'host_status_card.dart';
part 'host_status_card_helpers.dart';
part 'hosts_page_actions.dart';
part 'hosts_page_layout.dart';

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
  final TextEditingController _search = TextEditingController();
  String _query = '';
  Timer? _autoProbeTimer;
  int _autoProbeSecBound = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _autoProbeTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _syncAutoProbeTimer(AppState state) {
    final sec = state.hostAutoProbeSec;
    if (sec == _autoProbeSecBound) return;
    _autoProbeSecBound = sec;
    _autoProbeTimer?.cancel();
    _autoProbeTimer = null;
    if (sec <= 0) return;
    _autoProbeTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      final s = context.read<AppState>();
      if (!s.backendOk || s.hosts.isEmpty) return;
      unawaited(_probeMany(s, force: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context.select/watch only legal in build(); side effects moved to build.
  }

  Future<void> _probeMany(AppState state, {required bool force}) async {
    final ids = <String>[
      for (final h in state.hosts)
        if (h is Map && h['id'] is String) h['id'] as String,
    ];
    if (ids.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= ids.length) return;
        await _refreshProbe(state, ids[i], force: force);
      }
    }
    // From settings (1-6); clamp again defensively.
    final limit = state.probeConcurrency.clamp(1, 6);
    final n = ids.length < limit ? ids.length : limit;
    await Future.wait([for (var k = 0; k < n; k++) worker()]);
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
    } catch (e) {
      if (mounted) {
        final f = state.friendlyProbeError(e);
        setState(() {
          _summary[id] = ProbeSummary(
            ok: false,
            oneLine: f['short']!,
            lines: [
              ProbeLine('错误', f['short']!),
              if ((f['detail'] ?? '').isNotEmpty) ProbeLine('详情', f['detail']!),
            ],
            detail: '$e',
          );
        });
      }
    } finally {
      // Always clear the in-flight flag even if the page was disposed/kept-alive
      // mid-probe, or this host can never be probed again (contains() guard).
      _loading.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshAll(AppState state) async {
    await state.refreshHosts();
    await _probeMany(state, force: true);
  }
}
