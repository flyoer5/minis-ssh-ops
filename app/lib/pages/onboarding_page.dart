import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// First-run wizard: LLM + host, then mark onboarded.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _page = PageController();
  int _i = 0;
  bool _busy = false;
  String? _err;

  final llmBase = TextEditingController(text: 'http://cpa.lgh123.online/v1');
  final llmKey = TextEditingController();
  final llmModel = TextEditingController(text: 'grok-4.5');
  final hostName = TextEditingController(text: 'vps');
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController(text: 'root');
  final password = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    llmBase.dispose();
    llmKey.dispose();
    llmModel.dispose();
    hostName.dispose();
    host.dispose();
    port.dispose();
    user.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skipHost = false}) async {
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (!state.backendOk) {
        await state.bootstrap();
      }
      if (llmBase.text.trim().isNotEmpty && llmModel.text.trim().isNotEmpty) {
        await state.saveLlm(
          baseUrl: llmBase.text.trim(),
          model: llmModel.text.trim(),
          apiKey: llmKey.text.isEmpty ? null : llmKey.text,
        );
      }
      if (!skipHost && host.text.trim().isNotEmpty) {
        await state.addHost({
          'name': hostName.text.trim().isEmpty ? host.text.trim() : hostName.text.trim(),
          'host': host.text.trim(),
          'port': int.tryParse(port.text.trim()) ?? 22,
          'username': user.text.trim().isEmpty ? 'root' : user.text.trim(),
          if (password.text.isNotEmpty) 'password': password.text,
        });
      }
      await state.completeOnboarding();
      widget.onDone();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('初始配置', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => _finish(skipHost: true),
                    child: const Text('跳过'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (v) => setState(() => _i = v),
                children: [
                  _pad(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1/2 大模型', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('OpenAI 兼容接口（含 /v1）', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
                      TextField(controller: llmBase, decoration: const InputDecoration(labelText: 'Base URL')),
                      TextField(controller: llmKey, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                      TextField(controller: llmModel, decoration: const InputDecoration(labelText: 'Model')),
                    ],
                  )),
                  _pad(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2/2 SSH 主机', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(controller: hostName, decoration: const InputDecoration(labelText: '名称')),
                      TextField(controller: host, decoration: const InputDecoration(labelText: '地址')),
                      TextField(controller: port, decoration: const InputDecoration(labelText: '端口'), keyboardType: TextInputType.number),
                      TextField(controller: user, decoration: const InputDecoration(labelText: '用户')),
                      TextField(controller: password, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
                    ],
                  )),
                ],
              ),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_err!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  if (_i > 0)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _page.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                      child: const Text('上一步'),
                    ),
                  const Spacer(),
                  if (_i < 1)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _page.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                      child: const Text('下一步'),
                    )
                  else
                    FilledButton(
                      onPressed: _busy ? null : () => _finish(),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('完成'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.all(20), child: child);
}
