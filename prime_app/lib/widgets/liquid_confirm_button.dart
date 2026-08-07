import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/biometric_auth.dart';
import '../theme/prime_theme.dart';
import 'shimmer_sweep.dart';

enum LiquidButtonVariant { outlined, filled }

/// Visual treatment for [LiquidButtonVariant.filled]. Both read as glass
/// rather than a flat red fill -- flip the call site's `glassStyle` and
/// hot-reload to compare:
///  - [frosted]: real backdrop blur, translucent, subtle red tint
///  - [gradient]: soft red-to-dark diagonal gradient, no blur
enum GlassStyle { frosted, gradient }

/// Press-and-hold confirm button for destructive power actions. Replaces
/// the old two-tap "tap to arm, tap to confirm" flow: holding the button
/// fills it like water rising in a glass. Release early and it drains
/// back down (cancelled). Hold it to the top and it auto-prompts
/// biometric, then fires the command.
///
/// Two ways to fire on success:
///  - `apiClient` + `commandId`: fires a plain daemon command (power
///    buttons -- Shutdown/Restart/Log Out).
///  - `onConfirmed`: custom async logic for buttons that need more than
///    "run this command" (e.g. Lock/Unlock's password lookup + prompt +
///    toggle). Takes priority over apiClient/commandId if both given.
///
/// `needsConfirm` is kept for call-site compatibility with the old
/// _PowerActionButton API but no longer changes behavior -- the hold
/// itself IS the confirmation now.
class LiquidConfirmButton extends StatefulWidget {
  final ApiClient? apiClient;
  final String? commandId;
  final Future<void> Function(BuildContext context)? onConfirmed;
  final String label;
  final IconData icon;
  final bool needsConfirm;
  final bool expectDaemonDeath;
  final LiquidButtonVariant variant;
  final bool showLabel;
  final GlassStyle glassStyle;

  const LiquidConfirmButton({
    super.key,
    this.apiClient,
    this.commandId,
    this.onConfirmed,
    required this.label,
    required this.icon,
    this.needsConfirm = true,
    this.expectDaemonDeath = false,
    this.variant = LiquidButtonVariant.outlined,
    this.showLabel = true,
    this.glassStyle = GlassStyle.frosted,
  }) : assert(
          onConfirmed != null || (apiClient != null && commandId != null),
          'LiquidConfirmButton needs either onConfirmed, or both apiClient and commandId',
        );

  @override
  State<LiquidConfirmButton> createState() => _LiquidConfirmButtonState();
}

