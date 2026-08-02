import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

/// Animated typing indicator with three bouncing dots.
/// Used in the agent chat when the model is thinking / calling tools.
class TypingIndicator extends StatefulWidget {
  final String hint;

  const TypingIndicator({super.key, this.hint = '思考中...'});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar placeholder
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.accentSoft),
          ),
          const SizedBox(width: 8),
          // Bubble with typing dots
          Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.border.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(3, (i) => _Dot(index: i, controller: _ctrl)),
                const SizedBox(width: 10),
                Text(
                  widget.hint,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends AnimatedWidget {
  final int index;
  const _Dot({required this.index, required AnimationController controller})
      : super(listenable: controller);

  AnimationController get _ctrl => listenable as AnimationController;

  @override
  Widget build(BuildContext context) {
    final phase = (index / 3 + _ctrl.value) % 1.0;
    final scale = 0.4 + 0.6 * (1 - math.cos(phase * 2 * math.pi)).abs();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentSoft,
          ),
        ),
      ),
    );
  }
}

/// Animated pulse ring — wraps a child with a subtle expanding ring.
class PulseRing extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool active;

  const PulseRing({
    super.key,
    required this.child,
    this.color = AppColors.accentSoft,
    this.active = true,
  });

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(PulseRing old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final r = _ctrl.value;
        return CustomPaint(
          painter: _PulsePainter(r, widget.color),
          child: widget.child,
        );
      },
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulsePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide / 2;
    final ringRadius = baseRadius + progress * 14;
    final alpha = ((1 - progress) * 80).toInt();
    final paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, ringRadius, paint);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.progress != progress;
}