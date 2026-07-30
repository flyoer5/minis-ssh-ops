part of 'settings_page.dart';

extension _SettingsPageDisplaySection on _SettingsPageState {
  Widget _displaySection(AppState state) {
    final themeText = switch (state.themeMode) {
      'dark' => '暗色',
      'light' => '亮色',
      _ => '跟随系统',
    };
    return _section(
      icon: Icons.text_fields,
      accent: AppColors.chipBlue,
      title: '显示设置',
      subtitle: '主题、导航、字体缩放与探测',
      children: [
        const Text('外观主题', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'system', label: Text('跟随系统'), icon: Icon(Icons.phone_android, size: 16)),
            ButtonSegment(value: 'dark', label: Text('暗色'), icon: Icon(Icons.dark_mode, size: 16)),
            ButtonSegment(value: 'light', label: Text('亮色'), icon: Icon(Icons.light_mode, size: 16)),
          ],
          selected: {state.themeMode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            state.setThemeMode(s.first);
          },
          style: const ButtonStyle(textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
        ),
        const SizedBox(height: 4),
        Text('当前模式：$themeText', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        const Text('全局缩放', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '缩小',
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () => state.setUiScale((state.uiScale - 0.05).clamp(0.8, 1.3)),
            ),
            Expanded(
              child: Slider(
                value: state.uiScale,
                min: 0.8,
                max: 1.3,
                divisions: 10,
                label: '${(state.uiScale * 100).toInt()}%',
                onChanged: (v) => state.setUiScale(v.roundToDouble() / 100.0),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '放大',
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => state.setUiScale((state.uiScale + 0.05).clamp(0.8, 1.3)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('影响所有页面字体大小（${(state.uiScale * 100).round()}%）。', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        const Text('导航方式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'bottom', label: Text('底部导航'), icon: Icon(Icons.space_dashboard_outlined, size: 16)),
            ButtonSegment(value: 'menu', label: Text('侧边菜单'), icon: Icon(Icons.menu, size: 16)),
          ],
          selected: {state.navMode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            state.setNavMode(s.first);
          },
          style: const ButtonStyle(textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
        ),
        const SizedBox(height: 4),
        Text(
          state.navIsMenu ? '当前使用侧边菜单导航。' : '当前使用底部导航栏。',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('紧凑主机卡片', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('使用信息更紧凑的卡片布局', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          value: state.hostCardCompact,
          onChanged: (v) => state.setHostCardCompact(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('流式渲染 Markdown', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('接收回复时同步渲染 Markdown', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          value: state.streamMarkdown,
          onChanged: (v) => state.setStreamMarkdown(v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text('主机探测并发数', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text('${(_draftProbeConc ?? state.probeConcurrency.toDouble()).round()}',
                style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue)),
          ],
        ),
        Slider(
          value: (_draftProbeConc ?? state.probeConcurrency.toDouble()).clamp(1, 6),
          min: 1,
          max: 6,
          divisions: 5,
          label: '${(_draftProbeConc ?? state.probeConcurrency.toDouble()).round()}',
          onChanged: (v) => setState(() => _draftProbeConc = v),
          onChangeEnd: (v) {
            state.setProbeConcurrency(v.round());
            setState(() => _draftProbeConc = null);
          },
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in const [1, 2, 4, 6])
              ActionChip(
                label: Text('$n', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                visualDensity: VisualDensity.compact,
                backgroundColor: state.probeConcurrency == n ? AppColors.accentDeep.withAlpha(0x33) : null,
                onPressed: () => state.setProbeConcurrency(n),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '数值越高，同时探测的主机越多。',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('自动探测间隔', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              (() {
                final n = (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).round();
                return n == 0 ? '关闭' : '$n 秒';
              })(),
              style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue),
            ),
          ],
        ),
        Slider(
          value: (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).clamp(0, 300),
          min: 0,
          max: 300,
          divisions: 30,
          label: (() {
            final n = (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).round();
            return n == 0 ? '关闭' : '$n 秒';
          })(),
          onChanged: (v) => setState(() => _draftAutoProbe = v),
          onChangeEnd: (v) {
            final raw = v.round();
            final snapped = raw == 0 ? 0 : ((raw / 10).round() * 10).clamp(10, 300);
            state.setHostAutoProbeSec(snapped);
            setState(() => _draftAutoProbe = null);
          },
        ),
        const Text(
          '设为 0 可关闭自动探测。',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 8),
        _fontSlider(
          context: context,
          label: '终端字号',
          value: _draftTermFont ?? state.termFontSize,
          min: 10,
          max: 20,
          onChanged: (v) => setState(() => _draftTermFont = v),
          onChangeEnd: (v) {
            state.setTermFontSize(v);
            setState(() => _draftTermFont = null);
          },
          hint: '用于终端页面。',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: 'Agent 字号',
          value: _draftAgentFont ?? state.agentFontSize,
          min: 12,
          max: 20,
          onChanged: (v) => setState(() => _draftAgentFont = v),
          onChangeEnd: (v) {
            state.setAgentFontSize(v);
            setState(() => _draftAgentFont = null);
          },
          hint: '用于 Agent 对话页面。',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: '记录字号',
          value: _draftRecordsFont ?? state.recordsFontSize,
          min: 11,
          max: 18,
          onChanged: (v) => setState(() => _draftRecordsFont = v),
          onChangeEnd: (v) {
            state.setRecordsFontSize(v);
            setState(() => _draftRecordsFont = null);
          },
          hint: '用于记录列表。',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: '界面字号',
          value: _draftUiFont ?? state.uiFontSize,
          min: 11,
          max: 20,
          onChanged: (v) => setState(() => _draftUiFont = v),
          onChangeEnd: (v) {
            state.setUiFontSize(v);
            setState(() => _draftUiFont = null);
          },
          hint: '用于卡片、列表等通用界面。',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: '编辑器字号',
          value: _draftEditorFont ?? state.editorFontSize,
          min: 10,
          max: 24,
          onChanged: (v) => setState(() => _draftEditorFont = v),
          onChangeEnd: (v) {
            state.setEditorFontSize(v);
            setState(() => _draftEditorFont = null);
          },
          hint: '用于文件编辑器。',
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('预览：Agent 对话', style: TextStyle(fontSize: state.effectiveAgentFontSize(), color: context.text)),
              const SizedBox(height: 4),
              Text(
                '预览：等宽字体记录内容',
                style: TextStyle(
                  fontSize: state.effectiveRecordsFontSize(),
                  fontFamily: 'monospace',
                  color: context.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '预览：界面标签',
                style: TextStyle(fontSize: state.effectiveUiFontSize(), color: context.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                '预览：终端文本',
                style: TextStyle(
                  fontSize: state.effectiveTermFontSize(),
                  fontFamily: 'monospace',
                  color: context.success,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '预览：编辑器文本',
                style: TextStyle(
                  fontSize: state.effectiveEditorFontSize(),
                  fontFamily: 'monospace',
                  color: AppColors.chipBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
