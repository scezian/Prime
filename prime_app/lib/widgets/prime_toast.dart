import 'package:flutter/material.dart';
import '../theme/prime_theme.dart';

enum ToastKind { success, error, info }

/// Top-anchored toast for ephemeral results — e.g. "command ran / failed".
/// Not stored anywhere; for a persisted, browsable history use
/// PackageActivityCenter instead (that's what backs the Packages screen's
/// activity panel).
class PrimeToast {
  static void show(
    BuildContext context, {
    required String message,
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastCard(
        message: message,
        kind: kind,
        duration: duration,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  final String message;
  final ToastKind kind;
  final Duration duration;
  final VoidCallback onDismissed;

  const _ToastCard({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _slide = Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismissed();
  }

  Color get _accent {
    switch (widget.kind) {
      case ToastKind.success:
        return PrimeColors.success;
      case ToastKind.error:
        return PrimeColors.destructive;
      case ToastKind.info:
        return PrimeColors.primary;
    }
  }

  IconData get _icon {
    switch (widget.kind) {
      case ToastKind.success:
        return Icons.check_circle;
      case ToastKind.error:
        return Icons.error;
      case ToastKind.info:
        return Icons.info;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 8,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: PrimeColors.ink900,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withValues(alpha: 0.4)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Icon(_icon, size: 18, color: _accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: PrimeTheme.text(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
