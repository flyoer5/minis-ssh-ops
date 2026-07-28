import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';

import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/pages/ansi_text.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
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
  final _searchCtrl = TextEditingController();
  final _buf = StringBuffer();
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  String? _hostId;
  bool _connected = false;
  bool _connecting = false;
  int _connGen = 0;
  bool _ctrl = false;
  bool _showSearch = false;
  String _status = '';
  String _prev = '';
  int _searchIdx = 0;
  List<int> _searchHits = [];
  // Memoized non-search scrollback span: the 400KB ANSI parse is the hot cost
  // on every paint, so cache by exact buffer content + font size and rebuild
  // only when either changes.
  String? _spanCacheRaw;
  double? _spanCacheFont;
  TextSpan? _spanCache;
  // Debounce scrollback search so each keystroke doesn't rescan 400KB.
  Timer? _searchDebounce;
  // Batched repaint: high-frequency PTY chunks coalesce into one setState per
  // frame-ish window instead of a full scrollback rebuild per chunk.
  Timer? _appendFlush;
  bool _appendPending = false;

  static const _bg = AppColors.terminalBlack;
  static const _green = AppColors.success;
  static const _keyBg = AppColors.surface2;
  static const _bar = AppColors.bg;

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
    _appendFlush?.cancel();
    _searchDebounce?.cancel();
    _input.removeListener(_onChanged);
    _sub?.cancel();
    _ch?.sink.close();
    _scroll.dispose();
    _input.dispose();
    _searchCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Host reconnect is handled in build() via select + post-frame (select not allowed here).
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After backgrounding, WS often dies silently — auto-reconnect on resume.
    if (state == AppLifecycleState.resumed &&
        _hostId != null &&
        !_connected &&
        !_connecting &&
        mounted) {
      final app = context.read<AppState>();
      if (app.backendOk && app.selectedHostId == _hostId) {
        _append('\r\n\x1B[90m[app] resumed — reconnecting…\x1B[0m\r\n');
        _connect(app);
      }
    }
  }

  void _append(String s) {
    // Keep SGR color sequences; drop only pure noise later in AnsiPainter.
    _buf.write(s);
    final t = _buf.toString();
    // ~400KB raw scrollback (~keep last 200KB when overflow)
    if (t.length > 400000) {
      // trim raw buffer (may cut mid-sequence occasionally; acceptable for scrollback)
      _buf
        ..clear()
        ..write(t.substring(t.length - 200000));
    }
    if (!mounted) return;
    // Coalesce bursts: rebuild scrollback at most ~12x/sec, not per chunk.
    if (_appendFlush?.isActive == true) {
      _appendPending = true;
      return;
    }
    _appendFlush = Timer(const Duration(milliseconds: 80), _flushAppend);
    _doAppendPaint();
  }

  void _flushAppend() {
    _appendFlush = null;
    if (!_appendPending) return;
    _appendPending = false;
    _doAppendPaint();
  }

  void _doAppendPaint() {
    if (!mounted) return;
    setState(() {});
    // Throttled follow: only jump when user is near the bottom so a scroll-up
    // to read history isn't yanked back by incoming output.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels < 160) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  void _connect(AppState state) {
    final gen = ++_connGen;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connected = false;
      _status = '连接中…';
      _buf.clear();
    });
    final hostId = state.selectedHostId;
    if (hostId == null) {
      setState(() {
        _connecting = false;
        _status = '未选主机';
      });
      return;
    }
    final base = Uri.parse(state.api.baseUrl);
    final ws = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host.isEmpty ? '127.0.0.1' : base.host,
      port: base.hasPort ? base.port : 17890,
      path: '/v1/pty',
      queryParameters: {
        'token': state.api.localToken,
        'hostId': hostId,
        'cols': '80',
        'rows': '28',
      },
    );
    try {
      final ch = IOWebSocketChannel.connect(ws);
      if (gen != _connGen) {
        ch.sink.close();
        return;
      }
      _ch = ch;
      _sub = ch.stream.listen(
        (data) {
          if (gen != _connGen || !mounted) return;
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
              _append(data);
            }
          } else if (data is List<int>) {
            _append(utf8.decode(data, allowMalformed: true));
          } else if (data is ByteBuffer) {
            _append(utf8.decode(data.asUint8List(), allowMalformed: true));
          }
        },
        onError: (e) {
          if (gen != _connGen || !mounted) return;
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '错误';
          });
          _append('\n$e\n');
        },
        onDone: () {
          if (gen != _connGen || !mounted) return;
          setState(() {
            _connected = false;
            _connecting = false;
            _status = '已断开';
          });
        },
      );
    } catch (e) {
      if (gen != _connGen || !mounted) return;
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

  String get _plainScrollback => stripAnsi(_buf.toString());

  /// Prefer ANSI coloring; when searching, fall back to plain text with yellow hits.
  TextSpan _buildScrollbackSpan(double fontSize) {
    final raw = _buf.isEmpty ? '' : _buf.toString();
    if (!_showSearch || _searchCtrl.text.trim().isEmpty || _searchHits.isEmpty) {
      if (_spanCache != null && _spanCacheRaw == raw && _spanCacheFont == fontSize) {
        return _spanCache!;
      }
      final span = AnsiPainter(fontSize: fontSize, defaultFg: AppColors.text).build(raw);
      _spanCacheRaw = raw;
      _spanCacheFont = fontSize;
      _spanCache = span;
      return span;
    }
    final plain = _plainScrollback;
    final q = _searchCtrl.text.trim();
    final spans = <TextSpan>[];
    var cursor = 0;
    final base = TextStyle(fontFamily: 'monospace', fontSize: fontSize, height: 1.25, color: AppColors.text);
    final hit = base.copyWith(backgroundColor: const Color(0x66D29922), color: Colors.white);
    final active = base.copyWith(backgroundColor: const Color(0xAAD29922), color: Colors.white, fontWeight: FontWeight.w700);
    for (var i = 0; i < _searchHits.length; i++) {
      final start = _searchHits[i];
      if (start < cursor) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: plain.substring(cursor, start), style: base));
      }
      final end = (start + q.length).clamp(0, plain.length);
      spans.add(TextSpan(
        text: plain.substring(start, end),
        style: i == _searchIdx ? active : hit,
      ));
      cursor = end;
    }
    if (cursor < plain.length) {
      spans.add(TextSpan(text: plain.substring(cursor), style: base));
    }
    return TextSpan(children: spans, style: base);
  }

  void _runSearchDebounced([String? q]) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () => _runSearch(q));
  }

  void _runSearch([String? q]) {
    final query = (q ?? _searchCtrl.text).trim();
    if (query.isEmpty) {
      setState(() {
        _searchHits = [];
        _searchIdx = 0;
      });
      return;
    }
    final plain = _plainScrollback.toLowerCase();
    final needle = query.toLowerCase();
    final hits = <int>[];
    var from = 0;
    while (true) {
      final i = plain.indexOf(needle, from);
      if (i < 0) break;
      hits.add(i);
      from = i + needle.length;
      if (hits.length > 500) break;
    }
    setState(() {
      _searchHits = hits;
      _searchIdx = hits.isEmpty ? 0 : 0;
    });
  }

  void _searchNext({bool reverse = false}) {
    if (_searchHits.isEmpty) {
      _runSearch();
      return;
    }
    setState(() {
      if (reverse) {
        _searchIdx = (_searchIdx - 1) < 0 ? _searchHits.length - 1 : _searchIdx - 1;
      } else {
        _searchIdx = (_searchIdx + 1) % _searchHits.length;
      }
    });
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
            color: on ? AppColors.border : _keyBg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _extra(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(color: on ? _green : AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
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
    final hostId = context.select((AppState s) => s.selectedHostId);
    final fontSize = context.select((AppState s) => s.termFontSize);
    final hostLabel = context.select((AppState s) => s.hostLabel);
    final backendOk = context.select((AppState s) => s.backendOk);
    final state = context.read<AppState>();
    if (hostId != null && hostId != _hostId && backendOk) {
      final connectId = hostId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (connectId != state.selectedHostId) return;
        // Drop previous host's scrollback so output isn't mixed across hosts.
        _buf.clear();
        _spanCache = null;
        _spanCacheRaw = null;
        _hostId = connectId;
        _connect(state);
      });
    }
    if (hostId == null) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          leading: NavMenuButton.leadingOf(context),
          leadingWidth: NavMenuButton.leadingWidthOf(context),
          title: const Text('终端'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.terminal, size: 40, color: AppColors.textFaint),
                const SizedBox(height: 12),
                const Text('先选一台主机', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                const Text(
                  '终端会通过 WebSocket 挂到该主机的交互式 shell。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textFaint, height: 1.4),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => NavScope.maybeOf(context)?.go(0),
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: const Text('去选主机'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Do not freeze whole Scaffold — TextField needs real viewInsets.
    // Freeze only the scrollback Expanded subtree.
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false,
      body: TopSafePad(
        child: Column(
          children: [
            // Single slim bar: menu | ● host · status | A-/A+ | 键盘 | ⋯
            Material(
              color: _bar,
              child: Container(
                height: 36,
                padding: const EdgeInsets.only(left: 0, right: 2),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.surface2)),
                ),
                child: Row(
                  children: [
                    const NavMenuButton(color: AppColors.text),
                    Icon(Icons.circle, size: 8, color: _connected ? AppColors.success : AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: hostLabel,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text),
                            ),
                            if (_status.isNotEmpty)
                              TextSpan(
                                text: '  $_status',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w400),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: '减小字体',
                      icon: const Icon(Icons.text_decrease, size: 16, color: AppColors.textMuted),
                      onPressed: () => context.read<AppState>().setTermFontSize(fontSize - 1),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: '增大字体',
                      icon: const Icon(Icons.text_increase, size: 16, color: AppColors.textMuted),
                      onPressed: () => context.read<AppState>().setTermFontSize(fontSize + 1),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: _focus.hasFocus ? '收起键盘' : '键盘',
                      icon: Icon(
                        _focus.hasFocus ? Icons.keyboard_hide : Icons.keyboard,
                        size: 18,
                        color: _focus.hasFocus ? _green : AppColors.textMuted,
                      ),
                      onPressed: _toggleKb,
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                      color: AppColors.surface,
                      onSelected: (v) async {
                        switch (v) {
                          case 'paste':
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            final text = data?.text;
                            if (text == null || text.isEmpty) return;
                            _send(text.replaceAll('\n', '\r'));
                            _openKb();
                            break;
                          case 'copy_plain':
                            final plain = stripAnsi(_buf.toString());
                            await Clipboard.setData(ClipboardData(text: plain));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制纯文本'), duration: Duration(seconds: 1)),
                              );
                            }
                            break;
                          case 'copy_raw':
                            await Clipboard.setData(ClipboardData(text: _buf.toString()));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制原始输出'), duration: Duration(seconds: 1)),
                              );
                            }
                            break;
                          case 'search':
                            setState(() {
                              _showSearch = !_showSearch;
                              if (!_showSearch) {
                                _searchHits = [];
                                _searchIdx = 0;
                              }
                            });
                            break;
                          case 'clear':
                            setState(() {
                              _buf.clear();
                              _searchHits = [];
                              _searchIdx = 0;
                            });
                            break;
                          case 'reconnect':
                            _connect(state);
                            break;
                        }
                      },

                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'paste', child: Text('粘贴')),
                        const PopupMenuItem(value: 'copy_plain', child: Text('复制纯文本')),
                        const PopupMenuItem(value: 'copy_raw', child: Text('复制原始(含ANSI)')),
                        PopupMenuItem(value: 'search', child: Text(_showSearch ? '关闭搜索' : '搜索回滚')),
                        const PopupMenuItem(value: 'clear', child: Text('清屏')),
                        const PopupMenuItem(value: 'reconnect', child: Text('重连')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_showSearch)
              Material(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '搜索终端输出…',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onChanged: _runSearchDebounced,
                          onSubmitted: (_) => _searchNext(),
                        ),
                      ),
                      Text(
                        _searchHits.isEmpty ? '0' : '${_searchIdx + 1}/${_searchHits.length}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
                      ),
                      IconButton(
                        tooltip: '上一个',
                        visualDensity: VisualDensity.compact,
                        onPressed: _searchHits.isEmpty ? null : () => _searchNext(reverse: true),
                        icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      ),
                      IconButton(
                        tooltip: '下一个',
                        visualDensity: VisualDensity.compact,
                        onPressed: _searchHits.isEmpty ? null : () => _searchNext(),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _showSearch = false;
                          _searchHits = [];
                          _searchIdx = 0;
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            if (_connecting && _hostId != null)
              Material(
                color: AppColors.accent.withAlpha(0x28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentSoft),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status.isEmpty ? '连接中…' : _status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.accentSoft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_connected && !_connecting && _hostId != null)
              Material(
                color: AppColors.warning.withAlpha(0x33),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.link_off, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status.isEmpty ? '未连接' : _status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.warning),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.warning,
                        ),
                        onPressed: () => _connect(state),
                        child: const Text('重连', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: WithoutViewInsets(
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
                          child: SelectableText.rich(
                            _buildScrollbackSpan(fontSize),
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
              ), // Stack
              ), // WithoutViewInsets
            ), // Expanded
            ImeInset(
              usePadding: false,
              reservedBottom: kBottomNavigationBarHeight,
              fillColor: _bar,
              child: Container(
                color: _bar,
                padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 6),
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
            ),
          ],
        ), // Column
      ), // TopSafePad
    ); // Scaffold
  }
}
