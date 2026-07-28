/// Pure helpers for coalescing streamed vs final reasoning text.
/// Stream tokens sometimes lose spaces; final often has proper spacing.
/// Those must stay ONE thought, not two paragraphs.

library;

String compactReason(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

String normReason(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// True if [a] and [b] are the same thought ignoring whitespace differences,
/// or one is a prefix/substring of the other (stream draft vs full final).
bool isSameOrSubReason(String a, String b) {
  final ca = compactReason(a);
  final cb = compactReason(b);
  if (ca.isEmpty || cb.isEmpty) return false;
  if (ca == cb) return true;
  if (cb.startsWith(ca) || ca.startsWith(cb)) return true;
  if (cb.contains(ca) || ca.contains(cb)) return true;
  return false;
}

/// Prefer the more readable of two equivalent reasonings.
/// If they are different thoughts, join with a blank line.
String preferReasoning(String a, String b) {
  final ca = compactReason(a);
  final cb = compactReason(b);
  if (ca.isEmpty) return b.trim();
  if (cb.isEmpty) return a.trim();

  if (isSameOrSubReason(a, b)) {
    final spaceA = RegExp(r'\s').allMatches(a).length;
    final spaceB = RegExp(r'\s').allMatches(b).length;
    if (spaceB != spaceA) return spaceB > spaceA ? b.trim() : a.trim();
    // Prefer longer (usually complete final)
    return b.trim().length >= a.trim().length ? b.trim() : a.trim();
  }
  // Truly different segments (e.g. pre-tool vs post-tool)
  return '${a.trimRight()}\n\n${b.trimLeft()}';
}

/// Merge [incoming] into existing [current] for the same turn.
/// Always returns a single string (never creates a second card).
String mergeReasoningForTurn(String? current, String incoming) {
  final r = incoming.trim();
  if (r.isEmpty) return (current ?? '').trim();
  if (current == null || current.trim().isEmpty) return r;
  return preferReasoning(current, r);
}
