import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Interactive SSH terminal (WebSocket PTY).
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
  bool _ctrl = false;

  static const _bg = Color(0xFF000000);
  static const _panel = Color(0xFF121212);
  static const _fg = Color(0xFFE6E6E6);
  static const _green = Color(0xFF4CD964);
  static const _muted = Color(0xFF8E8E93);
  static const _keyBg = Color(0xFF2C2C2E);
  static const _keyBgActive = Color(0xFF3A3A3C);

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
    final t = _buf.toString();
    if (t.length > 100000) {
      _buf
        ..clear()
        ..write(t.substring(t.length - 50000));
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _stripAnsi(String s) {
    return s
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '')
        .replaceAll(RegExp(r'\x1B.'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '');
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
      _connected = false;
      _status = '连接中…';
      _buf.clear();
    });

    final base = state.api.baseUrl;
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
        'cols': '100',
        'rows': '30',
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
                _append('\n${msg['data']}\n');
              } else if (type == 'exit') {
                _append('\n[断开]\n');
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
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '错误';
          });
          _append('\n连接错误: $e\n');
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '已断开';
          });
        },
      );
      Future.delayed(const Duration(milliseconds: 600), () {
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
        _status = '连接失败';
      });
      _append('连接失败: $e\n');
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

  void _sendRaw(String data) {
    final ch = _ch;
    if (ch == null || !_connected) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  void _tapKey(String label) {
    if (!_connected) return;
    switch (label) {
      case 'Tab':
        _sendRaw('\t');
        break;
      case 'Esc':
        _sendRaw('\x1b');
        break;
      case 'Ctrl':
        setState(() => _ctrl = !_ctrl);
        return;
      case '↑':
        _sendRaw('\x1b[A');
        break;
      case '↓':
        _sendRaw('\x1b[B');
        break;
      case '←':
        _sendRaw('\x1b[D');
        break;
      case '→':
        _sendRaw('\x1b[C');
        break;
      case 'Home':
        _sendRaw('\x1b[H');
        break;
      case 'End':
        _sendRaw('\x1b[F');
        break;
      case 'PgUp':
        _sendRaw('\x1b[5~');
        break;
      case 'PgDn':
        _sendRaw('\x1b[6~');
        break;
      case '—':
        // spacer
        break;
      default:
        // Ctrl + letter chips: C D L Z
        if (_ctrl && label.length == 1) {
          final c = label.toUpperCase().codeUnitAt(0);
          if (c >= 65 && c <= 90) {
            _sendRaw(String.fromCharCode(c - 64));
            setState(() => _ctrl = false);
            return;
          }
        }
        _sendRaw(label);
    }
  }

  void _submit() {
    final text = _input.text;
    if (!_connected) return;
    if (text.isEmpty) {
      _sendRaw('\n');
    } else {
      _sendRaw('$text\n');
      _input.clear();
    }
    _focus.requestFocus();
  }

  Widget _key(String label, {double width = 40, bool wide = false}) {
    final active = label == 'Ctrl' && _ctrl;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(
        width: wide ? 72 : width,
        height: 36,
        child: Material(
          color: active ? _keyBgActive : _keyBg,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _tapKey(label),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? _green : _fg,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
            // top bar
            Container(
              height: 44,
              color: _panel,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connected
                          ? _green
                          : _connecting
                              ? Colors.amber
                              : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.selectedHostId == null ? '终端' : state.hostLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    _status ?? '',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '重连',
                    onPressed: canUse ? () => _connect(state) : null,
                    icon: const Icon(Icons.refresh, color: _muted, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '清屏',
                    onPressed: () => setState(() => _buf.clear()),
                    icon: const Icon(Icons.delete_outline, color: _muted, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _buf.toString()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined, color: _muted, size: 18),
                  ),
                ],
              ),
            ),
            // terminal screen
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _focus.requestFocus(),
                child: Container(
                  width: double.infinity,
                  color: _bg,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _buf.isEmpty
                          ? (canUse ? '' : '请先在「主机」选择服务器\n')
                          : _buf.toString(),
                      style: const TextStyle(
                        color: _fg,
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // special keyboard
            Container(
              color: _panel,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Column(
                children: [
                  Row(
                    children: [
                      _key('Esc', width: 44),
                      _key('Tab', width: 44),
                      _key('Ctrl', width: 48),
                      _key('C', width: 34),
                      _key('D', width: 34),
                      _key('L', width: 34),
                      _key('Z', width: 34),
                      const Spacer(),
                      _key('↑', width: 40),
                    ],
                  ),
                  Row(
                    children: [
                      _key('Home', width: 48),
                      _key('End', width: 44),
                      _key('PgUp', width: 48),
                      _key('PgDn', width: 48),
                      const Spacer(),
                      _key('←', width: 40),
                      _key('↓', width: 40),
                      _key('→', width: 40),
                    ],
                  ),
                ],
              ),
            ),
            // input
            Container(
              color: _panel,
              padding: EdgeInsets.only(
                left: 8,
                right: 4,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom + 6,
              ),
              child: Row(
                children: [
                  const Text('❯ ', style: TextStyle(color: _green, fontFamily: 'monospace', fontSize: 14)),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: _connected,
                      style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13.5),
                      cursorColor: _green,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输入后回车发送到远程 shell',
                        hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _connected ? _submit : null,
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
