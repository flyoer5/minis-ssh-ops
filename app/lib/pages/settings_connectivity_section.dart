part of 'settings_page.dart';

extension _SettingsPageConnectivitySection on _SettingsPageState {
  Widget _connectivitySection(AppState state) {
    return _section(
      icon: Icons.network_check,
      accent: AppColors.accentMint,
      title: 'Connectivity',
      subtitle: 'Quick backend reachability checks',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: !state.backendOk || state.selectedHostId == null || pinging
                  ? null
                  : () async {
                      setState(() {
                        pinging = true;
                        pingMsg = null;
                      });
                      try {
                        final o = await state.testHostSsh();
                        if (!mounted) return;
                        setState(() => pingMsg = 'SSH OK: $o');
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => pingMsg = 'SSH 检测失败：${cleanError(e)}');
                      } finally {
                        if (mounted) setState(() => pinging = false);
                      }
                    },
              icon: const Icon(Icons.terminal, size: 16),
              label: const Text('Test SSH'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk || state.selectedHostId == null || pinging
                  ? null
                  : () async {
                      setState(() {
                        pinging = true;
                        pingMsg = null;
                      });
                      try {
                        final o = await state.testLlmReachable();
                        if (!mounted) return;
                        setState(() => pingMsg = o);
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => pingMsg = '模型检测失败：${cleanError(e)}');
                      } finally {
                        if (mounted) setState(() => pinging = false);
                      }
                    },
              icon: const Icon(Icons.psychology_outlined, size: 16),
              label: const Text('Test model'),
            ),
            if (pinging)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
        if (state.selectedHostId == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Select a host first.', style: TextStyle(fontSize: 11, color: AppColors.warning)),
          ),
        if (pingMsg != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              pingMsg!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.textCode),
            ),
          ),
        ],
      ],
    );
  }
}
