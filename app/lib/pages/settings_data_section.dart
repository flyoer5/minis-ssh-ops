part of 'settings_page.dart';

extension _SettingsPageDataSection on _SettingsPageState {
  Widget _dataSection(AppState state) {
    return _section(
      icon: Icons.medical_services_outlined,
      accent: AppColors.accentPink,
      title: 'Data & Diagnostics',
      subtitle: 'Export, import, logs, and trusted host records',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: !state.backendOk
                  ? null
                  : () async {
                      try {
                        final json = await state.exportConfigJson();
                        if (!context.mounted) return;
                        await showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Export config'),
                            content: SizedBox(
                              width: double.maxFinite,
                              height: 280,
                              child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: json));
                                  Navigator.pop(c);
                                  _toast('copied');
                                },
                                child: const Text('Copy'),
                              ),
                              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
                            ],
                          ),
                        );
                      } catch (e) {
                        _toast('$e');
                      }
                    },
              icon: const Icon(Icons.upload_outlined, size: 16),
              label: const Text('Export config'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk
                  ? null
                  : () async {
                      final ctrl = TextEditingController();
                      try {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Import config JSON'),
                            content: TextField(
                              controller: ctrl,
                              maxLines: 12,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          _toast(await state.importConfigJson(ctrl.text));
                        }
                      } catch (e) {
                        _toast('$e');
                      } finally {
                        ctrl.dispose();
                      }
                    },
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Import config'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final log = await state.exportBackendLog();
                if (!context.mounted) return;
                await showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('backend.log'),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 360,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          log.isEmpty ? '(empty)' : log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: log));
                          Navigator.pop(c);
                        },
                        child: const Text('Copy'),
                      ),
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('Backend log'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk ? null : () => _openHostKeySheet(state),
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: const Text('Host keys'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk ? null : () => _openLongMemSheet(state),
              icon: const Icon(Icons.psychology_outlined, size: 16),
              label: const Text('Session memory'),
            ),
          ],
        ),
      ],
    );
  }
}
