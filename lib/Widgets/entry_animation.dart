import 'package:flutter/material.dart';

class EntryAnimation extends StatelessWidget {
  const EntryAnimation({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 18),
    this.beginScale = 0.98,
    this.duration = const Duration(milliseconds: 360),
  });

  final Widget child;
  final int index;
  final Offset offset;
  final double beginScale;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final stagger = Duration(milliseconds: (index * 55).clamp(0, 360));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + stagger,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: offset * (1 - value),
            child: Transform.scale(
              scale: beginScale + ((1 - beginScale) * value),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class AnimatedPressable extends StatefulWidget {
  const AnimatedPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
