import 'dart:convert';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

part 'records_page_actions.dart';
part 'records_page_layout.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> with AutomaticKeepAliveClientMixin {
  String filter = 'all';
  String hostFilter = 'all';
  final TextEditingController _q = TextEditingController();
  String query = '';

  @override
  bool get wantKeepAlive => false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _fmtLocal(String raw, {bool relative = false}) {
    if (relative) return formatChinaRelative(raw);
    return formatChinaAbsolute(raw);
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'destructive':
        return AppColors.danger;
      case 'write':
        return AppColors.warning;
      case 'blocked':
        return AppColors.riskPurple;
      case 'read':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  String _hostLabel(AppState state, String hostId) {
    if (hostId.isEmpty) return '未知主机';
    for (final raw in state.hosts) {
      if (raw is Map && raw['id']?.toString() == hostId) {
        final name = raw['name']?.toString() ?? '';
        if (name.isNotEmpty) return name;
        return '${raw['host']}:${raw['port']}';
      }
    }
    return hostId.length > 8 ? '${hostId.substring(0, 8)}...' : hostId;
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
    return _buildRecordsPage(context);
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
