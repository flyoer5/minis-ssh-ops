import 'package:ssh_ai_agent/widgets/nav_menu.dart';

import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/pages/file_editor_page.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/widgets/shimmer.dart';

part 'files_page_actions.dart';
part 'files_page_transfers.dart';
part 'files_page_pane.dart';
part 'files_page_layout.dart';

/// Dual-pane remote file manager (MT Manager style).
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _Pane {
  String path = '';
  List<dynamic> entries = [];
  bool loading = false;
  String? err;
  final Set<String> selected = {};
  bool selecting = false;
  // Monotonic request id: a slow in-flight _load must not overwrite a newer
  // navigation (stale response race when tapping dirs quickly).
  int loadGen = 0;
}

class _FilesPageState extends State<FilesPage> with AutomaticKeepAliveClientMixin {
  final _left = _Pane();
  final _right = _Pane();
  /// 0 = left, 1 = right
  int focus = 0;
  String? hostId;
  bool dualPane = true;
  /// name | size | mtime
  String sortBy = 'name';
  bool sortAsc = true;
  bool _transferring = false;
  String _transferLabel = '';
  double? _transferProgress; // null = indeterminate

  _Pane get active => focus == 0 ? _left : _right;
  _Pane get inactive => focus == 0 ? _right : _left;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Host reload is handled in build() via select + post-frame.
  }

  Future<void> _load(_Pane pane) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final gen = ++pane.loadGen;
    final reqPath = pane.path; // capture: response must apply to this path only
    setState(() {
      pane.loading = true;
      pane.err = null;
      pane.selected.clear();
      pane.selecting = false;
    });
    try {
      final r = await s.api.fsList(id, reqPath);
      // A newer _load started while this one was in flight - drop stale result.
      if (gen != pane.loadGen) return;
      final list = List<dynamic>.from((r['entries'] as List?) ?? []);
      _sortEntries(list);
      setState(() {
        pane.entries = list;
        final rp = r['path']?.toString();
        if (rp != null && rp.isNotEmpty) pane.path = rp;
      });
    } catch (e) {
      if (gen != pane.loadGen) return;
      setState(() => pane.err = '$e');
    } finally {
      // Only the latest request clears the spinner; a superseded one must not
      // turn it off while the newer load is still running.
      if (gen == pane.loadGen) {
        setState(() => pane.loading = false);
      }
    }
  }

  void _up(_Pane pane) {
    if (pane.path.isEmpty || pane.path == '/') return;
    final p = pane.path.endsWith('/') ? pane.path.substring(0, pane.path.length - 1) : pane.path;
    final i = p.lastIndexOf('/');
    setState(() => pane.path = i <= 0 ? '/' : p.substring(0, i));
    _load(pane);
  }

  void _go(_Pane pane, String p) {
    setState(() => pane.path = p);
    _load(pane);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildLayout(context);
  }
}
