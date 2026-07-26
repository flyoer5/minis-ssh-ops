import 'package:flutter/material.dart';

/// Pads / translates for the system IME without fighting the IME animation.
///
/// Reads [FlutterView.viewInsets] via [WidgetsBindingObserver.didChangeMetrics]
/// — **not** [MediaQuery] — so only this leaf [setState]s on keyboard frames.
///
/// **Stable element tree**: always the same widget skeleton, even when IME
/// height is 0. Conditional `return child` / conditional Stack children remount
/// the [TextField] and drop keyboard focus (Agent auto-dismiss bug).
///
/// [reservedBottom]: shell chrome already under the composer (e.g. NavigationBar).
/// Lift by max(0, ime - reservedBottom) so we do **not** need to hide the bar
/// (hiding Scaffold.bottomNavigationBar mid-IME still dismisses the keyboard).
///
/// Sheet helpers: [left]/[right]/[top]/[extraBottom] fixed padding.
class ImeInset extends StatefulWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.usePadding = true,
    this.reservedBottom = 0,
    this.fillColor,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.extraBottom = 0,
  });

  final Widget child;
  final bool usePadding;

  /// Height already occupied under [child] (bottom nav). Subtracted from IME lift.
  final double reservedBottom;

  final Color? fillColor;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _sync();

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

  double get _lift {
    final v = _ime - widget.reservedBottom;
    return v > 0 ? v : 0;
  }

  @override
  Widget build(BuildContext context) {
    final padded = (widget.left > 0 ||
            widget.right > 0 ||
            widget.top > 0 ||
            widget.extraBottom > 0)
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              widget.left,
              widget.top,
              widget.right,
              widget.extraBottom,
            ),
            child: widget.child,
          )
        : widget.child;

    final lift = _lift;

    if (widget.usePadding) {
      // Always Padding — never swap with bare child.
      return Padding(
        padding: EdgeInsets.only(bottom: lift),
        child: padded,
      );
    }

    // Always Stack → [gap fill, translate] — never conditional children.
    final fill = widget.fillColor ?? const Color(0x00000000);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: -lift,
          height: lift < 0.5 ? 0 : lift,
          child: ColoredBox(color: fill),
        ),
        Transform.translate(
          offset: Offset(0, -lift),
          child: padded,
        ),
      ],
    );
  }
}

/// Freezes MediaQuery for a **subtree** (message list / scrollback only).
///
/// Do **not** wrap the whole shell or Scaffold that hosts form [TextField]s.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        viewInsets: EdgeInsets.zero,
        padding: mq.viewPadding,
      ),
      child: child,
    );
  }
}

/// Top system inset only — uses [viewPaddingOf] (stable when IME opens).
class TopSafePad extends StatelessWidget {
  const TopSafePad({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Padding(padding: EdgeInsets.only(top: top), child: child);
  }
}
