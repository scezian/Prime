import 'package:flutter/material.dart';

/// Wraps [child] with a soft diagonal light band that sweeps across it on
/// a loop. Purely decorative and ignores pointer events -- used on the
/// power/lock buttons, the now-playing card, and the grid tiles so they
/// read as glass rather than flat color.
class ShimmerSweep extends StatefulWidget {
  final Widget child;
  final bool active;
  final Duration period;

  const ShimmerSweep({
    super.key,
    required this.child,
    this.active = true,
    this.period = const Duration(seconds: 3),
  });

  @override
  State<ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<ShimmerSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period);
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant ShimmerSweep old) {
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
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  return ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment(-1.6 + 3.2 * t, -1),
                      end: Alignment(-0.6 + 3.2 * t, 1),
                      colors: const [
                        Colors.transparent,
                        Color(0x33FFFFFF),
                        Colors.transparent,
                      ],
                      stops: const [0.35, 0.5, 0.65],
                    ).createShader(rect),
                    child: Container(color: Colors.white),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
