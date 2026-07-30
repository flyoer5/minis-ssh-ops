import 'package:flutter/material.dart';

/// UI feedback helpers — single place for snackbar + error-string cleanup so
/// the 40+ call sites stay consistent (duration, styling, message shape).

/// Show a snackbar with sane defaults. [seconds] defaults to 2 (most are
/// transient confirmations); pass a longer duration for errors the user must
/// read, or an [action] for actionable messages. [floating] lifts it off the
/// bottom edge (settings-style).
void showSnack(
  BuildContext context,
  String message, {
  int seconds = 1,
  SnackBarAction? action,
  bool floating = true,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: Duration(seconds: seconds),
      action: action,
      behavior: floating ? SnackBarBehavior.floating : null,
    ),
  );
}

/// Strip framework exception wrappers so the user sees the real cause, not
/// "Exception: ..." / "ApiException(502): ..." boilerplate.
String cleanError(Object e) {
  return e
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^ApiException\(\d+\):\s*'), '')
      .trim();
}

/// Like [cleanError] but capped for a one-line snackbar.
String shortError(Object e, {int max = 160}) {
  final s = cleanError(e);
  return s.length > max ? '${s.substring(0, max)}…' : s;
}