class _LiquidConfirmButtonState extends State<LiquidConfirmButton>
    with TickerProviderStateMixin {
  static const _fillDuration = Duration(milliseconds: 1300);
  static const _drainDuration = Duration(milliseconds: 260);
  static const _rippleDuration = Duration(milliseconds: 450);

  late final AnimationController _fillCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _rippleCtrl;
  bool _verifying = false;
  bool _loading = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fillCtrl = AnimationController(vsync: this, duration: _fillDuration);
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _rippleCtrl = AnimationController(vsync: this, duration: _rippleDuration);
    _fillCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onFilled();
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_loading || _verifying) return;
    _fillCtrl.duration = _fillDuration;
    _fillCtrl.forward();
    _rippleCtrl.forward(from: 0);
    HapticFeedback.selectionClick();
    setState(() => _pressed = true);
  }

  void _release() {
    if (_fillCtrl.status == AnimationStatus.forward) {
      _fillCtrl.duration = _drainDuration;
      _fillCtrl.reverse();
    }
    if (_pressed) setState(() => _pressed = false);
  }

  Future<void> _onFilled() async {
    HapticFeedback.mediumImpact();
    setState(() => _verifying = true);

    final authorized = await BiometricAuth.confirm('Confirm: ${widget.label}');
    if (!mounted) return;

    if (!authorized) {
      setState(() => _verifying = false);
      _fillCtrl.duration = _drainDuration;
      _fillCtrl.reverse();
      return;
    }

    setState(() {
      _verifying = false;
      _loading = true;
    });
    try {
      if (widget.onConfirmed != null) {
        await widget.onConfirmed!(context);
      } else {
        await widget.apiClient!.runCommand(widget.commandId!);
      }
    } catch (e) {
      if (!widget.expectDaemonDeath && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _fillCtrl.duration = _drainDuration;
        _fillCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    _waveCtrl.dispose();
    _rippleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destructive = PrimeColors.destructive;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_fillCtrl, _waveCtrl, _rippleCtrl]),
        builder: (context, _) {
          final fill = _fillCtrl.value;
          return widget.variant == LiquidButtonVariant.outlined
              ? _buildOutlined(fill, destructive)
              : _buildFilled(fill, destructive);
        },
      ),
    );
  }

  Widget _buildOutlined(double fill, Color borderColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: PrimeColors.card,
          border: Border.all(color: borderColor.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LiquidWavePainter(
                  fill: fill,
                  phase: _waveCtrl.value * 2 * math.pi,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: borderColor),
                    )
                  else
                    Icon(_verifying ? Icons.fingerprint : widget.icon, size: 18, color: borderColor),
                  const SizedBox(height: 6),
                  Text(
                    _verifying ? 'verify' : widget.label,
                    style: PrimeTheme.mono(fontSize: 10, color: borderColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glass-styled fill: [GlassStyle.frosted] uses a real [BackdropFilter]
  /// blur over a translucent white base with a red-tinted border/glow;
  /// [GlassStyle.gradient] skips the blur in favor of a red-to-dark
  /// diagonal gradient. Both keep the liquid-wave hold animation, the
  /// ripple pulse on press, a pulsing glow shadow, and a scale-bounce.
  Widget _buildFilled(double fill, Color bgColor) {
    final glass = widget.glassStyle;
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ShimmerSweep(
          active: !_loading,
          period: const Duration(seconds: 3),
          child: Stack(
            children: [
              if (glass == GlassStyle.frosted)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: const SizedBox.expand(),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: glass == GlassStyle.frosted ? Colors.white.withValues(alpha: 0.08) : null,
                    gradient: glass == GlassStyle.gradient
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              bgColor.withValues(alpha: 0.55),
                              PrimeColors.card.withValues(alpha: 0.92),
                            ],
                          )
                        : null,
                    border: Border.all(color: bgColor.withValues(alpha: 0.45), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: bgColor.withValues(alpha: _pressed ? 0.5 : 0.24),
                        blurRadius: _pressed ? 22 : 10,
                        spreadRadius: _pressed ? 1 : 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              // Diagonal glass sheen -- a fixed highlight (distinct from
              // the moving ShimmerSweep band) so the surface reads as
              // curved glass even while idle.
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x1AFFFFFF), Colors.transparent],
                        stops: [0.0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _LiquidWavePainter(fill: fill, phase: _waveCtrl.value * 2 * math.pi),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _RipplePainter(progress: _rippleCtrl.value, color: Colors.white),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_loading)
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        Icon(_verifying ? Icons.fingerprint : widget.icon, size: 18, color: Colors.white),
                      if (widget.showLabel) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _verifying ? 'Verify' : widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanding, fading ring painted from the button's center on each press
/// -- the "ripple" half of the ripple/glow ask. Independent of the
/// longer hold-to-confirm liquid fill.
class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final maxRadius = size.longestSide * 0.9;
    final radius = maxRadius * Curves.easeOut.transform(progress);
    final paint = Paint()..color = color.withValues(alpha: (1 - progress) * 0.35);
    canvas.drawCircle(size.center(Offset.zero), radius, paint);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.progress != progress;
}

/// Draws two overlapping wave layers with a meniscus (surface curls up at
/// the container edges), a wobble that's liveliest early in the hold and
/// settles as the fill nears the top, and a bright crest highlight along
/// the surface so the water reads clearly against either button color --
/// a same-color wave on a same-color button was hard to see, so this
/// always renders in a fixed cyan regardless of the button's own color.
class _LiquidWavePainter extends CustomPainter {
  final double fill;
  final double phase;
  final Color waterColor;
  final double opacityBack;
  final double opacityFront;

  _LiquidWavePainter({
    required this.fill,
    required this.phase,
    this.waterColor = const Color(0xFF22D3EE),
    this.opacityBack = 0.34,
    this.opacityFront = 0.54,
  });

  List<Offset> _crestPoints(Size size, double levelY, double amp, double phaseOffset, double sway) {
    final w = size.width;
    const n = 8;
    final pts = <Offset>[];
    for (int i = 0; i <= n; i++) {
      final x = w / n * i;
      final edgeDamp = math.sin((x / w) * math.pi);
      final y = levelY - amp * edgeDamp * math.sin(phaseOffset + i * 0.9) - sway * edgeDamp;
      pts.add(Offset(x, y));
    }
    return pts;
  }

  Path _smoothPath(List<Offset> pts) {
    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final mx = (pts[i - 1].dx + pts[i].dx) / 2;
      final my = (pts[i - 1].dy + pts[i].dy) / 2;
      path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mx, my);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  Path _fillPath(Size size, List<Offset> pts) {
    final path = _smoothPath(pts);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fill <= 0.001) return;
    final h = size.height;
    final levelY = h - fill * h;
    final settle = (1 - fill * 1.15).clamp(0.0, 1.0);
    final amp = 3.5 * settle + 0.5;
    final sway = math.sin(phase * 1.3) * 2.2 * settle;
    final swayFront = math.sin(phase * 1.55 + 1.2) * 2.6 * settle;

    final backPts = _crestPoints(size, levelY, amp * 0.7, phase * 1.1, sway);
    final frontPts = _crestPoints(size, levelY, amp, phase * 1.7 + 1.5, swayFront);

    final backPaint = Paint()..color = waterColor.withValues(alpha: opacityBack);
    final frontPaint = Paint()..color = waterColor.withValues(alpha: opacityFront);
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25 + 0.45 * settle)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(_fillPath(size, backPts), backPaint);
    canvas.drawPath(_fillPath(size, frontPts), frontPaint);
    canvas.drawPath(_smoothPath(frontPts), highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidWavePainter old) => old.fill != fill || old.phase != phase;
}
