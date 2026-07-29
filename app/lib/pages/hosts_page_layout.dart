part of 'hosts_page.dart';

extension HostsPageLayout on _HostsPageState {
  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索名称 / IP / 用户 - 无搜索时长按排序',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.slateFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.slateDeep),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.slateDeep),
          ),
        ),
      ),
    );
  }

  Widget _buildNoMatchState(AppState state) {
    return LayoutBuilder(
      builder: (c, cons) => RefreshIndicator(
        onRefresh: () => _refreshAll(state),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: cons.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('无匹配主机', style: TextStyle(color: AppColors.slate)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: const Text('清除搜索'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHostList(BuildContext context, AppState state, List<Map<String, dynamic>> list, bool canReorder) {
    Widget cardAt(int i) {
      final h = list[i];
      final id = h['id'] as String;
      final name = (h['name'] as String?)?.isNotEmpty == true ? h['name'] as String : '${h['host']}';
      final addr = '${h['username']}@${h['host']}:${h['port']}';
      final auth = h['hasPrivateKey'] == true ? 'key' : (h['hasPassword'] == true ? 'password' : '');
      final card = RepaintBoundary(
        child: _StatusCard(
          name: name,
          addr: addr,
          selected: state.selectedHostId == id,
          loading: _loading.contains(id),
          summary: _summary[id],
          probedAt: state.probeCacheTime(id),
          fontSize: state.uiFontSize,
          compact: state.hostCardCompact,
          authKind: auth,
          onSelect: () => state.selectHost(id),
          onRefresh: () => _refreshProbe(state, id, force: true),
          onMenu: () => _hostMenu(context, state, h),
          longPressOpensMenu: !canReorder,
          onShowDetail: () => _showProbeDetail(
            context,
            name,
            addr,
            _summary[id],
            hostId: id,
            onRetry: () => _refreshProbe(state, id, force: true),
          ),
        ),
      );
      if (!canReorder) return card;
      return ReorderableDelayedDragStartListener(
        key: ValueKey(id),
        index: i,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: card,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refreshAll(state),
      child: canReorder
          ? ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              itemCount: list.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  color: Colors.transparent,
                  child: child,
                );
              },
              onReorderItem: (oldIndex, newIndex) {
                state.reorderHosts(oldIndex, newIndex);
              },
              itemBuilder: (_, i) => cardAt(i),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => cardAt(i),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hostCount = context.select((AppState s) => s.hosts.length);
    context.select((AppState s) => s.selectedHostId);
    context.select((AppState s) => s.probeGen);
    context.select((AppState s) => s.uiFontSize);
    context.select((AppState s) => s.hostCardCompact);
    final backendOk = context.select((AppState s) => s.backendOk);
    context.select((AppState s) => s.probeConcurrency);
    context.select((AppState s) => s.hostAutoProbeSec);
    final state = context.read<AppState>();
    if (!_autoStarted && backendOk && hostCount > 0) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_probeMany(state, force: false));
      });
    }
    _syncAutoProbeTimer(state);
    final total = state.hosts.length;
    final online = state.hosts.where((h) {
      final id = h['id']?.toString();
      if (id == null) return false;
      final s = _summary[id];
      return s != null && s.ok;
    }).length;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        titleSpacing: 4,
        title: Text(
          total == 0 ? '主机' : '主机 - $online/$total 在线',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _refreshAll(state) : null,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _showAdd(context, state) : null,
            icon: const Icon(Icons.add, size: 22),
          ),
        ],
      ),
      body: !state.backendOk
          ? Center(child: FilledButton(onPressed: () => state.bootstrap(), child: const Text('连接后端')))
          : state.hosts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dns_outlined, size: 44, color: AppColors.textFaint),
                        const SizedBox(height: 12),
                        const Text(
                          '还没有主机',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '添加后可在 Agent、终端、文件中使用。支持密码或密钥登录。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.textFaint, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: state.backendOk ? () => _showAdd(context, state) : null,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加主机'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildSearchField(context),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final q = _query;
                          final list = state.hosts.where((raw) {
                            if (q.isEmpty) return true;
                            final h = raw as Map<String, dynamic>;
                            final name = (h['name']?.toString() ?? '').toLowerCase();
                            final host = (h['host']?.toString() ?? '').toLowerCase();
                            final user = (h['username']?.toString() ?? '').toLowerCase();
                            final note = (h['note']?.toString() ?? h['remark']?.toString() ?? '').toLowerCase();
                            final addr = '$user@$host:${h['port']}';
                            return name.contains(q) || host.contains(q) || user.contains(q) || note.contains(q) || addr.contains(q);
                          }).map((raw) => raw as Map<String, dynamic>).toList();
                          if (list.isEmpty) return _buildNoMatchState(state);
                          final canReorder = q.isEmpty && list.length > 1;
                          return _buildHostList(context, state, list, canReorder);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
