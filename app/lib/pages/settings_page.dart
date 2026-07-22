import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AutomaticKeepAliveClientMixin {
  final baseUrl = TextEditingController(text: 'http://127.0.0.1:17890');
  final token = TextEditingController();
  final llmBase = TextEditingController();
  final llmKey = TextEditingController();
  final llmModel = TextEditingController(text: 'grok-4.5');
  bool loaded = false;
  String? pingMsg;
  bool pinging = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    loaded = true;
    final s = context.read<AppState>();
    baseUrl.text = s.api.baseUrl;
    token.text = s.api.localToken;
    final llm = s.llm;
    if (llm != null) {
      llmBase.text = (llm['baseUrl'] as String?) ?? '';
      llmModel.text = (llm['model'] as String?) ?? 'grok-4.5';
    }
  }

  @override
  void dispose() {
    baseUrl.dispose();
    token.dispose();
    llmBase.dispose();
    llmKey.dispose();
    llmModel.dispose();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final llm = state.llm;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('后端', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            state.backendOk ? '已连接 · ${state.api.baseUrl}' : '未连接',
            style: TextStyle(color: state.backendOk ? const Color(0xFF3FB950) : const Color(0xFFF85149)),
          ),
          if (state.backendNote != null) Text(state.backendNote!, style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
          TextField(controller: baseUrl, decoration: const InputDecoration(labelText: 'Go Base URL')),
          TextField(controller: token, decoration: const InputDecoration(labelText: 'X-Local-Token')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              try {
                await state.saveConnection(baseUrl: baseUrl.text.trim(), token: token.text.trim());
                _toast(state.backendOk ? '已连接' : '失败: ${state.backendError}');
              } catch (e) {
                _toast('$e');
              }
            },
            child: const Text('保存并连接'),
          ),
          const Divider(height: 28),
          Text('大模型', style: Theme.of(context).textTheme.titleMedium),
          if (llm != null) Text('Key: ${llm['apiKeySet'] == true ? (llm['apiKeyMasked'] ?? '已设置') : '未设置'}', style: const TextStyle(fontSize: 12)),
          TextField(controller: llmBase, decoration: const InputDecoration(labelText: 'LLM Base URL', helperText: '含 /v1')),
          TextField(controller: llmKey, decoration: const InputDecoration(labelText: 'API Key（留空不改）'), obscureText: true),
          TextField(controller: llmModel, decoration: const InputDecoration(labelText: '模型')),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: !state.backendOk
                ? null
                : () async {
                    try {
                      await state.saveLlm(baseUrl: llmBase.text.trim(), model: llmModel.text.trim(), apiKey: llmKey.text);
                      llmKey.clear();
                      _toast('LLM 已保存');
                    } catch (e) {
                      _toast('$e');
                    }
                  },
            child: const Text('保存 LLM'),
          ),
          const Divider(height: 28),
          Text('连通性', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(
              onPressed: !state.backendOk || state.selectedHostId == null || pinging
                  ? null
                  : () async {
                      setState(() { pinging = true; pingMsg = null; });
                      try {
                        final o = await state.testHostSsh();
                        setState(() => pingMsg = 'SSH OK: $o');
                      } catch (e) {
                        setState(() => pingMsg = 'SSH 失败: $e');
                      } finally {
                        setState(() => pinging = false);
                      }
                    },
              child: const Text('测 SSH'),
            ),
            FilledButton.tonal(
              onPressed: !state.backendOk || state.selectedHostId == null || pinging
                  ? null
                  : () async {
                      setState(() { pinging = true; pingMsg = null; });
                      try {
                        final o = await state.testLlmReachable();
                        setState(() => pingMsg = o);
                      } catch (e) {
                        setState(() => pingMsg = '模型失败: $e');
                      } finally {
                        setState(() => pinging = false);
                      }
                    },
              child: const Text('测模型'),
            ),
            if (pinging) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (pingMsg != null) ...[
            const SizedBox(height: 8),
            SelectableText(pingMsg!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
          const Divider(height: 28),
          Text('保活', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('忽略电池优化'),
            subtitle: Text(state.batteryIgnored ? '已忽略（有利于后台）' : '未忽略，后台易被杀'),
            trailing: TextButton(
              onPressed: () async {
                await state.requestBatteryExempt();
                _toast(state.batteryIgnored ? '已忽略' : '请在系统页确认');
              },
              child: const Text('去设置'),
            ),
          ),
          TextButton(
            onPressed: () => state.openBatterySettings(),
            child: const Text('打开电池优化列表'),
          ),
          const Divider(height: 28),
          Text('终端', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              const Text('字体'),
              Expanded(
                child: Slider(
                  value: state.termFontSize,
                  min: 10,
                  max: 20,
                  divisions: 10,
                  label: state.termFontSize.toStringAsFixed(0),
                  onChanged: (v) => state.setTermFontSize(v),
                ),
              ),
              Text(state.termFontSize.toStringAsFixed(0)),
            ],
          ),
          const Divider(height: 28),
          Text('诊断', style: Theme.of(context).textTheme.titleMedium),
          FilledButton.tonal(
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
                      child: SelectableText(log.isEmpty ? '(empty)' : log, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: log));
                        Navigator.pop(c);
                      },
                      child: const Text('复制关闭'),
                    ),
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                  ],
                ),
              );
            },
            child: const Text('查看后端日志'),
          ),
        ],
      ),
    );
  }
}
