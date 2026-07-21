import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final baseUrl = TextEditingController(text: 'http://127.0.0.1:17890');
  final token = TextEditingController();
  final llmBase = TextEditingController();
  final llmKey = TextEditingController();
  final llmModel = TextEditingController(text: 'grok-4.5');
  bool loaded = false;

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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final llm = state.llm;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('后端连接', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            state.backendOk ? '状态：已连接' : '状态：未连接',
            style: TextStyle(color: state.backendOk ? Colors.green : Colors.red),
          ),
          if (state.backendNote != null) Text(state.backendNote!),
          TextField(
            controller: baseUrl,
            decoration: const InputDecoration(
              labelText: 'Go Base URL',
              helperText: '开发默认 http://127.0.0.1:17890',
            ),
          ),
          TextField(
            controller: token,
            decoration: const InputDecoration(
              labelText: 'X-Local-Token',
              helperText: '读自 backend 数据目录 local.token',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              try {
                await state.saveConnection(
                  baseUrl: baseUrl.text.trim(),
                  token: token.text.trim(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.backendOk ? '已连接' : '仍失败：${state.backendError}')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('保存并连接后端'),
          ),
          const Divider(height: 32),
          Text('大模型（存于 Go 加密库）', style: Theme.of(context).textTheme.titleMedium),
          if (llm != null) ...[
            Text('Key 已设置：${llm['apiKeySet'] == true}  ${llm['apiKeyMasked'] ?? ''}'),
          ],
          TextField(
            controller: llmBase,
            decoration: const InputDecoration(
              labelText: 'LLM Base URL',
              helperText: '如 http://IP:8317/v1',
            ),
          ),
          TextField(
            controller: llmKey,
            decoration: const InputDecoration(
              labelText: 'API Key（留空则不修改）',
            ),
            obscureText: true,
          ),
          TextField(
            controller: llmModel,
            decoration: const InputDecoration(labelText: '模型'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: !state.backendOk
                ? null
                : () async {
                    try {
                      await state.saveLlm(
                        baseUrl: llmBase.text.trim(),
                        model: llmModel.text.trim(),
                        apiKey: llmKey.text,
                      );
                      llmKey.clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('LLM 设置已保存')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
            child: const Text('保存 LLM 设置'),
          ),
        ],
      ),
    );
  }
}
