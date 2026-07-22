import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// PTY terminal: system soft keyboard via TextField (JuiceSSH-style) + compact extra bar.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  String _status = '';
  bool _ctrl = false;
  String _prevInput = '';

  static const _bg = Color(0xFF000000);
  static const _panel = Color(0xFF1C1C1E);
  static const _fg = Color(0xFFE5E5EA);
  static const _green = Color(0xFF30D158);
  static const _muted = Color(0xFF8E8E93);
  static const _key = Color(0xFF2C2C2E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_onInputChanged);
    _sub?.cancel();
    _ch?.sink.close();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // keep focus when keyboard opens/closes
    if (_connected && mounted) {
      _focus.requestFocus();
    }
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
      _prevInput = '';
      _input.clear();
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
                _openKeyboard();
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
        onError: (_) {
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
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _connecting) {
          setState(() {
            _connecting = false;
            _connected = true;
            _status = '已连接';
          });
          _openKeyboard();
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
    if (ch == null || !_connected) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  void _openKeyboard() {
    if (!mounted) return;
    _focus.requestFocus();
    // Force soft keyboard on Android
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  /// Diff TextField content → PTY keystrokes (JuiceSSH-like).
  void _onInputChanged() {
    if (!_connected) {
      _prevInput = _input.text;
      return;
    }
    final cur = _input.text;
    final prev = _prevInput;

    if (cur == prev) return;

    if (cur.length > prev.length && cur.startsWith(prev)) {
      final added = cur.substring(prev.length);
      // Map newline from IME to CR for shells
      _send(added.replaceAll('\n', '\r'));
    } else if (cur.length < prev.length && prev.startsWith(cur)) {
      final n = prev.length - cur.length;
      for (var i = 0; i < n; i++) {
        _send('\x7f');
      }
    } else {
      // complex edit: send backspaces then new text
      for (var i = 0; i < prev.length; i++) {
        _send('\x7f');
      }
      if (cur.isNotEmpty) {
        _send(cur.replaceAll('\n', '\r'));
      }
    }

    // Keep field short so IME stays light
    if (cur.length > 200) {
      _input.removeListener(_onInputChanged);
      _input.clear();
      _prevInput = '';
      _input.addListener(_onInputChanged);
    } else {
      _prevInput = cur;
    }
  }

  void _extra(String name) {
    if (!_connected) return;
    switch (name) {
      case 'TAB':
        _send('\t');
        break;
      case 'ESC':
        _send('\x1b');
        break;
      case 'CTRL':
        setState(() => _ctrl = !_ctrl);
        break;
      case 'Ctrl-C':
        _send('\x03');
        setState(() => _ctrl = false);
        break;
      case 'Ctrl-D':
        _send('\x04');
        setState(() => _ctrl = false);
        break;
      case 'Ctrl-L':
        _send('\x0c');
        setState(() => _ctrl = false);
        break;
      case 'Ctrl-Z':
        _send('\x1a');
        setState(() => _ctrl = false);
        break;
      case '↑':
        _send('\x1b[A');
        break;
      case '↓':
        _send('\x1b[B');
        break;
      case '←':
        _send('\x1b[D');
        break;
      case '→':
        _send('\x1b[C');
        break;
      case 'Home':
        _send('\x1b[H');
        break;
      case 'End':
        _send('\x1b[F');
        break;
      case '⌫':
        _send('\x7f');
        break;
      case '↵':
        _send('\r');
        break;
      default:
        if (_ctrl && name.length == 1) {
          final c = name.toUpperCase().codeUnitAt(0);
          if (c >= 65 && c <= 90) {
            _send(String.fromCharCode(c - 64));
            setState(() => _ctrl = false);
          }
        }
    }
    _openKeyboard();
  }

  Widget _key(String label, {bool on = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: SizedBox(
          height: 38,
          child: Material(
            color: on ? const Color(0xFF3A3A3C) : _key,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _extra(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: on ? _green : _fg,
                    fontSize: 12,
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 42,
              color: _panel,
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: ready ? () => _connect(state) : null,
                    icon: const Icon(Icons.refresh, color: _muted, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() => _buf.clear());
                      _openKeyboard();
                    },
                    icon: const Icon(Icons.cleaning_services_outlined, color: _muted, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
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
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openKeyboard,
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
            // special keys
            Container(
              color: _panel,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Column(
                children: [
                  Row(children: [
                    _key('ESC'),
                    _key('TAB'),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: SizedBox(
                          height: 38,
                          child: Material(
                            color: _ctrl ? const Color(0xFF3A3A3C) : _key,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _extra('CTRL'),
                              child: Center(
                                child: Text(
                                  'CTRL',
                                  style: TextStyle(
                                    color: _ctrl ? _green : _fg,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _key('Ctrl-C'),
                    _key('Ctrl-D'),
                    _key('Ctrl-L'),
                  ]),
                  Row(children: [
                    _key('↑'),
                    _key('↓'),
                    _key('←'),
                    _key('→'),
                    _key('Home'),
                    _key('End'),
                    _key('⌫'),
                    _key('↵'),
                  ]),
                ],
              ),
            ),
            // system keyboard host — always present so IME can attach
            Container(
              color: _panel,
              padding: EdgeInsets.only(
                left: 10,
                right: 8,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 4 : 8,
              ),
              child: Row(
                children: [
                  const Text('❯ ', style: TextStyle(color: _green, fontFamily: 'monospace')),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: _connected,
                      autofocus: false,
                      keyboardType: TextInputType.visiblePassword, // avoid suggestions lag
                      textInputAction: TextInputAction.newline,
                      enableSuggestions: false,
                      autocorrect: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 14),
                      cursorColor: _green,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '点此输入',
                        hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 13),
                      ),
                      onTap: _openKeyboard,
                      onSubmitted: (_) {
                        // some IMEs send submit instead of newline char
                        _send('\r');
                        _input.clear();
                        _prevInput = '';
                      },
                    ),
                  ),
                  if (_ctrl)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('CTRL', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.bold)),
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
