import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UI feedback helpers — single place for snackbar + error-string cleanup so
/// the 40+ call sites stay consistent (duration, styling, message shape).

/// Light haptic pulse when enabled. Call at the start of user actions
/// (select, toggle, send, refresh) for tactile confirmation.
void hapticTap(bool enabled) {
  if (!enabled) return;
  HapticFeedback.lightImpact();
}

/// Medium haptic for heavier actions (delete, stop, destructive confirms).
void hapticConfirm(bool enabled) {
  if (!enabled) return;
  HapticFeedback.mediumImpact();
}

/// Show a compact snackbar with consistent styling and timing. One-second
/// feedback is used for transient confirmations; pass a longer duration only
/// when the message needs reading or exposes an action.
void showSnack(
  BuildContext context,
  String message, {
  int seconds = 1,
  SnackBarAction? action,
  bool floating = true,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      duration: Duration(seconds: seconds),
      action: action,
      behavior: floating ? SnackBarBehavior.floating : null,
    ),
  );
}

void showErrorSnack(BuildContext context, Object error, {String prefix = ''}) {
  final message = shortError(error, max: 96);
  showSnack(context, '$prefix$message', seconds: 3);
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
