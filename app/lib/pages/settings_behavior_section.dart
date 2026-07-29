part of 'settings_page.dart';

extension _SettingsPageBehaviorSection on _SettingsPageState {
  Widget _behaviorSection(AppState state) {
    return _section(
      icon: Icons.rule_folder_outlined,
      accent: AppColors.warning,
      title: 'Behavior',
      subtitle: 'Agent interaction settings',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Confirm writes', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Require confirmation for destructive commands', style: TextStyle(fontSize: 11.5)),
          value: state.confirmWrites,
          onChanged: (v) => state.setConfirmWrites(v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text('Max rounds', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '${(_draftMaxRounds ?? state.agentMaxRounds.toDouble()).round()}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.chipBlue, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        Slider(
          value: (_draftMaxRounds ?? state.agentMaxRounds.toDouble()).clamp(1, 99),
          min: 1,
          max: 99,
          divisions: 98,
          label: '${(_draftMaxRounds ?? state.agentMaxRounds.toDouble()).round()}',
          onChanged: (v) => setState(() => _draftMaxRounds = v),
          onChangeEnd: (v) {
            state.setAgentMaxRounds(v.round());
            setState(() => _draftMaxRounds = null);
          },
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in const [4, 8, 12, 24, 40, 64])
              ActionChip(
                label: Text('$n', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                visualDensity: VisualDensity.compact,
                backgroundColor: state.agentMaxRounds == n ? AppColors.accentDeep.withAlpha(0x33) : null,
                onPressed: () => state.setAgentMaxRounds(n),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Lower values keep the loop shorter.',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text('Temperature', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              (() {
                final x = _draftTemp ?? state.agentTemperature;
                return x == 0 ? 'default' : x.toStringAsFixed(1);
              })(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.chipBlue, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: (_draftTemp ?? state.agentTemperature).clamp(0, 2),
          min: 0,
          max: 2,
          divisions: 20,
          label: (() {
            final x = _draftTemp ?? state.agentTemperature;
            return x == 0 ? 'default' : x.toStringAsFixed(1);
          })(),
          onChanged: (v) => setState(() => _draftTemp = v),
          onChangeEnd: (v) {
            state.setAgentTemperature(v);
            setState(() => _draftTemp = null);
          },
        ),
        const Text('0 uses the provider default.', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
        const SizedBox(height: 8),
        const Text('Custom prompt', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: customPrompt,
          decoration: const InputDecoration(
            hintText: 'Optional prompt prefix for the agent',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
          onEditingComplete: () => state.setAgentCustomPrompt(customPrompt.text),
          onTapOutside: (_) => state.setAgentCustomPrompt(customPrompt.text),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show reasoning', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Display reasoning when available', style: TextStyle(fontSize: 11.5)),
          value: state.agentShowReasoning,
          onChanged: (v) => state.setAgentShowReasoning(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Collapse tools', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Compact completed tool results', style: TextStyle(fontSize: 11.5)),
          value: state.agentCollapseTools,
          onChanged: (v) => state.setAgentCollapseTools(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Auto scroll', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Follow the conversation while streaming', style: TextStyle(fontSize: 11.5)),
          value: state.agentAutoScroll,
          onChanged: (v) => state.setAgentAutoScroll(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Enter to send', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Press Enter to submit a message', style: TextStyle(fontSize: 11.5)),
          value: state.agentEnterToSend,
          onChanged: (v) => state.setAgentEnterToSend(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Keep keyboard open', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Do not hide the keyboard after send', style: TextStyle(fontSize: 11.5)),
          value: state.agentKeepKeyboard,
          onChanged: (v) => state.setAgentKeepKeyboard(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Haptic feedback', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Subtle vibration on actions', style: TextStyle(fontSize: 11.5)),
          value: state.hapticFeedback,
          onChanged: (v) => state.setHapticFeedback(v),
        ),
      ],
    );
  }
}
