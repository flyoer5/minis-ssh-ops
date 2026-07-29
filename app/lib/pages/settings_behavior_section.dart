part of 'settings_page.dart';

extension _SettingsPageBehaviorSection on _SettingsPageState {
  Widget _behaviorSection(AppState state) {
    return _section(
      icon: Icons.rule_folder_outlined,
      accent: AppColors.warning,
      title: '交互行为',
      subtitle: 'Agent 对话与操作偏好',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('写入操作需确认', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('执行破坏性命令前要求手动确认', style: TextStyle(fontSize: 11.5)),
          value: state.confirmWrites,
          onChanged: (v) => state.setConfirmWrites(v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text('最大执行轮数', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
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
          '数值越小，单次任务的执行链路越短。',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text('模型温度', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              (() {
                final x = _draftTemp ?? state.agentTemperature;
                return x == 0 ? '默认' : x.toStringAsFixed(1);
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
            return x == 0 ? '默认' : x.toStringAsFixed(1);
          })(),
          onChanged: (v) => setState(() => _draftTemp = v),
          onChangeEnd: (v) {
            state.setAgentTemperature(v);
            setState(() => _draftTemp = null);
          },
        ),
        const Text('设为 0 时使用模型服务商的默认值。', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
        const SizedBox(height: 8),
        const Text('自定义提示词', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: customPrompt,
          decoration: const InputDecoration(
            hintText: '可选：添加到 Agent 提示词前的内容',
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
          title: const Text('显示思考过程', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('模型返回推理内容时一并显示', style: TextStyle(fontSize: 11.5)),
          value: state.agentShowReasoning,
          onChanged: (v) => state.setAgentShowReasoning(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('折叠工具结果', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('完成后以紧凑形式显示工具调用结果', style: TextStyle(fontSize: 11.5)),
          value: state.agentCollapseTools,
          onChanged: (v) => state.setAgentCollapseTools(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('自动滚动', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('流式回复时自动跟随最新内容', style: TextStyle(fontSize: 11.5)),
          value: state.agentAutoScroll,
          onChanged: (v) => state.setAgentAutoScroll(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('回车发送', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('按下回车键直接发送消息', style: TextStyle(fontSize: 11.5)),
          value: state.agentEnterToSend,
          onChanged: (v) => state.setAgentEnterToSend(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('发送后保留键盘', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('发送消息后不自动收起键盘', style: TextStyle(fontSize: 11.5)),
          value: state.agentKeepKeyboard,
          onChanged: (v) => state.setAgentKeepKeyboard(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('触感反馈', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('执行操作时提供轻微振动反馈', style: TextStyle(fontSize: 11.5)),
          value: state.hapticFeedback,
          onChanged: (v) => state.setHapticFeedback(v),
        ),
      ],
    );
  }
}
