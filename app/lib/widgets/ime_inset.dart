import 'package:flutter/material.dart';

/// Pads [child] by the current keyboard inset without rebuilding ancestors.
///
/// Must be a **leaf** under a Scaffold with `resizeToAvoidBottomInset: false`
/// and preferably Android `windowSoftInputMode=adjustNothing` so the window
/// size stays fixed while only this widget reacts to [MediaQuery.viewInsets].
///
/// No [AnimatedPadding]: the platform IME already interpolates insets each frame;
/// a second animation curve fights it and feels like jank.
class ImeInset extends StatelessWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.extraBottom = 0,
  });

  final Widget child;
  final double left;
  final double right;
  final double top;
  final double extraBottom;

  @override
  Widget build(BuildContext context) {
    final ime = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, ime + extraBottom),
      child: child,
    );
  }
}

/// Optional: strip viewInsets from [child] so deep MediaQuery consumers do not
/// mark dirty when only the keyboard moves. Prefer [adjustNothing] + no sizeOf.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.viewInsets.bottom == 0 && mq.viewInsets.top == 0) return child;
    return MediaQuery(
      data: mq.copyWith(viewInsets: EdgeInsets.zero),
      child: child,
    );
  }
}
