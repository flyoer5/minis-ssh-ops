import 'package:flutter/material.dart';

/// Pads / translates for the system IME without fighting the IME animation.
///
/// Reads [FlutterView.viewInsets] via [WidgetsBindingObserver.didChangeMetrics]
/// — **not** [MediaQuery] — so only this leaf [setState]s on keyboard frames.
///
/// **Stable element tree**: always the same [Stack] → [Transform]/[Padding] →
/// [child] structure, even when IME height is 0. Switching `return child` ↔
/// wrapped tree remounts the [TextField] and drops keyboard focus (Agent bug).
///
/// Sheet helpers: [left]/[right]/[top]/[extraBottom] add fixed padding around
/// [child] (host editor / session settings sheets).
class ImeInset extends StatefulWidget {
  const ImeInset({
    super.key,
    required this.child,
    this.usePadding = true,
    this.fillColor,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.extraBottom = 0,
  });

  final Widget child;

  /// When true (default): pad bottom by IME height (forms / sheets).
  /// When false: translate up only — parent layout height unchanged (Agent /
  /// Terminal composer so the message list does not reflow every frame).
  final bool usePadding;

  /// When [usePadding] is false, paint this under the translated child to fill
  /// the gap that would otherwise show the window background.
  final Color? fillColor;

  final double left;
  final double right;
  final double top;

  /// Extra bottom padding beyond IME (safe area / sheet chrome).
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

    // Always the same skeleton so TextField Elements are not remounted when
    // IME goes 0 ↔ non-zero (that auto-dismissed the Agent keyboard).
    if (widget.usePadding) {
      return Padding(
        padding: EdgeInsets.only(bottom: _ime),
        child: padded,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.fillColor != null && _ime > 0.5)
          Positioned(
            left: 0,
            right: 0,
            bottom: -_ime,
            height: _ime,
            child: ColoredBox(color: widget.fillColor!),
          ),
        Transform.translate(
          offset: Offset(0, -_ime),
          child: padded,
        ),
      ],
    );
  }
}

/// Freezes MediaQuery for a **subtree** (message list / scrollback only).
///
/// Do **not** wrap the whole shell or Scaffold that hosts form [TextField]s —
/// zeroed [viewInsets] breaks ensureVisible / keyboard lift for every field.
class WithoutViewInsets extends StatelessWidget {
  const WithoutViewInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        viewInsets: EdgeInsets.zero,
        // Keep padding == viewPadding so system does not shrink padding when
        // the IME opens (another MediaQuery rebuild path).
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

/// Hides [child] (bottom nav) while the IME is open — **local** [setState] only.
/// Does not rebuild [HomeShell] / [IndexedStack] / Agent (preserves TextField focus).
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
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final ime = view.viewInsets.bottom / view.devicePixelRatio;
    final open = _open ? ime > 4 : ime > 12;
    if (open == _open) return;
    setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    if (_open) return const SizedBox.shrink();
    return widget.child;
  }
}
