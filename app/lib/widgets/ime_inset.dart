import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Lifts [child] above the keyboard **without** depending on [MediaQuery].
///
/// Flutter's [Scaffold] uses `MediaQuery.of` even with
/// `resizeToAvoidBottomInset: false`, so every IME frame rebuilds the whole
/// page if anything in the tree still sees animating viewInsets/padding.
///
/// This widget reads [FlutterView.viewInsets] via [WidgetsBindingObserver]
/// and only [setState]s **itself** — ancestors/siblings stay cold.
///
/// Layout size does not change ([Transform.translate] only), so parent
/// [Column]/[Expanded] children do not relayout during the animation.
///
/// Pair with Android `windowSoftInputMode=adjustNothing` and
/// [WithoutViewInsets] around [Scaffold] / page body.
class ImeInset extends StatefulWidget {
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
  State<ImeInset> createState() => _ImeInsetState();
}

class _ImeInsetState extends State<ImeInset> with WidgetsBindingObserver {
  double _ime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // First frame: context may not have a View yet.
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
    final dy = _ime + widget.extraBottom;
    Widget w = widget.child;
    if (widget.left != 0 || widget.right != 0 || widget.top != 0) {
      w = Padding(
        padding: EdgeInsets.fromLTRB(widget.left, widget.top, widget.right, 0),
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

/// Freezes IME-driven [MediaQuery] fields so [Scaffold] / lists do not rebuild.
///
/// Under `adjustNothing`, Flutter still animates viewInsets every frame and
/// shrinks [MediaQueryData.padding]. [Scaffold] calls `MediaQuery.of`, so it
/// rebuilds the entire page unless a parent re-provides a **stable**
/// [MediaQueryData].
///
/// Frozen data:
/// - `viewInsets: EdgeInsets.zero`
/// - `padding: viewPadding` (keyboard must not eat safe padding)
///
/// [ImeInset] does **not** read MediaQuery — safe as a descendant.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final frozen = data.copyWith(
      viewInsets: EdgeInsets.zero,
      padding: data.viewPadding,
    );
    return MediaQuery(data: frozen, child: child);
  }
}

/// Top/side safe padding using stable [MediaQuery.viewPaddingOf].
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
