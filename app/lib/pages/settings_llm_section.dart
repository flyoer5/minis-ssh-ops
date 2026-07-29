part of 'settings_page.dart';

extension _SettingsPageLlmSection on _SettingsPageState {
  Widget _llmSection(AppState state) {
    return _section(
      icon: Icons.smart_toy_outlined,
      accent: AppColors.purple,
      title: 'Model',
      subtitle: 'OpenAI-compatible endpoint',
      children: [
        TextField(
          controller: llmBase,
          style: const TextStyle(fontSize: 13.5),
          decoration: const InputDecoration(
            labelText: 'LLM Base URL',
            helperText: 'Usually ends with /v1',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: llmKey,
          obscureText: _obscureKey,
          enableSuggestions: false,
          autocorrect: false,
          style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'API Key',
            helperText: 'Stored locally',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscureKey ? 'Show' : 'Hide',
              icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _modelIds.isEmpty
                  ? TextField(
                      controller: llmModel,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        helperText: '刷新以加载模型列表',
                        isDense: true,
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _modelIds.contains(llmModel.text) ? llmModel.text : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Model', isDense: true),
                      items: [
                        for (final id in _modelIds)
                          DropdownMenuItem(
                            value: id,
                            child: Text(id, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => llmModel.text = v);
                      },
                    ),
            ),
            IconButton(
              tooltip: '拉取模型列表',
              onPressed: !state.backendOk || _loadingModels ? null : () => _refreshModels(state),
              icon: _loadingModels
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        if (_modelIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text('Loaded ${_modelIds.length} models', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        DropdownButtonFormField<String>(
          initialValue: const ['none', 'auto', 'low', 'medium', 'high', 'xhigh'].contains(thinkingLevel) ? thinkingLevel : 'auto',
          decoration: const InputDecoration(
            labelText: '思考级别',
            helperText: 'Optional provider hint',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('none')),
            DropdownMenuItem(value: 'auto', child: Text('auto')),
            DropdownMenuItem(value: 'low', child: Text('low')),
            DropdownMenuItem(value: 'medium', child: Text('medium')),
            DropdownMenuItem(value: 'high', child: Text('high')),
            DropdownMenuItem(value: 'xhigh', child: Text('xhigh')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => thinkingLevel = v);
          },
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: !state.backendOk
              ? null
              : () async {
                  try {
                    await state.saveLlm(
                      baseUrl: llmBase.text.trim(),
                      model: llmModel.text.trim(),
                      apiKey: llmKey.text,
                      thinkingLevel: thinkingLevel,
                    );
                    await _refreshModels(state);
                    _toast('LLM saved');
                  } catch (e) {
                    _toast('$e');
                  }
                },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存模型'),
        ),
      ],
    );
  }
}
