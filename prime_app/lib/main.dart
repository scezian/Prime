import 'package:flutter/material.dart';
import 'services/api_client.dart';
import 'services/app_lock.dart';
import 'services/package_activity.dart';
import 'theme/prime_theme.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';

void main() {
  runApp(const PrimeApp());
}

class PrimeApp extends StatefulWidget {
  const PrimeApp({super.key});

  @override
  State<PrimeApp> createState() => _PrimeAppState();
}

class _PrimeAppState extends State<PrimeApp> {
  final ApiClient _apiClient = ApiClient();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    PackageActivityCenter.instance.load();
    _apiClient.loadConfig().then((_) {
      setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prime',
      theme: PrimeTheme.dark,
      darkTheme: PrimeTheme.dark,
      themeMode: ThemeMode.dark,
      home: !_loaded
          ? Scaffold(
              backgroundColor: PrimeColors.background,
              body: const Center(child: CircularProgressIndicator(color: PrimeColors.primary)),
            )
          : _AppLockGate(child: HomeScreen(apiClient: _apiClient)),
    );
  }
}

/// Sits above [HomeScreen] and shows [LockScreen] whenever app lock is
/// enabled — on cold start, and again any time the app returns from the
/// background (so switching away and back re-locks it, not just relaunch).
class _AppLockGate extends StatefulWidget {
  final Widget child;
  const _AppLockGate({required this.child});

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate> with WidgetsBindingObserver {
  bool _lockChecked = false;
  bool _locked = false;
  DateTime? _pausedAt;

  /// How long the app can sit in the background before the next resume
  /// requires the PIN again. Brief interruptions — a notification shade
  /// swipe, the biometric prompt's own system overlay, switching to
  /// answer a text — land well under this and don't re-lock.
  static const _graceDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLock() async {
    final enabled = await AppLock.isEnabled();
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _lockChecked = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Different Android skins report backgrounding differently — some send
    // `inactive` for a notification-shade pull, others (MIUI and other
    // heavily customized ROMs) send `paused` for the same gesture. Rather
    // than special-case specific state names, treat any non-`resumed`
    // state as "left" and only re-lock if we've been away for longer than
    // the grace period by the time we're `resumed` again.
    if (state != AppLifecycleState.resumed) {
      _pausedAt ??= DateTime.now();
      return;
    }

    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    final awayFor = DateTime.now().difference(pausedAt);
    if (awayFor < _graceDuration) return; // back quickly enough, stay unlocked

    AppLock.isEnabled().then((enabled) {
      if (enabled && mounted) setState(() => _locked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_lockChecked) {
      return Scaffold(
        backgroundColor: PrimeColors.background,
        body: const Center(child: CircularProgressIndicator(color: PrimeColors.primary)),
      );
    }
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return widget.child;
  }
}
