import 'package:flutter/material.dart';

/// Lift [child] above the IME without rebuilding the rest of the page.
///
/// Reads [FlutterView.viewInsets] via [didChangeMetrics] (not MediaQuery),
/// so only this leaf setStates during keyboard animation.
///
/// Important: the widget tree shape around [child] is **stable** whether the
/// keyboard is open or closed. Switching between `return child` and
/// `Stack(Transform(child))` remounts TextFields and drops focus (Agent bug).
class ImeInset extends StatefulWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.usePadding = true,
    this.fillColor,
  });

  final Widget child;

  /// true: [Padding] bottom (forms). false: [Transform.translate] (Agent/terminal).
  final bool usePadding;

  /// Paint under the lifted bar so the gap above the keyboard is not a black hole.
  final Color? fillColor;

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

  @override
  Widget build(BuildContext context) {
    final ime = _ime;
    // Always the same parent chain so TextField Elements are not remounted
    // when the keyboard opens (focus would be lost).
    final Widget lifted = widget.usePadding
        ? Padding(
            padding: EdgeInsets.only(bottom: ime),
            child: widget.child,
          )
        : Transform.translate(
            offset: Offset(0, -ime),
            child: widget.child,
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        lifted,
        if (widget.fillColor != null && ime > 0.5)
          Positioned(
            left: 0,
            right: 0,
            bottom: -ime,
            height: ime,
            child: IgnorePointer(
              child: ColoredBox(color: widget.fillColor!),
            ),
          ),
      ],
    );
  }
}

/// Freeze MediaQuery for a heavy subtree (message list / scrollback only).
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

/// Top inset via stable [viewPadding] (not [padding], which shrinks with IME).
class TopSafePad extends StatelessWidget {
  const TopSafePad({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: child,
    );
  }
}

/// Hides [child] (typically [NavigationBar]) while the IME is open.
///
/// setState stays **inside this widget** so [IndexedStack] / Agent TextField
/// are not rebuilt by the shell when the keyboard opens (which drops focus).
class ImeAwareBottomBar extends StatefulWidget {
  const ImeAwareBottomBar({super.key, required this.child});
  final Widget child;

  @override
  State<ImeAwareBottomBar> createState() => _ImeAwareBottomBarState();
}

class _ImeAwareBottomBarState extends State<ImeAwareBottomBar>
    with WidgetsBindingObserver {
  bool _open = false;

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
    double ime = 0;
    try {
      final view = View.of(context);
      ime = view.viewInsets.bottom / view.devicePixelRatio;
    } catch (_) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      ime = views.first.viewInsets.bottom / views.first.devicePixelRatio;
    }
    // Hysteresis: open quickly, close only when nearly gone.
    final open = _open ? ime > 4 : ime > 12;
    if (open == _open) return;
    setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the child Element alive (Offstage) so Scaffold doesn't thrash;
    // height collapses via zero-size when open.
    if (_open) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
