part of 'settings_page.dart';

extension _SettingsPageSectionBuilders on _SettingsPageState {
  List<Widget> _buildSettingsSections(AppState state) {
    final all = <({String title, Widget widget})>[
      (title: '本地后端 本机 Go 服务与访问令牌', widget: _backendSection(state)),
      (title: '模型服务 OpenAI 兼容接口 LLM', widget: _llmSection(state)),
      (title: '显示设置 主题、导航、字体缩放与探测', widget: _displaySection(state)),
      (title: '交互行为 Agent 对话与操作偏好', widget: _behaviorSection(state)),
      (title: '连接检测 SSH 与模型服务连通性', widget: _connectivitySection(state)),
      (title: '后台运行 电池与后台任务限制', widget: _batterySection(state)),
      (title: '数据与诊断 配置导入导出、日志与可信主机', widget: _dataSection(state)),
      (title: '关于 应用版本与后端能力', widget: _aboutSection(state)),
    ];
    final q = _settingsQuery;
    if (q.isEmpty) {
      return [for (final s in all) s.widget];
    }
    final hits = <Widget>[];
    for (final s in all) {
      // Section-level match: title/subtitle.
      if (s.title.toLowerCase().contains(q)) {
        hits.add(s.widget);
        continue;
      }
      // Child-level match: walk widget tree for text matches.
      if (_sectionChildrenContain(s.widget, q)) {
        hits.add(s.widget);
      }
    }
    if (hits.isEmpty) {
      hits.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.search_off, size: 36, color: AppColors.textFaint),
            const SizedBox(height: 10),
            const Text('没有匹配的设置项', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            Text('试试：主题 / 字体 / 确认 / 日志', style: TextStyle(color: AppColors.textFaint, fontSize: 11)),
          ],
        ),
      ));
    }
    return hits;
  }

  /// Recursively checks whether any descendant Text widget contains [q].
  bool _sectionChildrenContain(Widget root, String q) {
    var found = false;
    final queue = <Widget>[root];
    while (queue.isNotEmpty && !found) {
      final w = queue.removeLast();
      if (w is Text) {
        final data = w.data ?? w.textSpan?.toPlainText() ?? '';
        if (data.toLowerCase().contains(q)) {
          found = true;
          break;
        }
      }
      if (w is ListTile) {
        final t = w.title;
        final s = w.subtitle;
        if (t is Text && (t.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (s is Text && (s.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (!found && t is Widget) queue.add(t);
        if (!found && s is Widget) queue.add(s);
      }
      if (w is SwitchListTile) {
        final tile = w as SwitchListTile;
        final t = tile.title;
        final s = tile.subtitle;
        if (t is Text && (t.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (s is Text && (s.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (!found && t is Widget) queue.add(t);
        if (!found && s is Widget) queue.add(s);
      }
      if (w is CheckboxListTile) {
        final tile = w as CheckboxListTile;
        final t = tile.title;
        final s = tile.subtitle;
        if (t is Text && (t.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (s is Text && (s.data?.toLowerCase().contains(q) ?? false)) found = true;
        if (!found && t is Widget) queue.add(t);
        if (!found && s is Widget) queue.add(s);
      }
      final el = w as dynamic;
      for (final p in const ['child', 'children']) {
        final v = el[p];
        if (v is Widget) {
          queue.add(v);
        } else if (v is List) {
          queue.addAll(v.whereType<Widget>());
        }
      }
    }

    return found;
  }
}