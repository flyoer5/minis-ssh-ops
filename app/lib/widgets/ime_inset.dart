import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Bottom pad/lift for a **leaf** (composer / keybar) using live IME height.
///
/// Reads [FlutterView.viewInsets] via [WidgetsBindingObserver] so only this
/// State setStates — does not require ancestors to depend on [MediaQuery].
///
/// Uses [Padding] (layout) rather than [Transform.translate]: with
/// [windowSoftInputMode] `adjustResize` the window already shrinks; padding
/// the leaf is still correct when the parent Scaffold has
/// `resizeToAvoidBottomInset: false` and only the composer should move.
///
/// When [usePadding] is false, uses translate (layout size fixed) — prefer
/// for chat lists that must not reflow.
class ImeInset extends StatefulWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.extraBottom = 0,
    this.usePadding = true,
  });

  final Widget child;
  final double left;
  final double right;
  final double top;
  final double extraBottom;
  /// true: [Padding] (forms / default). false: [Transform.translate] (chat).
  final bool usePadding;

  @override
  State<ImeInset> createState() => _ImeInsetState();
}

class _ImeInsetState extends State<ImeInset> with WidgetsBindingObserver {
  double _ime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    double ime;
    try {
      final view = View.of(context);
      ime = view.viewInsets.bottom / view.devicePixelRatio;
    } catch (_) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      ime = view.viewInsets.bottom / view.devicePixelRatio;
    }
    if ((ime - _ime).abs() < 0.5) return;
    setState(() => _ime = ime);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = _ime + widget.extraBottom;
    if (widget.usePadding) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.left,
          widget.top,
          widget.right,
          bottom,
        ),
        child: widget.child,
      );
    }
    Widget w = widget.child;
    if (widget.left != 0 || widget.right != 0 || widget.top != 0) {
      w = Padding(
        padding: EdgeInsets.fromLTRB(widget.left, widget.top, widget.right, 0),
        child: w,
      );
    }
    if (bottom == 0) return w;
    return Transform.translate(offset: Offset(0, -bottom), child: w);
  }
}

/// Freeze IME-driven MediaQuery for a **subtree only** (e.g. message list).
///
/// Do **not** wrap the whole app or form pages — focused [TextField]s need
/// real [MediaQuery.viewInsets] for ensureVisible / Scaffold inset.
///
/// When frozen [MediaQueryData] is equal across frames, list descendants skip
/// rebuild even if an ancestor [Scaffold] rebuilds.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        viewInsets: EdgeInsets.zero,
        // Keep padding stable: under some modes padding shrinks with IME.
        padding: data.viewPadding,
      ),
      child: child,
    );
  }
}

/// Top/side safe pad via stable [MediaQuery.viewPaddingOf] (not paddingOf).
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
    final pad = MediaQuery.viewPaddingOf(context);
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
