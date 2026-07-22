import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Real interactive SSH terminal via backend PTY WebSocket + xterm.js.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  WebViewController? _controller;
  String? _loadedForHost;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    _ensureTerminal(state);
  }

  Future<void> _ensureTerminal(AppState state) async {
    if (!state.backendOk) {
      setState(() {
        _error = '后端未连接';
        _loading = false;
      });
      return;
    }
    final hostId = state.selectedHostId;
    if (hostId == null) {
      setState(() {
        _error = '请先在「主机」页选择一台机器';
        _loading = false;
        _controller = null;
        _loadedForHost = null;
      });
      return;
    }
    if (_loadedForHost == hostId && _controller != null && _error == null) {
      return;
    }

    final token = state.api.localToken;
    final base = state.api.baseUrl;
    final label = Uri.encodeComponent(state.hostLabel);
    final uri = Uri.parse(
      'file:///android_asset/flutter_assets/assets/terminal/index.html'
      '?token=${Uri.encodeComponent(token)}'
      '&hostId=${Uri.encodeComponent(hostId)}'
      '&base=${Uri.encodeComponent(base)}'
      '&label=$label',
    );

    // Prefer asset path via loadFlutterAsset for reliability
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (mounted) {
              setState(() {
                _error = e.description;
                _loading = false;
              });
            }
          },
        ),
      );

    setState(() {
      _controller = c;
      _loadedForHost = hostId;
      _loading = true;
      _error = null;
    });

    try {
      await c.loadFlutterAsset('assets/terminal/index.html');
      // inject query params after load because loadFlutterAsset can't take query
      await c.runJavaScript('''
        (function(){
          const q = new URLSearchParams({
            token: ${jsStr(token)},
            hostId: ${jsStr(hostId)},
            base: ${jsStr(base)},
            label: ${jsStr(state.hostLabel)}
          });
          // if page already read empty params, force reconnect with injected globals
          window.__SSH = {
            token: ${jsStr(token)},
            hostId: ${jsStr(hostId)},
            base: ${jsStr(base)},
            label: ${jsStr(state.hostLabel)}
          };
          if (typeof connect === 'function') {
            // patch params from __SSH
            try {
              const title = document.getElementById('title');
              if (title) title.textContent = window.__SSH.label;
            } catch(e){}
          }
        })();
      ''');
      // Hard reload with query via data is messy; instead rewrite page connect using injected values.
      await c.runJavaScript(_injectConnectJs(token, hostId, base, state.hostLabel));
    } catch (e) {
      // fallback: try loadRequest with file uri (may fail on some WebViews)
      try {
        await c.loadRequest(uri);
      } catch (e2) {
        if (mounted) {
          setState(() {
            _error = '终端页加载失败: $e';
            _loading = false;
          });
        }
      }
    }
  }

  static String jsStr(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  /// Override connect() to use injected credentials (asset load has no query string).
  static String _injectConnectJs(String token, String hostId, String base, String label) {
    return '''
(function(){
  const token = ${jsStr(token)};
  const hostId = ${jsStr(hostId)};
  const base = ${jsStr(base)};
  const label = ${jsStr(label)};
  try { document.getElementById('title').textContent = label; } catch(e){}
  function wsURL() {
    const u = new URL(base);
    const proto = u.protocol === 'https:' ? 'wss:' : 'ws:';
    const cols = (typeof term !== 'undefined' && term.cols) ? term.cols : 80;
    const rows = (typeof term !== 'undefined' && term.rows) ? term.rows : 24;
    return proto + '//' + u.host + '/v1/pty?token=' + encodeURIComponent(token)
      + '&hostId=' + encodeURIComponent(hostId)
      + '&cols=' + cols + '&rows=' + rows;
  }
  if (typeof connect === 'function') {
    const old = connect;
    window.connect = function() {
      if (typeof ws !== 'undefined' && ws) { try { ws.close(); } catch(e){} }
      if (typeof term !== 'undefined') term.writeln('\\r\\n\\x1b[90mconnecting…\\x1b[0m');
      if (typeof setDot === 'function') setDot(false);
      ws = new WebSocket(wsURL());
      ws.binaryType = 'arraybuffer';
      ws.onopen = function() {
        if (typeof setDot === 'function') setDot(true);
        if (typeof fit !== 'undefined') fit.fit();
        if (typeof sendResize === 'function') sendResize();
      };
      ws.onmessage = function(ev) {
        if (typeof ev.data === 'string') {
          try {
            const msg = JSON.parse(ev.data);
            if (msg.type === 'error') term.writeln('\\r\\n\\x1b[31m' + (msg.data||'error') + '\\x1b[0m');
            else if (msg.type === 'exit') { term.writeln('\\r\\n\\x1b[33m[session closed]\\x1b[0m'); setDot(false); }
          } catch(_) { term.write(ev.data); }
          return;
        }
        term.write(new Uint8Array(ev.data));
      };
      ws.onclose = function(){ setDot(false); term.writeln('\\r\\n\\x1b[90mdisconnected\\x1b[0m'); };
      ws.onerror = function(){ setDot(false); };
    };
    // rebind button
    try { document.getElementById('btnReconnect').onclick = window.connect; } catch(e){}
    window.connect();
  }
})();
''';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // rebuild when host changes
    if (state.selectedHostId != _loadedForHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTerminal(state));
    }

    if (state.selectedHostId == null) {
      return const Scaffold(
        body: Center(child: Text('请先在「主机」页选择一台机器')),
      );
    }
    if (_error != null && _controller == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => _ensureTerminal(state), child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null) WebViewWidget(controller: _controller!),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
