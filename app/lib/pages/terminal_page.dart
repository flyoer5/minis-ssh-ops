import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Termux/JuiceSSH style PTY terminal.
/// - Tap screen: open system IME
/// - IME hide button / back: system dismiss works (EditableText owns focus)
/// - Extra key bar only; no permanent command box; no copy button
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _input = TextEditingController();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  bool _ctrl = false;
  String _status = '';
  String _prev = '';

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
    _input.addListener(_onChanged);
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_onChanged);
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
    final fontSize = state.termFontSize;
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
    // Strip OSC (] ... BEL/ST), CSI ([ ... letter), charset, and other ESC sequences.
    var t = s
        .replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '')
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'\x1B[()][0-9A-Za-z]'), '')
        .replaceAll(RegExp(r'\x1B.'), '');
    // Normalize newlines; drop CR alone
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '');
    // Drop leftover C0 controls except tab/newline (bell, backspace already handled by server usually)
    final out = StringBuffer();
    for (final cu in t.runes) {
      if (cu == 0x09 || cu == 0x0A) {
        out.writeCharCode(cu);
      } else if (cu < 0x20 || cu == 0x7F) {
        // skip other controls that often render as tofu/box
      } else if (cu == 0xFFFD) {
        // skip replacement character
      } else {
        out.writeCharCode(cu);
      }
    }
    return out.toString();
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

  void _sendResize() {
    final ch = _ch;
    if (ch == null || !_connected) return;
    // approximate cols from width / char width ~ fontSize*0.6
    final mq = MediaQuery.of(context);
    final w = mq.size.width - 16;
    final h = mq.size.height - mq.viewInsets.bottom - 160;
    final fs = context.read<AppState>().termFontSize;
    final cols = (w / (fs * 0.6)).floor().clamp(40, 200);
    final rows = (h / (fs * 1.3)).floor().clamp(10, 80);
    ch.sink.add(jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows}));
  }

  /// Diff EditableText → PTY. System IME owns show/hide.
  void _onChanged() {
    if (!_connected) {
      _prev = _input.text;
      return;
    }
    final cur = _input.text;
    final prev = _prev;
    if (cur == prev) return;
    if (cur.length > prev.length && cur.startsWith(prev)) {
      _send(cur.substring(prev.length).replaceAll('\n', '\r'));
    } else if (cur.length < prev.length && prev.startsWith(cur)) {
      for (var i = 0; i < prev.length - cur.length; i++) {
        _send('\x7f');
      }
    } else {
      for (var i = 0; i < prev.length; i++) {
        _send('\x7f');
      }
      if (cur.isNotEmpty) _send(cur.replaceAll('\n', '\r'));
    }
    if (cur.length > 64) {
      _input.removeListener(_onChanged);
      _input.clear();
      _prev = '';
      _input.addListener(_onChanged);
    } else {
      _prev = cur;
    }
  }

  void _openKb() {
    if (!mounted || !_connected) return;
    FocusScope.of(context).requestFocus(_focus);
    // EditableText will show IME when focused; also nudge Android.
    SystemChannels.textInput.invokeMethod('TextInput.show');
    setState(() {});
  }

  void _closeKb() {
    if (!mounted) return;
    _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() {});
  }

  void _toggleKb() {
    if (_focus.hasFocus) {
      _closeKb();
    } else {
      _openKb();
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
      case '—':
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
    final fontSize = state.termFontSize;
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
                title: Text(
                  state.hostLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(_status, style: const TextStyle(fontSize: 11, color: _muted)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '减小字体',
                      icon: const Icon(Icons.text_decrease, size: 18),
                      onPressed: () => context.read<AppState>().setTermFontSize(state.termFontSize - 1),
                    ),
                    IconButton(
                      tooltip: '增大字体',
                      icon: const Icon(Icons.text_increase, size: 18),
                      onPressed: () => context.read<AppState>().setTermFontSize(state.termFontSize + 1),
                    ),
                    IconButton(
                      tooltip: _focus.hasFocus ? '收起键盘' : '打开键盘',
                      icon: Icon(
                        _focus.hasFocus ? Icons.keyboard_hide : Icons.keyboard,
                        size: 20,
                      ),
                      onPressed: _toggleKb,
                    ),
                    IconButton(
                      tooltip: '粘贴',
                      icon: const Icon(Icons.content_paste, size: 18),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        final text = data?.text;
                        if (text == null || text.isEmpty) return;
                        _send(text.replaceAll('\n', '\r'));
                        _openKb();
                      },
                    ),
                    IconButton(
                      tooltip: '清屏',
                      icon: const Icon(Icons.delete_sweep, size: 20),
                      onPressed: () {
                        setState(() {
                          _buf.clear();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => _connect(state),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // Terminal surface: tap opens IME
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openKb,
                      child: Container(
                        color: _bg,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: Text(
                            _buf.isEmpty
                                ? (_connecting ? 'connecting…\n' : 'tap to type\n')
                                : _buf.toString(),
                            style: TextStyle(
                              color: _fg,
                              fontFamily: 'monospace',
                              fontSize: fontSize,
                              height: 1.28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Off-screen EditableText owns IME so system hide works.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 1,
                    child: Opacity(
                      opacity: 0.01,
                      child: EditableText(
                        controller: _input,
                        focusNode: _focus,
                        style: const TextStyle(color: Colors.transparent, fontSize: 1),
                        cursorColor: Colors.transparent,
                        backgroundCursorColor: Colors.transparent,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.newline,
                        autofocus: false,
                        enableSuggestions: false,
                        autocorrect: false,
                        onSubmitted: (_) {
                          _send('\r');
                          _input.clear();
                          _prev = '';
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    _k('—'),
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
