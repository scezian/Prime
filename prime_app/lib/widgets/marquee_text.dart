import 'package:flutter/material.dart';

/// Single-line text that continuously scrolls left when it doesn't fit
/// its available width, and renders as plain (ellipsized) text when it
/// does fit. Used for the now-playing title so long track names loop
/// instead of truncating.
///
/// Pauses briefly at the start of each cycle (and again once it wraps
/// back around, which is visually seamless thanks to the duplicated
/// copy + gap) so the text is actually readable instead of scrolling
/// nonstop.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double gap;
  final double pixelsPerSecond;
  final Duration pauseDuration;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.gap = 32,
    this.pixelsPerSecond = 10,
    this.pauseDuration = const Duration(milliseconds: 1400),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ctrl
        ..stop()
        ..value = 0
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = painter.width;
        final maxWidth = constraints.maxWidth;

        if (!textWidth.isFinite || textWidth <= maxWidth) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final scrollDistance = textWidth + widget.gap;
        final scrollMs = (scrollDistance / widget.pixelsPerSecond * 1000)
            .round()
            .clamp(1500, 20000);
        final pauseMs = widget.pauseDuration.inMilliseconds;
        final totalMs = scrollMs + pauseMs * 2;
        _ctrl.duration = Duration(milliseconds: totalMs);

        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final elapsedMs = _ctrl.value * totalMs;
                double dx;
                if (elapsedMs < pauseMs) {
                  dx = 0;
                } else if (elapsedMs < pauseMs + scrollMs) {
                  final t = (elapsedMs - pauseMs) / scrollMs;
                  dx = -t * scrollDistance;
                } else {
                  dx = -scrollDistance;
                }
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: dx,
                      top: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.text,
                            style: widget.style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          SizedBox(width: widget.gap),
                          Text(
                            widget.text,
                            style: widget.style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          SizedBox(width: widget.gap),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
