part of 'records_page.dart';

extension RecordsPageLayout on _RecordsPageState {
  Widget _buildFilters(BuildContext context, AppState state, double fs, List<Map> list, Set<String> hostIds) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: TextField(
            controller: _q,
            onChanged: (v) => setState(() => query = v),
            style: TextStyle(fontSize: fs - 1),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索命令 / 输出 / 主机',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _q.clear();
                        setState(() => query = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
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
        if (hostIds.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text('全部主机', style: TextStyle(fontSize: fs - 1.5)),
                    selected: hostFilter == 'all',
                    onSelected: (_) => setState(() => hostFilter = 'all'),
                  ),
                ),
                for (final id in hostIds)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      label: Text(_hostLabel(state, id), style: TextStyle(fontSize: fs - 1.5)),
                      selected: hostFilter == id,
                      onSelected: (_) => setState(() => hostFilter = id),
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
              style: TextStyle(fontSize: fs - 2, color: AppColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyListState(BuildContext context, double fs) {
    final searching = query.trim().isNotEmpty || filter != 'all' || hostFilter != 'all';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                searching ? Icons.search_off : Icons.receipt_long_outlined,
                size: 40,
                color: AppColors.textFaint,
              ),
              const SizedBox(height: 10),
              Text(
                searching ? '没有匹配的记录' : '暂无执行记录',
                style: TextStyle(fontSize: fs, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
              if (searching) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    filter = 'all';
                    hostFilter = 'all';
                    query = '';
                    _q.clear();
                  }),
                  child: const Text('清除筛选'),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '下拉可刷新',
                  style: TextStyle(fontSize: fs - 2, color: AppColors.textFaint),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsList(BuildContext context, AppState state, List<Map> list, double fs) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: list.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
      itemBuilder: (ctx, i) {
        if (i == list.length) {
          final st = context.watch<AppState>();
          if (list.length < st.auditLimit) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: TextButton.icon(
                onPressed: () => st.refreshAudit(limit: st.auditLimit + 100),
                icon: const Icon(Icons.expand_more, size: 16),
                label: Text('加载更多（当前 ${st.auditLimit} 条）', style: TextStyle(fontSize: fs - 1)),
              ),
            ),
          );
        }

        final e = list[i];
        final risk = e['risk']?.toString() ?? '';
        final cmd = e['command']?.toString() ?? '';
        final exit = e['exitCode'];
        final at = _fmtLocal(e['createdAt']?.toString() ?? '', relative: true);
        final hostId = e['hostId']?.toString() ?? '';
        final hostName = _hostLabel(state, hostId);
        final rc = _riskColor(risk);
        return InkWell(
          onTap: () => _showDetail(context, e, hostName, fs),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: rc, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cmd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fs,
                          fontFamily: 'monospace',
                          height: 1.3,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            risk.isEmpty ? '-' : risk,
                            style: TextStyle(fontSize: fs - 2, color: rc, fontWeight: FontWeight.w600),
                          ),
                          Text('exit $exit', style: TextStyle(fontSize: fs - 2, color: AppColors.textMuted, fontFamily: 'monospace')),
                          Text(hostName, style: TextStyle(fontSize: fs - 2, color: AppColors.chipBlue)),
                          if (at.isNotEmpty)
                            Text(at, style: TextStyle(fontSize: fs - 2, color: AppColors.textMuted, fontFamily: 'monospace')),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.iconFaint),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordsPage(BuildContext context) {
    context.select((AppState s) => s.audit.length);
    context.select((AppState s) => s.hosts.length);
    final fs = context.select((AppState s) => s.recordsFontSize);
    final state = context.read<AppState>();
    final all = state.audit.whereType<Map>().toList();

    final hostIds = <String>{};
    for (final e in all) {
      final id = e['hostId']?.toString() ?? '';
      if (id.isNotEmpty) hostIds.add(id);
    }

    var list = all;
    if (filter != 'all') {
      list = list.where((e) => (e['risk']?.toString() ?? '') == filter).toList();
    }
    if (hostFilter != 'all') {
      list = list.where((e) => (e['hostId']?.toString() ?? '') == hostFilter).toList();
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final cmd = (e['command']?.toString() ?? '').toLowerCase();
        final out = (e['stdout']?.toString() ?? '').toLowerCase();
        final err = (e['stderr']?.toString() ?? '').toLowerCase();
        final hid = (e['hostId']?.toString() ?? '').toLowerCase();
        final risk = (e['risk']?.toString() ?? '').toLowerCase();
        final hostName = _hostLabel(state, e['hostId']?.toString() ?? '').toLowerCase();
        return cmd.contains(q) || out.contains(q) || err.contains(q) || hid.contains(q) || risk.contains(q) || hostName.contains(q);
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 48,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        titleSpacing: 12,
        backgroundColor: AppColors.bg,
        title: Text('记录', style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '导出 CSV',
            onPressed: list.isEmpty ? null : () => _exportCsv(context, state, list),
            icon: const Icon(Icons.download_outlined, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '刷新',
            onPressed: () => state.refreshAudit(),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.refreshAudit(),
        child: Column(
          children: [
            _buildFilters(context, state, fs, list, hostIds),
            Expanded(
              child: list.isEmpty ? _buildEmptyListState(context, fs) : _buildRecordsList(context, state, list, fs),
            ),
          ],
        ),
      ),
    );
  }
}
