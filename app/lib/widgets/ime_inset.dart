import 'package:flutter/material.dart';

/// Pads [child] by the current IME height.
///
/// Important: only *this* widget depends on [MediaQuery.viewInsets], so keyboard
/// animation does not rebuild the whole page (message list, terminal scrollback).
///
/// Do **not** wrap with [AnimatedPadding] — [MediaQuery.viewInsets] is already
/// interpolated by the framework during the IME animation; a second animation
/// fights it and feels laggy.
class ImeInset extends StatelessWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.extraBottom = 0,
    this.left = 0,
    this.right = 0,
    this.top = 0,
  });

  final Widget child;
  final double extraBottom;
  final double left;
  final double right;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ime = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, ime + extraBottom),
      child: child,
    );
  }
}
