#!/usr/bin/env python3
"""Re-apply frontend post-1.4.7 changes."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def must(path, old, new, label):
    p = ROOT / path
    t = p.read_text()
    if old not in t:
        print(f"FAIL {label}")
        print(repr(old[:120]))
        sys.exit(1)
    p.write_text(t.replace(old, new))
    print(f"OK {label}")


def main():
    # ----- pubspec -----
    must(
        "app/pubspec.yaml",
        """version: 1.4.7+39
""",
        """version: 1.4.8+40
""",
        "version",
    )
    must(
        "app/pubspec.yaml",
        """  web_socket_channel: ^3.0.1
""",
        """  web_socket_channel: ^3.0.1
  flutter_markdown: ^0.7.7+1
""",
        "flutter_markdown dep",
    )

    # ----- chat_message -----
    must(
        "app/lib/models/chat_message.dart",
        """enum ChatKind {
  text,
  plan,
  stepResult,
  error,
  status,
}
""",
        """enum ChatKind {
  text,
  plan,
  stepResult,
  error,
  status,
  reasoning,
}
""",
        "ChatKind.reasoning",
    )

    # ----- records local time -----
    p = ROOT / "app/lib/pages/records_page.dart"
    t = p.read_text()
    if "_fmtLocal" not in t:
        t = t.replace(
            """class _RecordsPageState extends State<RecordsPage> with AutomaticKeepAliveClientMixin {
  String filter = 'all'; // all|read|write|destructive|blocked

  @override
  bool get wantKeepAlive => true;
""",
            """class _RecordsPageState extends State<RecordsPage> with AutomaticKeepAliveClientMixin {
  String filter = 'all'; // all|read|write|destructive|blocked

  @override
  bool get wantKeepAlive => true;

  /// Backend stores UTC RFC3339; show device local wall clock.
  String _fmtLocal(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final dt0 = DateTime.tryParse(s);
    if (dt0 == null) return s;
    final dt = dt0.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
""",
        )
        t = t.replace(
            "final at = e['createdAt']?.toString() ?? '';",
            "final at = _fmtLocal(e['createdAt']?.toString() ?? '');",
        )
        p.write_text(t)
        print("OK records local time")
    else:
        print("OK records already")

    print("frontend part1 done")


if __name__ == "__main__":
    main()
