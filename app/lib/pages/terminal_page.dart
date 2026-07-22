import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Real interactive SSH terminal (WebSocket PTY), no WebView/CDN.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  String? _status;

  static const _bg = Color(0xFF0A0A0A);
  static const _fg = Color(0xFFE8E8E8);
  static const _green = Color(0xFF3DDC84);
  static const _muted = Color(0xFF888888);

  @override
  void dispose() {
    _sub?.cancel();
    _ch?.sink.close();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final id = state.selectedHostId;
    if (id != null && id != _hostId && state.backendOk) {
      _hostId = id;
      _connect(state);
    }
  }

  void _append(String s) {
    _buf.write(s);
    // keep last ~80k chars
    final t = _buf.toString();
    if (t.length > 80000) {
      _buf
        ..clear()
        ..write(t.substring(t.length - 40000));
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  /// Strip common CSI/OSC for plain Text display (good enough for shell use).
  String _stripAnsi(String s) {
    return s
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '')
        .replaceAll(RegExp(r'\x1B[>=()]'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }

  Future<void> _connect(AppState state) async {
    final hostId = state.selectedHostId;
    if (hostId == null) {
      setState(() => _status = '请先选择主机');
      return;
    }
    await _disconnect(silent: true);
    setState(() {
      _connecting = true;
      _status = '连接中…';
      _connected = false;
      _buf.clear();
    });

    final base = state.api.baseUrl; // http://127.0.0.1:17890
    final token = state.api.localToken;
    final uri = Uri.parse(base);
    final wsUri = Uri(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      host: uri.host.isEmpty ? '127.0.0.1' : uri.host,
      port: uri.hasPort ? uri.port : 17890,
      path: '/v1/pty',
      queryParameters: {
        'token': token,
        'hostId': hostId,
        'cols': '80',
        'rows': '24',
      },
    );

    try {
      final ch = IOWebSocketChannel.connect(wsUri);
      _ch = ch;
      _sub = ch.stream.listen(
        (event) {
          if (event is String) {
            try {
              final msg = jsonDecode(event) as Map<String, dynamic>;
              final type = msg['type']?.toString();
              if (type == 'ready') {
                setState(() {
                  _connected = true;
                  _connecting = false;
                  _status = '已连接';
                });
              } else if (type == 'error') {
                _append('\n[error] ${msg['data']}\n');
              } else if (type == 'exit') {
                _append('\n[session closed]\n');
                setState(() {
                  _connected = false;
                  _status = '已断开';
                });
              }
            } catch (_) {
              _append(_stripAnsi(event));
            }
          } else if (event is List<int>) {
            _append(_stripAnsi(utf8.decode(event, allowMalformed: true)));
          } else if (event is ByteBuffer) {
            _append(_stripAnsi(utf8.decode(event.asUint8List(), allowMalformed: true)));
          } else if (event is Uint8List) {
            _append(_stripAnsi(utf8.decode(event, allowMalformed: true)));
          }
        },
        onError: (e) {
          _append('\n[ws error] $e\n');
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '连接错误';
          });
        },
        onDone: () {
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '已断开';
          });
        },
      );
      // also mark connecting until ready; some servers only send binary
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _connecting) {
          setState(() {
            _connecting = false;
            _connected = true;
            _status = '已连接';
          });
        }
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _connected = false;
        _status = '连接失败: $e';
      });
      _append('\n连接失败: $e\n');
    }
  }

  Future<void> _disconnect({bool silent = false}) async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    if (!silent && mounted) {
      setState(() {
        _connected = false;
        _status = '已断开';
      });
    }
  }

  void _sendInput(String data) {
    final ch = _ch;
    if (ch == null) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  void _onSubmit() {
    final text = _input.text;
    if (text.isEmpty) {
      _sendInput('\n');
      return;
    }
    // Send line + newline to shell (normal terminal behavior when using line editor UI)
    _sendInput('$text\n');
    _input.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canUse = state.backendOk && state.selectedHostId != null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: const Color(0xFF141414),
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.circle,
                  size: 10,
                  color: _connected
                      ? _green
                      : _connecting
                          ? Colors.amber
                          : Colors.redAccent,
                ),
                title: Text(
                  state.selectedHostId == null ? '终端' : state.hostLabel,
                  style: const TextStyle(color: _fg, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _status ?? (canUse ? 'SSH' : '未就绪'),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '重连',
                      onPressed: canUse ? () => _connect(state) : null,
                      icon: const Icon(Icons.refresh, color: _muted, size: 20),
                    ),
                    IconButton(
                      tooltip: '清屏',
                      onPressed: () => setState(() => _buf.clear()),
                      icon: const Icon(Icons.cleaning_services_outlined, color: _muted, size: 18),
                    ),
                    IconButton(
                      tooltip: '复制',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _buf.toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                        );
                      },
                      icon: const Icon(Icons.copy, color: _muted, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _focus.requestFocus(),
                child: Container(
                  width: double.infinity,
                  color: _bg,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _buf.isEmpty
                          ? (canUse ? '正在连接远程 shell…\n' : '请先在主机页选择服务器\n')
                          : _buf.toString(),
                      style: const TextStyle(
                        color: _fg,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // quick keys row
            Container(
              color: const Color(0xFF141414),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _KeyChip(label: 'Tab', onTap: () => _sendInput('\t')),
                    _KeyChip(label: 'Ctrl-C', onTap: () => _sendInput('\x03')),
                    _KeyChip(label: 'Ctrl-D', onTap: () => _sendInput('\x04')),
                    _KeyChip(label: 'Ctrl-L', onTap: () => _sendInput('\x0c')),
                    _KeyChip(label: 'Esc', onTap: () => _sendInput('\x1b')),
                    _KeyChip(label: '↑', onTap: () => _sendInput('\x1b[A')),
                    _KeyChip(label: '↓', onTap: () => _sendInput('\x1b[B')),
                    _KeyChip(label: '←', onTap: () => _sendInput('\x1b[D')),
                    _KeyChip(label: '→', onTap: () => _sendInput('\x1b[C')),
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFF141414),
              padding: EdgeInsets.only(
                left: 8,
                right: 4,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom + 4,
              ),
              child: Row(
                children: [
                  const Text(
                    '\$ ',
                    style: TextStyle(color: _green, fontFamily: 'monospace', fontSize: 13),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: _connected,
                      style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13),
                      cursorColor: _green,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _onSubmit(),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输入命令…',
                        hintStyle: TextStyle(color: Color(0xFF555555), fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _connected ? _onSubmit : null,
                    icon: Icon(Icons.keyboard_return, color: _connected ? _green : _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        label: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC))),
        backgroundColor: const Color(0xFF222222),
        side: BorderSide.none,
        onPressed: onTap,
      ),
    );
  }
}
