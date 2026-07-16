import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_lock.dart';
import '../theme/prime_theme.dart';
import '../widgets/ambient_background.dart';

/// Full-screen PIN gate shown on launch and whenever the app returns from
/// the background while app lock is enabled. Calls [onUnlocked] once the
/// correct PIN or a successful biometric check is provided.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entered = '';
  bool _error = false;
  bool _biometricAvailable = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final hasBiometrics = await AppLock.deviceHasBiometrics();
    final prefersBiometric = await AppLock.biometricPreferred();
    if (!mounted) return;
    setState(() => _biometricAvailable = hasBiometrics && prefersBiometric);
    if (_biometricAvailable) {
      // Offer biometric immediately so the user isn't forced to type a PIN
      // every time when fingerprint is set up.
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await AppLock.authenticateBiometric();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _onDigit(String d) async {
    if (_entered.length >= 8) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += d;
      _error = false;
    });
    if (_entered.length >= 4) {
      final ok = await AppLock.verifyPin(_entered);
      if (ok) {
        widget.onUnlocked();
      } else if (_entered.length >= 8) {
        setState(() {
          _error = true;
          _entered = '';
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: PrimeGradients.header,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: PrimeShadows.tile,
                  ),
                  child: const Icon(Icons.lock_outline, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 20),
                Text('Prime Locked', style: PrimeTheme.text(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  _error ? 'Incorrect PIN, try again' : 'Enter your PIN to continue',
                  style: PrimeTheme.text(
                    fontSize: 13,
                    color: _error ? PrimeColors.destructive : PrimeColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _entered.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? PrimeColors.prime400 : Colors.white.withValues(alpha: 0.15),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 36),
                _PinPad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  showBiometric: _biometricAvailable,
                  onBiometric: _tryBiometric,
                  checking: _checking,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool showBiometric;
  final VoidCallback onBiometric;
  final bool checking;

  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    required this.showBiometric,
    required this.onBiometric,
    required this.checking,
  });

  Widget _key({Widget? child, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: child,
      ),
    );
  }

  Widget _digitKey(String d) => _key(
        onTap: () => onDigit(d),
        child: Text(d, style: PrimeTheme.text(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map(_digitKey).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            showBiometric
                ? _key(
                    onTap: checking ? null : onBiometric,
                    child: checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.prime300),
                          )
                        : const Icon(Icons.fingerprint, color: PrimeColors.prime300, size: 26),
                  )
                : const SizedBox(width: 68, height: 68),
            _digitKey('0'),
            _key(
              onTap: onBackspace,
              child: const Icon(Icons.backspace_outlined, size: 20, color: PrimeColors.mutedForeground),
            ),
          ],
        ),
      ],
    );
  }
}
