import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/opsd_service.dart';
import 'native_hosts_page.dart';

/// Primary UI: embedded opsd Web UI (same as debug page) + native host list fallback.
class HomePage extends StatefulWidget {
  final OpsdService opsd;
  const HomePage({super.key, required this.opsd});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final WebViewController _controller;
  int _tab = 0;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1419))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          // inject token into localStorage for the static UI
          _controller.runJavaScript(
            "localStorage.setItem('opsd_token', '${widget.opsd.token}');",
          );
        },
        onWebResourceError: (e) {
          if (mounted) {
            setState(() {
              _loadError = e.description;
              _loading = false;
            });
          }
        },
      ));
    _openWeb();
  }

  Future<void> _openWeb() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await widget.opsd.ensureRunning();
    final url = '${widget.opsd.baseUrl}/?t=${DateTime.now().millisecondsSinceEpoch}';
    await _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minis SSH Ops'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _openWeb,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '状态',
            onPressed: () async {
              try {
                final h = await widget.opsd.getJson('/api/health');
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('opsd OK · port ${widget.opsd.port} · $h')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('异常: $e')));
              }
            },
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_loadError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('页面加载失败: $_loadError'),
                        const SizedBox(height: 8),
                        const Text('若未打包 Web 静态资源，请用下方「主机」原生页，或把 web/static 拷到 opsd-web。',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _openWeb, child: const Text('重试')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          NativeHostsPage(opsd: widget.opsd),
          _AboutPage(opsd: widget.opsd),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.terminal), label: '控制台'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), label: '主机'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: '关于'),
        ],
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  final OpsdService opsd;
  const _AboutPage({required this.opsd});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Minis SSH Ops', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('本地私有 AI SSH 运维。主机密钥与 API Key 仅存本机，经 AES-GCM 加密。'),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('opsd 地址'),
          subtitle: Text(opsd.baseUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Token'),
          subtitle: Text('${opsd.token.substring(0, 6)}****'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('数据'),
          subtitle: Text('Application Support / opsd-data（SQLite + master.key）'),
        ),
        const SizedBox(height: 12),
        const Text('电池优化', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text('长任务/后台时请在系统设置中关闭本应用的电池限制，避免 opsd 被杀。',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
