import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/pages/ansi_text.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'terminal_page_scrollback.dart';
part 'terminal_page_input.dart';
part 'terminal_page_widgets.dart';

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
  String? _spanCacheRaw;
  double? _spanCacheFont;
  TextSpan? _spanCache;
  Timer? _searchDebounce;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _hostId != null &&
        !_connected &&
        !_connecting &&
        mounted) {
      final app = context.read<AppState>();
      if (app.backendOk && app.selectedHostId == _hostId) {
        _append('\r\n\x1B[90m[app] resumed, reconnecting...\x1B[0m\r\n');
        _connect(app);
      }
    }
  }

  void _append(String s) {
    _buf.write(s);
    final t = _buf.toString();
    if (t.length > 400000) {
      _buf
        ..clear()
        ..write(t.substring(t.length - 200000));
    }
    if (!mounted) return;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels < 160) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  Future<void> _connect(AppState state) async {
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
      _status = '连接中...';
      _buf.clear();
    });
    final hostId = state.selectedHostId;
    if (hostId == null) {
      setState(() {
        _connecting = false;
        _status = '未选择主机';
      });
      return;
    }
    final base = Uri.parse(state.api.baseUrl);
    late final String ticket;
    try {
      ticket = await state.api.createPtyTicket(hostId).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (gen != _connGen || !mounted) return;
      setState(() {
        _connecting = false;
        _status = '终端授权失败';
      });
      _append('\n终端授权失败：$e\n');
      return;
    }
    if (gen != _connGen || !mounted) return;
    final ws = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host.isEmpty ? '127.0.0.1' : base.host,
      port: base.hasPort ? base.port : 17890,
      path: '/v1/pty',
      queryParameters: {
        'ticket': ticket,
        'hostId': hostId,
        'cols': '80',
        'rows': '28',
      },
    );
    try {
      final ch = IOWebSocketChannel.connect(
        ws,
        pingInterval: const Duration(seconds: 25),
        connectTimeout: const Duration(seconds: 15),
      );
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
                  _status = '已连接，点击屏幕输入';
                });
              } else if (t == 'error') {
                _append('\n${m['data']}\n');
              } else if (t == 'exit') {
                setState(() {
                  _connected = false;
                  _connecting = false;
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
        _buf.clear();
        _spanCache = null;
        _spanCacheRaw = null;
        _hostId = connectId;
        _connect(state);
      });
    }
    if (hostId == null) {
      return _buildEmptyState(context);
    }

    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false,
      body: TopSafePad(
        child: Column(
          children: [
            _buildTopBar(context, state, hostLabel, fontSize),
            if (_showSearch) _buildSearchBar(),
            _buildConnectionBanner(state),
            _buildTerminalSurface(fontSize),
            _buildKeyBar(),
          ],
        ),
      ),
    );
  }
}
