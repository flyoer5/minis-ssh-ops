part of 'terminal_page.dart';

extension _TerminalPageInput on _TerminalPageState {
  void _send(String data) {
    final ch = _ch;
    if (ch == null || !_connected) return;
    ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  /// Diff EditableText -> PTY. System IME owns show/hide.
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
      case 'UP':
        _send('\x1b[A');
        break;
      case 'DOWN':
        _send('\x1b[B');
        break;
      case 'LEFT':
        _send('\x1b[D');
        break;
      case 'RIGHT':
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
                  style: TextStyle(
                    color: on ? _green : AppColors.text,
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

  Widget _buildKeyBar() {
    return ImeInset(
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
              _k('-'),
              _k('/'),
              _k('|'),
            ]),
            Row(children: [
              _k('UP'),
              _k('DOWN'),
              _k('LEFT'),
              _k('RIGHT'),
              _k('~'),
              _k('BS'),
              _k('ENT'),
            ]),
          ],
        ),
      ),
    );
  }
}
