import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Plain SSH-tool terminal (JuiceSSH / Termius style).
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _busy = false;
  int _histIdx = -1;

  static const _bg = Color(0xFF000000);
  static const _fg = Color(0xFFE0E0E0);
  static const _green = Color(0xFF00C853);
  static const _muted = Color(0xFF9E9E9E);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _run(AppState state) async {
    final cmd = _input.text;
    final trimmed = cmd.trimRight();
    if (trimmed.isEmpty || _busy) return;

    if (!state.backendOk) {
      _snack('后端未连接');
      return;
    }
    if (state.selectedHostId == null) {
      _snack('请先选择主机');
      return;
    }

    final line = trimmed.trim();
    if (line == 'clear' || line == 'cls') {
      state.clearTerminal();
      _input.clear();
      return;
    }
    if (line == 'exit' || line == 'logout') {
      state.appendTerminal('${state.terminalPrompt}$line\nConnection closed.\n\n');
      _input.clear();
      _scrollEnd();
      return;
    }

    setState(() => _busy = true);
    try {
      await state.runTerminal(line, confirmed: false);
      _input.clear();
      _histIdx = -1;
      _scrollEnd();
    } on ApiException catch (e) {
      if (e.status == 409) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('确认执行'),
            content: Text('该命令可能修改系统：\n\n$line'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('执行')),
            ],
          ),
        );
        if (ok == true) {
          try {
            await state.runTerminal(line, confirmed: true);
            _input.clear();
            _histIdx = -1;
            _scrollEnd();
          } catch (e2) {
            _snack('$e2');
          }
        } else {
          // still show the typed line was cancelled
          state.appendTerminal('${state.terminalPrompt}$line\n');
          state.appendTerminal('(cancelled)\n\n');
          _input.clear();
          _scrollEnd();
        }
      } else if (e.status == 403) {
        state.appendTerminal('${state.terminalPrompt}$line\n');
        state.appendTerminal('bash: $line: Operation not permitted\n\n');
        _input.clear();
        _scrollEnd();
      } else {
        state.appendTerminal('${state.terminalPrompt}$line\n');
        state.appendTerminal('$e\n\n');
        _scrollEnd();
      }
    } catch (e) {
      state.appendTerminal('$e\n\n');
      _scrollEnd();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  void _hist(AppState state, int d) {
    final h = state.terminalHistory;
    if (h.isEmpty) return;
    var i = _histIdx < 0 ? h.length : _histIdx;
    i += d;
    if (i < 0) i = 0;
    if (i >= h.length) {
      _histIdx = -1;
      _input.clear();
      return;
    }
    _histIdx = i;
    _input.text = h[i];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  void _snack(String s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.backendOk && state.selectedHostId != null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // session bar
            Material(
              color: const Color(0xFF121212),
              child: ListTile(
                dense: true,
                leading: Icon(
                  connected ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: connected ? _green : Colors.redAccent,
                ),
                title: Text(
                  state.selectedHostId == null ? '终端' : state.hostLabel,
                  style: const TextStyle(color: _fg, fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  connected ? 'SSH' : (state.backendOk ? '未选择主机' : '未连接'),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '清屏',
                      onPressed: () => state.clearTerminal(),
                      icon: const Icon(Icons.backspace_outlined, color: _muted, size: 18),
                    ),
                    IconButton(
                      tooltip: '复制',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: state.terminalBuffer));
                        _snack('已复制');
                      },
                      icon: const Icon(Icons.copy, color: _muted, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            // screen
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
                      state.terminalBuffer.isEmpty
                          ? (connected
                              ? 'Connected to ${state.hostLabel}.\n'
                              : 'Select a host on 主机 tab, then type commands here.\n')
                          : state.terminalBuffer,
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
            // input — single line like real ssh apps
            Container(
              color: const Color(0xFF121212),
              padding: EdgeInsets.only(
                left: 8,
                right: 4,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom + 4,
              ),
              child: Row(
                children: [
                  Text(
                    connected ? state.terminalPrompt : '> ',
                    style: TextStyle(
                      color: connected ? _green : _muted,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: connected && !_busy,
                      style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13),
                      cursorColor: _green,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _run(state),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      // capture up/down if possible via shortcuts
                      onTap: () => _focus.requestFocus(),
                    ),
                  ),
                  // history buttons for mobile (no physical arrows)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: connected ? () => _hist(state, -1) : null,
                    icon: const Icon(Icons.keyboard_arrow_up, color: _muted, size: 20),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: connected ? () => _hist(state, 1) : null,
                    icon: const Icon(Icons.keyboard_arrow_down, color: _muted, size: 20),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                      ),
                    )
                  else
                    IconButton(
                      onPressed: connected ? () => _run(state) : null,
                      icon: Icon(Icons.keyboard_return, color: connected ? _green : _muted, size: 20),
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
