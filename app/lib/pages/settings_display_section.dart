part of 'settings_page.dart';

extension _SettingsPageDisplaySection on _SettingsPageState {
  Widget _displaySection(AppState state) {
    return _section(
      icon: Icons.text_fields,
      accent: AppColors.chipBlue,
      title: '显示设置',
      subtitle: '导航、Markdown、探测和字体大小',
      children: [
        const Text('Navigation mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'bottom', label: Text('底部导航'), icon: Icon(Icons.space_dashboard_outlined, size: 16)),
            ButtonSegment(value: 'menu', label: Text('菜单导航'), icon: Icon(Icons.menu, size: 16)),
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
          state.navIsMenu ? 'Menu navigation is enabled.' : 'Bottom navigation is enabled.',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Compact host cards', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Show a denser card layout', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          value: state.hostCardCompact,
          onChanged: (v) => state.setHostCardCompact(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Stream markdown', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Render assistant markdown while streaming', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          value: state.streamMarkdown,
          onChanged: (v) => state.setStreamMarkdown(v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text('Probe concurrency', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
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
          'Higher values increase parallel host probing.',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('Auto probe interval', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              (() {
                final n = (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).round();
                return n == 0 ? 'off' : '${n}s';
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
            return n == 0 ? 'off' : '${n}s';
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
          '0 disables auto probing.',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 8),
        _fontSlider(
          context: context,
          label: 'Terminal font',
          value: _draftTermFont ?? state.termFontSize,
          min: 10,
          max: 20,
          onChanged: (v) => setState(() => _draftTermFont = v),
          onChangeEnd: (v) {
            state.setTermFontSize(v);
            setState(() => _draftTermFont = null);
          },
          hint: 'Used by the terminal page.',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: 'Agent font',
          value: _draftAgentFont ?? state.agentFontSize,
          min: 12,
          max: 20,
          onChanged: (v) => setState(() => _draftAgentFont = v),
          onChangeEnd: (v) {
            state.setAgentFontSize(v);
            setState(() => _draftAgentFont = null);
          },
          hint: 'Used by the agent page.',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: 'Records font',
          value: _draftRecordsFont ?? state.recordsFontSize,
          min: 11,
          max: 18,
          onChanged: (v) => setState(() => _draftRecordsFont = v),
          onChangeEnd: (v) {
            state.setRecordsFontSize(v);
            setState(() => _draftRecordsFont = null);
          },
          hint: 'Used by records list rows.',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: 'UI font',
          value: _draftUiFont ?? state.uiFontSize,
          min: 11,
          max: 20,
          onChanged: (v) => setState(() => _draftUiFont = v),
          onChangeEnd: (v) {
            state.setUiFontSize(v);
            setState(() => _draftUiFont = null);
          },
          hint: 'Used across cards and lists.',
        ),
        const SizedBox(height: 6),
        _fontSlider(
          context: context,
          label: 'Editor font',
          value: _draftEditorFont ?? state.editorFontSize,
          min: 10,
          max: 24,
          onChanged: (v) => setState(() => _draftEditorFont = v),
          onChangeEnd: (v) {
            state.setEditorFontSize(v);
            setState(() => _draftEditorFont = null);
          },
          hint: 'Used by the file editor.',
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preview: Agent', style: TextStyle(fontSize: state.agentFontSize, color: AppColors.text)),
              const SizedBox(height: 4),
              Text(
                'Preview: record line with monospace text',
                style: TextStyle(
                  fontSize: state.recordsFontSize,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Preview: UI label',
                style: TextStyle(fontSize: state.uiFontSize, color: AppColors.textCode),
              ),
              const SizedBox(height: 4),
              Text(
                'preview terminal',
                style: TextStyle(
                  fontSize: state.termFontSize,
                  fontFamily: 'monospace',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'editor preview',
                style: TextStyle(
                  fontSize: state.editorFontSize,
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
