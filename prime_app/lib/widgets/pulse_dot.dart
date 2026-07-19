import 'package:flutter/material.dart';
import '../theme/prime_theme.dart';

class PulseDot extends StatefulWidget {
  final Color? color;
  final double size;

  const PulseDot({super.key, this.color, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.2,
      height: widget.size * 2.2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final resolvedColor = widget.color ?? PrimeColors.primary;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.4,
                child: Container(
                  width: widget.size * (1 + t * 1.2),
                  height: widget.size * (1 + t * 1.2),
                  decoration: BoxDecoration(color: resolvedColor, shape: BoxShape.circle),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: resolvedColor, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}
