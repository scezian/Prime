import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/prime_theme.dart';

/// Slow-drifting blurred gradient blobs behind screen content, matching the
/// bolt.new mockup's ambient purple glow. Purely decorative — sits behind
/// whatever is passed as `child`.
class AmbientBackground extends StatefulWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: PrimeColors.background),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * math.pi;
            return Stack(
              children: [
                Positioned(
                  left: -60 + 50 * math.sin(t),
                  top: -140 + 40 * math.cos(t * 0.8),
                  child: _blob(PrimeColors.prime700.withValues(alpha: 0.55), 300),
                ),
                Positioned(
                  right: -90 + 45 * math.cos(t * 0.6),
                  top: 140 + 50 * math.sin(t * 0.5),
                  child: _blob(PrimeColors.prime500.withValues(alpha: 0.35), 240),
                ),
                Positioned(
                  left: -70 + 40 * math.cos(t * 0.4),
                  bottom: -120 + 45 * math.sin(t * 0.7),
                  child: _blob(PrimeColors.prime900.withValues(alpha: 0.6), 280),
                ),
              ],
            );
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
          child: Container(color: Colors.transparent),
        ),
        // Subtle scrim so foreground text/cards stay readable over the glow.
        Container(color: PrimeColors.background.withValues(alpha: 0.35)),
        widget.child,
      ],
    );
  }
}
