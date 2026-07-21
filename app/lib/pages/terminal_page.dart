import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Terminal page — look & feel of common mobile SSH clients.
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

  static const _bg = Color(0xFF0C0C0C);
  static const _fg = Color(0xFFD4D4D4);
  static const _green = Color(0xFF4EC9B0);
  static const _dim = Color(0xFF6A9955);
  static const _bar = Color(0xFF1E1E1E);
  static const _amber = Color(0xFFDCDCAA);
  static const _red = Color(0xFFF44747);

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

  Future<void> _run(AppState state, {bool forceConfirm = false}) async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;
    if (!state.backendOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('后端未连接')));
      return;
    }
    if (state.selectedHostId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择主机')));
      return;
    }

    // local helpers
    if (cmd == 'clear' || cmd == 'cls') {
      state.clearTerminal();
      _input.clear();
      return;
    }

    setState(() => _busy = true);
    try {
      await state.runTerminal(cmd, confirmed: forceConfirm);
      _input.clear();
      _histIdx = -1;
      _scrollEnd();
    } on ApiException catch (e) {
      if (e.status == 409) {
        final risk = e.body?['risk']?.toString() ?? 'write';
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: _bar,
            title: Text('需要确认 ($risk)', style: const TextStyle(color: _fg)),
            content: Text(
              '命令可能修改系统：\n\n$cmd\n\n是否确认执行？',
              style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('确认执行'),
              ),
            ],
          ),
        );
        if (ok == true) {
          try {
            await state.runTerminal(cmd, confirmed: true);
            _input.clear();
            _histIdx = -1;
            _scrollEnd();
          } catch (e2) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e2')));
            }
          }
        } else {
          state.appendTerminal('^C  (已取消确认)\n', dim: true);
        }
      } else if (e.status == 403) {
        state.appendTerminal('blocked: ${e.message}\n', error: true);
        _scrollEnd();
      } else {
        state.appendTerminal('error: $e\n', error: true);
        _scrollEnd();
      }
    } catch (e) {
      state.appendTerminal('error: $e\n', error: true);
      _scrollEnd();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  void _history(AppState state, int delta) {
    final h = state.terminalHistory;
    if (h.isEmpty) return;
    var i = _histIdx;
    if (i < 0) i = h.length;
    i += delta;
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prompt = state.terminalPrompt;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // title bar like JuiceSSH / Termius compact
            Container(
              color: _bar,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: _green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('终端', style: TextStyle(color: _fg, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                          state.hostLabel,
                          style: const TextStyle(color: Color(0xFF858585), fontSize: 11, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '清屏',
                    onPressed: () => state.clearTerminal(),
                    icon: const Icon(Icons.cleaning_services_outlined, color: Color(0xFF858585), size: 18),
                  ),
                  IconButton(
                    tooltip: '复制全部',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: state.terminalBuffer));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制终端输出'), duration: Duration(seconds: 1)),
                      );
                    },
                    icon: const Icon(Icons.copy, color: Color(0xFF858585), size: 18),
                  ),
                ],
              ),
            ),
            // session strip
            Container(
              width: double.infinity,
              color: const Color(0xFF252526),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                state.backendOk
                    ? (state.selectedHostId == null ? '未选择主机 — 请到「主机」页选择' : 'connected · risk gate on · type clear to reset')
                    : 'backend offline',
                style: TextStyle(
                  color: state.backendOk && state.selectedHostId != null ? _dim : _red,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // scrollback
            Expanded(
              child: GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Container(
                  width: double.infinity,
                  color: _bg,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      state.terminalBuffer.isEmpty
                          ? 'SSH session ready.\nSelect a host, then type a command.\n'
                          : state.terminalBuffer,
                      style: const TextStyle(
                        color: _fg,
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // input line
            Container(
              color: _bar,
              padding: EdgeInsets.only(
                left: 8,
                right: 6,
                top: 6,
                bottom: 6 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Row(
                children: [
                  Text(
                    prompt,
                    style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 12.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (e) {
                        if (e is! KeyDownEvent) return;
                        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _history(state, -1);
                        } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _history(state, 1);
                        }
                      },
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        style: const TextStyle(color: _fg, fontFamily: 'monospace', fontSize: 13),
                        cursorColor: _green,
                        enabled: state.backendOk && state.selectedHostId != null && !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _run(state),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'command…',
                          hintStyle: TextStyle(color: Color(0xFF555555), fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                    )
                  else
                    IconButton(
                      onPressed: () => _run(state),
                      icon: const Icon(Icons.keyboard_return, color: _green, size: 20),
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
