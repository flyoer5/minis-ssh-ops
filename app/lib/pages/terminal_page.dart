import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Interactive PTY terminal. Keys send raw bytes immediately (SSH client style).
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  String _status = '';
  bool _ctrl = false;

  static const _bg = Color(0xFF000000);
  static const _panel = Color(0xFF1C1C1E);
  static const _fg = Color(0xFFE5E5EA);
  static const _green = Color(0xFF30D158);
  static const _muted = Color(0xFF8E8E93);
  static const _key = Color(0xFF2C2C2E);

  @override
  void dispose() {
    _sub?.cancel();
    _ch?.sink.close();
    _scroll.dispose();
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
    if (t.length > 120000) {
      _buf
        ..clear()
        ..write(t.substring(t.length - 60000));
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
    if (hostId == null) return;
    await _teardown();
    setState(() {
      _connecting = true;
      _connected = false;
      _status = '连接中';
      _buf.clear();
    });

    final uri = Uri.parse(state.api.baseUrl);
    final wsUri = Uri(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      host: uri.host.isEmpty ? '127.0.0.1' : uri.host,
      port: uri.hasPort ? uri.port : 17890,
      path: '/v1/pty',
      queryParameters: {
        'token': state.api.localToken,
        'hostId': hostId,
        'cols': '100',
        'rows': '28',
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
                setState(() {
                  _connected = false;
                  _status = '断开';
                });
              }
            } catch (_) {
              _append(_stripAnsi(event));
            }
          } else if (event is List<int>) {
            _append(_stripAnsi(utf8.decode(event, allowMalformed: true)));
          } else if (event is Uint8List) {
            _append(_stripAnsi(utf8.decode(event, allowMalformed: true)));
          } else if (event is ByteBuffer) {
            _append(_stripAnsi(utf8.decode(event.asUint8List(), allowMalformed: true)));
          }
        },
        onError: (e) {
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '错误';
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '断开';
          });
        },
      );
      Future.delayed(const Duration(milliseconds: 500), () {
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
        _status = '失败';
      });
      _append('$e\n');
    }
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }

  void _send(String data) {
    final ch = _ch;
    if (ch == null) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_connected || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (HardwareKeyboard.instance.isControlPressed || _ctrl) {
      final label = key.keyLabel;
      if (label.length == 1) {
        final c = label.toUpperCase().codeUnitAt(0);
        if (c >= 65 && c <= 90) {
          _send(String.fromCharCode(c - 64));
          if (_ctrl) setState(() => _ctrl = false);
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _send('\r');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _send('\x7f');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _send('\t');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _send('\x1b');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _send('\x1b[A');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _send('\x1b[B');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _send('\x1b[C');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _send('\x1b[D');
      return KeyEventResult.handled;
    }

    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      _send(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _extra(String name) {
    if (!_connected) return;
    switch (name) {
      case 'TAB':
        _send('\t');
      case 'ESC':
        _send('\x1b');
      case 'CTRL':
        setState(() => _ctrl = !_ctrl);
      case 'C':
        _send(_ctrl ? '\x03' : 'c');
        if (_ctrl) setState(() => _ctrl = false);
      case 'D':
        _send(_ctrl ? '\x04' : 'd');
        if (_ctrl) setState(() => _ctrl = false);
      case 'L':
        _send(_ctrl ? '\x0c' : 'l');
        if (_ctrl) setState(() => _ctrl = false);
      case 'Z':
        _send(_ctrl ? '\x1a' : 'z');
        if (_ctrl) setState(() => _ctrl = false);
      case '↑':
        _send('\x1b[A');
      case '↓':
        _send('\x1b[B');
      case '←':
        _send('\x1b[D');
      case '→':
        _send('\x1b[C');
      case '⌫':
        _send('\x7f');
      case '↵':
        _send('\r');
    }
  }

  Widget _kb(String label, {bool highlight = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          height: 40,
          child: Material(
            color: highlight ? const Color(0xFF3A3A3C) : _key,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _extra(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: highlight ? _green : _fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
    final ready = state.backendOk && state.selectedHostId != null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 42,
              color: _panel,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: _connected ? _green : (_connecting ? Colors.amber : Colors.redAccent)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.selectedHostId == null ? '终端' : state.hostLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(_status, style: const TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: ready ? () => _connect(state) : null,
                    icon: const Icon(Icons.refresh, color: _muted, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _buf.clear()),
                    icon: const Icon(Icons.cleaning_services_outlined, color: _muted, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: _onKey,
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
                        _buf.isEmpty ? (ready ? '' : '选择主机后自动连接\n') : _buf.toString(),
                        style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13, height: 1.3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // virtual extras — compact, fixed layout, no Spacer chaos
            Container(
              color: _panel,
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Column(
                children: [
                  Row(children: [
                    _kb('ESC'),
                    _kb('TAB'),
                    _kb('CTRL', highlight: _ctrl),
                    _kb('C'),
                    _kb('D'),
                    _kb('L'),
                    _kb('Z'),
                  ]),
                  Row(children: [
                    _kb('↑'),
                    _kb('↓'),
                    _kb('←'),
                    _kb('→'),
                    _kb('⌫'),
                    _kb('↵'),
                  ]),
                ],
              ),
            ),
            // soft hint: type with system keyboard; characters go to PTY via Focus
            Container(
              width: double.infinity,
              color: _panel,
              padding: EdgeInsets.only(left: 12, right: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 8, top: 4),
              child: Text(
                _connected ? '点屏幕后用系统键盘输入；上方为特殊键' : '未连接',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
