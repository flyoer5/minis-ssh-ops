part of 'terminal_page.dart';

extension _TerminalPageScrollback on _TerminalPageState {
  String get _plainScrollback => stripAnsi(_buf.toString());

  /// Prefer ANSI coloring; when searching, fall back to plain text with
  /// highlighted hits.
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
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.25,
      color: AppColors.text,
    );
    final hit = base.copyWith(backgroundColor: const Color(0x66D29922), color: Colors.white);
    final active = base.copyWith(
      backgroundColor: const Color(0xAAD29922),
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    for (var i = 0; i < _searchHits.length; i++) {
      final start = _searchHits[i];
      if (start < cursor) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: plain.substring(cursor, start), style: base));
      }
      final end = (start + q.length).clamp(0, plain.length);
      spans.add(TextSpan(text: plain.substring(start, end), style: i == _searchIdx ? active : hit));
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
      _searchIdx = 0;
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
}
