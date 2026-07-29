part of 'settings_page.dart';

extension _SettingsPageBackendSection on _SettingsPageState {
  Widget _backendSection(AppState state) {
    return _section(
      icon: Icons.dns_outlined,
      accent: AppColors.success,
      title: 'Backend',
      subtitle: 'Local Go service and token',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _statusChip(state.backendOk, state.backendOk ? 'connected' : 'disconnected'),
            _portChip(state.api.baseUrl),
            Text(
              state.api.baseUrl,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'The backend URL is used for all local API calls.',
          style: TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.35),
        ),
        if (state.backendVersion != null) ...[
          const SizedBox(height: 6),
          Text(
            'Version ${state.backendVersion}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
          ),
        ],
        if (state.backendFeatures.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Features', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in state.backendFeatures)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: f == 'tokstream' || f == 'stream' || f == 'fscopy' || f == 'fsmove'
                          ? AppColors.accentSoft.withAlpha(0x66)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: f == 'tokstream' || f == 'stream' ? AppColors.accentSoft : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (state.backendNote != null) ...[
          const SizedBox(height: 6),
          Text(state.backendNote!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: baseUrl,
          style: const TextStyle(fontSize: 13.5),
          decoration: const InputDecoration(
            labelText: 'Go Base URL',
            isDense: true,
            prefixIcon: Icon(Icons.link, size: 18),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: token,
          style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'X-Local-Token',
            isDense: true,
            prefixIcon: Icon(Icons.key, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () async {
            try {
              await state.saveConnection(baseUrl: baseUrl.text.trim(), token: token.text.trim());
              _toast(state.backendOk ? '已保存' : '保存失败：${state.backendError}');
            } catch (e) {
              _toast('$e');
            }
          },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存并连接'),
        ),
      ],
    );
  }
}
