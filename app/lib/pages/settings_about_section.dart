part of 'settings_page.dart';

extension _SettingsPageAboutSection on _SettingsPageState {
  Widget _aboutSection(AppState state) {
    return _section(
      icon: Icons.info_outline,
      accent: AppColors.accentSoft,
      title: 'About',
      subtitle: 'Build and backend summary',
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('minis SSH ops', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('SSH agent and remote operations', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentDeep.withAlpha(0x33),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                state.backendVersion?.isNotEmpty == true ? state.backendVersion! : 'unknown',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.chipBlue),
              ),
            ),
          ],
        ),
        if (state.backendFeatures.isNotEmpty) ...[
          const SizedBox(height: 8),
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
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    f,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
