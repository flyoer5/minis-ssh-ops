import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Termux/JuiceSSH style terminal:
/// - Full-screen scrollback (tap opens system keyboard)
/// - No permanent text box
/// - Extra key bar only
/// - KeepAlive so tab switch does not drop session
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin
    implements TextInputClient {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  bool _ctrl = false;
  String _status = '';
  TextInputConnection? _conn;
  TextEditingValue _value = TextEditingValue.empty;

  static const _bg = Color(0xFF000000);
  static const _fg = Color(0xFFE6EDF3);
  static const _green = Color(0xFF3FB950);
  static const _muted = Color(0xFF8B949E);
  static const _keyBg = Color(0xFF21262D);
  static const _bar = Color(0xFF0D1117);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _attachIme();
      } else {
        _detachIme();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachIme();
    _sub?.cancel();
    _ch?.sink.close();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (_connected && _focus.hasFocus) _attachIme();
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

  void _connect(AppState state) {
    _sub?.cancel();
    _ch?.sink.close();
    setState(() {
      _connecting = true;
      _connected = false;
      _status = '连接中…';
      _buf.clear();
    });

    final base = Uri.parse(state.api.baseUrl);
    final ws = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host.isEmpty ? '127.0.0.1' : base.host,
      port: base.hasPort ? base.port : 17890,
      path: '/v1/pty',
      queryParameters: {
        'token': state.api.localToken,
        'hostId': state.selectedHostId!,
        'cols': '80',
        'rows': '28',
      },
    );

    try {
      final ch = IOWebSocketChannel.connect(ws);
      _ch = ch;
      _sub = ch.stream.listen(
        (data) {
          if (data is String) {
            try {
              final m = jsonDecode(data) as Map<String, dynamic>;
              final t = m['type']?.toString();
              if (t == 'ready') {
                setState(() {
                  _connected = true;
                  _connecting = false;
                  _status = '已连接 · 点屏幕输入';
                });
                _openKb();
              } else if (t == 'error') {
                _append('\n${m['data']}\n');
              } else if (t == 'exit') {
                setState(() {
                  _connected = false;
                  _status = '已断开';
                });
                _append('\n[closed]\n');
              }
            } catch (_) {
              _append(_stripAnsi(data));
            }
          } else if (data is List<int>) {
            _append(_stripAnsi(utf8.decode(data, allowMalformed: true)));
          } else if (data is ByteBuffer) {
            _append(_stripAnsi(utf8.decode(data.asUint8List(), allowMalformed: true)));
          }
        },
        onError: (e) {
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '错误';
          });
          _append('\n$e\n');
        },
        onDone: () {
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '已断开';
          });
        },
      );
    } catch (e) {
      setState(() {
        _connecting = false;
        _status = '连接失败';
      });
      _append('$e\n');
    }
  }

  void _send(String data) {
    final ch = _ch;
    if (ch == null || !_connected) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  void _openKb() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_focus);
    _attachIme();
  }

  void _attachIme() {
    if (_conn == null || !(_conn?.attached ?? false)) {
      _conn = TextInput.attach(
        this,
        const TextInputConfiguration(
          inputType: TextInputType.text,
          obscureText: false,
          autocorrect: false,
          enableSuggestions: false,
          inputAction: TextInputAction.newline,
          keyboardAppearance: Brightness.dark,
        ),
      );
    }
    _conn?.setEditingState(_value);
    _conn?.show();
  }

  void _detachIme() {
    _conn?.close();
    _conn = null;
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final old = _value.text;
    final cur = value.text;
    _value = value;
    if (!_connected) return;
    if (cur == old) return;
    if (cur.length > old.length && cur.startsWith(old)) {
      _send(cur.substring(old.length).replaceAll('\n', '\r'));
    } else if (cur.length < old.length && old.startsWith(cur)) {
      for (var i = 0; i < old.length - cur.length; i++) {
        _send('\x7f');
      }
    } else {
      for (var i = 0; i < old.length; i++) {
        _send('\x7f');
      }
      if (cur.isNotEmpty) _send(cur.replaceAll('\n', '\r'));
    }
    if (cur.length > 80) {
      _value = TextEditingValue.empty;
      _conn?.setEditingState(_value);
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline ||
        action == TextInputAction.send ||
        action == TextInputAction.done) {
      _send('\r');
      _value = TextEditingValue.empty;
      _conn?.setEditingState(_value);
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _conn = null;
  }

  @override
  bool onFocusReceived() => false;

  @override
  void performSelector(String selectorName) {}


  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}

  @override
  void insertContent(KeyboardInsertedContent content) {
    final d = content.data;
    if (d != null && d.isNotEmpty) {
      _send(String.fromCharCodes(d));
    }
  }

  void _extra(String name) {
    switch (name) {
      case 'ESC':
        _send('\x1b');
        break;
      case 'TAB':
        _send('\t');
        break;
      case 'CTRL':
        setState(() => _ctrl = !_ctrl);
        return;
      case 'C':
        _send(_ctrl ? '\x03' : 'c');
        if (_ctrl) setState(() => _ctrl = false);
        break;
      case 'D':
        _send(_ctrl ? '\x04' : 'd');
        if (_ctrl) setState(() => _ctrl = false);
        break;
      case 'L':
        _send(_ctrl ? '\x0c' : 'l');
        if (_ctrl) setState(() => _ctrl = false);
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
      case '-':
        _send('-');
        break;
      case '/':
        _send('/');
        break;
      case '|':
        _send('|');
        break;
      case '~':
        _send('~');
        break;
      case 'BS':
        _send('\x7f');
        break;
      case 'ENT':
        _send('\r');
        break;
    }
    _openKb();
  }

  Widget _k(String label, {bool on = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox(
          height: 36,
          child: Material(
            color: on ? const Color(0xFF30363D) : _keyBg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _extra(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(color: on ? _green : _fg, fontSize: 12, fontWeight: FontWeight.w600),
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
    super.build(context);
    final state = context.watch<AppState>();
    if (state.selectedHostId == null) {
      return const Scaffold(body: Center(child: Text('先选主机')));
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: _bar,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 10, color: _connected ? _green : Colors.redAccent),
                title: Text(state.hostLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                subtitle: Text(_status, style: const TextStyle(fontSize: 11, color: _muted)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.keyboard, size: 20), onPressed: _openKb),
                    IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => _connect(state)),
                    IconButton(
                      icon: const Icon(Icons.copy_all, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _buf.toString()));
                      },
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openKb,
                child: Container(
                  width: double.infinity,
                  color: _bg,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _buf.isEmpty ? (_connecting ? 'connecting…\n' : 'tap screen for keyboard\n') : _buf.toString(),
                      style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13, height: 1.28),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 1, height: 1, child: Focus(focusNode: _focus, child: const SizedBox.shrink())),
            Container(
              color: _bar,
              padding: EdgeInsets.only(
                left: 4,
                right: 4,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 4 : 6,
              ),
              child: Column(
                children: [
                  Row(children: [
                    _k('ESC'),
                    _k('TAB'),
                    _k('CTRL', on: _ctrl),
                    _k('C'),
                    _k('D'),
                    _k('L'),
                    _k('-'),
                    _k('/'),
                    _k('|'),
                  ]),
                  Row(children: [
                    _k('↑'),
                    _k('↓'),
                    _k('←'),
                    _k('→'),
                    _k('~'),
                    _k('BS'),
                    _k('ENT'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
