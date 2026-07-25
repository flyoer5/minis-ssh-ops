import 'package:flutter/material.dart';

/// Lifts [child] above the keyboard **without changing layout size**.
///
/// Why translate (not Padding):
/// - [Padding] grows the leaf every IME frame → parent [Column] shrinks
///   [Expanded] siblings → ListView/terminal scrollback **relayout every frame**
///   (that is the stutter users feel).
/// - [Transform.translate] only moves paint/hit-test; flex children keep a
///   stable size for the whole animation.
///
/// Pair with Android `windowSoftInputMode=adjustNothing` and
/// `Scaffold.resizeToAvoidBottomInset: false`.
///
/// Depends only on [MediaQuery.viewInsetsOf] so siblings that never read
/// viewInsets are not marked dirty by this widget.
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
  /// Extra lift (e.g. small gap). Applied on top of viewInsets.bottom.
  final double extraBottom;

  @override
  Widget build(BuildContext context) {
    final ime = MediaQuery.viewInsetsOf(context).bottom;
    final dy = ime + extraBottom;
    Widget w = child;
    if (left != 0 || right != 0 || top != 0) {
      w = Padding(
        padding: EdgeInsets.fromLTRB(left, top, right, 0),
        child: w,
      );
    }
    if (dy == 0) return w;
    return Transform.translate(
      offset: Offset(0, -dy),
      child: w,
    );
  }
}

/// Freezes [MediaQuery.viewInsets] at zero for [child].
///
/// Under `adjustNothing`, viewInsets still animates every frame. Any descendant
/// that calls [MediaQuery.of] (e.g. [SafeArea], some scrollables) would
/// otherwise rebuild. This wrapper re-provides a stable MediaQueryData so
/// those dependents are not notified during the IME animation.
///
/// The wrapper itself rebuilds cheaply; when stripped data is equal across
/// frames, [MediaQuery] does not notify its dependents.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    if (data.viewInsets == EdgeInsets.zero) return child;
    return MediaQuery(
      data: data.copyWith(viewInsets: EdgeInsets.zero),
      child: child,
    );
  }
}

/// Top (and optional sides) safe padding without [SafeArea].
///
/// [SafeArea] uses [MediaQuery.of] (full data) so it rebuilds on every IME
/// frame. [MediaQuery.paddingOf] only depends on padding.
class TopSafePad extends StatelessWidget {
  const TopSafePad({
    super.key,
    required this.child,
    this.left = true,
    this.right = true,
    this.top = true,
    this.bottom = false,
  });

  final Widget child;
  final bool left;
  final bool right;
  final bool top;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: left ? pad.left : 0,
        right: right ? pad.right : 0,
        top: top ? pad.top : 0,
        bottom: bottom ? pad.bottom : 0,
      ),
      child: child,
    );
  }
}
