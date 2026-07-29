part of 'settings_page.dart';

extension _SettingsPageDataSection on _SettingsPageState {
  Widget _dataSection(AppState state) {
    return _section(
      icon: Icons.medical_services_outlined,
      accent: AppColors.accentPink,
      title: '数据与诊断',
      subtitle: '配置导入导出、日志与可信主机记录',
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
                            title: const Text('导出配置'),
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
                                  _toast('配置已复制到剪贴板');
                                },
                                child: const Text('复制'),
                              ),
                              TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                            ],
                          ),
                        );
                      } catch (e) {
                        _toast('导出失败：${cleanError(e)}');
                      }
                    },
              icon: const Icon(Icons.upload_outlined, size: 16),
              label: const Text('导出配置'),
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
                            title: const Text('导入配置 JSON'),
                            content: TextField(
                              controller: ctrl,
                              maxLines: 12,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('导入')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          _toast(await state.importConfigJson(ctrl.text));
                        }
                      } catch (e) {
                        _toast('导入失败：${cleanError(e)}');
                      } finally {
                        ctrl.dispose();
                      }
                    },
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('导入配置'),
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
                          log.isEmpty ? '暂无日志' : log,
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
                        child: const Text('复制'),
                      ),
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('后端日志'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk ? null : () => _openHostKeySheet(state),
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: const Text('可信主机密钥'),
            ),
            FilledButton.tonalIcon(
              onPressed: !state.backendOk ? null : () => _openLongMemSheet(state),
              icon: const Icon(Icons.psychology_outlined, size: 16),
              label: const Text('长期记忆'),
            ),
          ],
        ),
      ],
    );
  }
}
