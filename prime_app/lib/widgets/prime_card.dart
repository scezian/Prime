import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/prime_theme.dart';

/// Reusable card surface with elevation and tactile tap feedback: a
/// slight scale-down + shadow-drop on press (so it reads as being
/// pushed into the surface) plus the standard Material ripple, all
/// driven off one gesture source (InkWell) to avoid double-handling.
///
/// Drop-in replacement for the ad-hoc `InkWell` + `BoxDecoration` pairs
/// scattered across control/files/settings/packages/commands screens.
/// If [onTap] is null, the card renders as a static (non-pressable)
/// surface — no ripple, no scale animation.
class PrimeCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;
  final List<BoxShadow>? boxShadow;

  const PrimeCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.boxShadow,
  });

  @override
  State<PrimeCard> createState() => _PrimeCardState();
}

class _PrimeCardState extends State<PrimeCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    if (value && !_pressed) {
      HapticFeedback.selectionClick();
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final restShadow = widget.boxShadow ?? PrimeShadows.tile;
    return AnimatedSlide(
      offset: _pressed ? const Offset(0, 0.02) : Offset.zero,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _pressed
                ? (widget.color ?? PrimeColors.card).withValues(alpha: 0.85)
                : (widget.color ?? PrimeColors.card),
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _pressed
                  ? PrimeColors.primary.withValues(alpha: 0.7)
                  : PrimeColors.border,
              width: _pressed ? 1.8 : 1,
            ),
            boxShadow: _pressed ? const [] : restShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _setPressed,
              borderRadius: widget.borderRadius,
              splashColor: PrimeColors.primary.withValues(alpha: 0.20),
              highlightColor: PrimeColors.primary.withValues(alpha: 0.10),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
