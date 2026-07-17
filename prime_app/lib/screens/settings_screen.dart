import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/app_lock.dart';
import '../services/secure_credentials.dart';
import '../theme/prime_theme.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onSaved;

  const SettingsScreen({super.key, required this.apiClient, required this.onSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _showToken = false;
  bool _testing = false;
  bool? _testOk; // null = not tested yet

  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricHardwareAvailable = false;
  bool _lockLoaded = false;

  final _unlockPasswordController = TextEditingController();
  bool _unlockPasswordSet = false;
  bool _showUnlockPassword = false;

  @override
  void initState() {
    super.initState();
    _hostController.text = widget.apiClient.host ?? '';
    _tokenController.text = widget.apiClient.token ?? '';
    _loadLockState();
    _loadUnlockPasswordState();
  }

  Future<void> _loadLockState() async {
    final enabled = await AppLock.isEnabled();
    final biometricPref = await AppLock.biometricPreferred();
    final hardware = await AppLock.deviceHasBiometrics();
    if (!mounted) return;
    setState(() {
      _lockEnabled = enabled;
      _biometricEnabled = biometricPref;
      _biometricHardwareAvailable = hardware;
      _lockLoaded = true;
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    _unlockPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.apiClient.saveConfig(
      host: _hostController.text.trim(),
      token: _tokenController.text.trim(),
    );
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testOk = null;
    });

    await widget.apiClient.saveConfig(
      host: _hostController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await widget.apiClient.checkHealth();
    setState(() {
      _testing = false;
      _testOk = ok;
    });
  }

  Future<void> _onToggleLock(bool value) async {
    if (value) {
      final pin = await _promptSetPin();
      if (pin == null) return; // cancelled
      await AppLock.enable(pin);
      if (_biometricHardwareAvailable) {
        final useBiometric = await _promptUseBiometric();
        await AppLock.setBiometricPreferred(useBiometric);
        setState(() => _biometricEnabled = useBiometric);
      }
      setState(() => _lockEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App lock enabled')));
      }
    } else {
      final confirmedPin = await _promptVerifyPin('Enter your PIN to turn off App Lock');
      if (confirmedPin != true) return;
      await AppLock.disable();
      setState(() {
        _lockEnabled = false;
        _biometricEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App lock disabled')));
      }
    }
  }

  Future<void> _onToggleBiometric(bool value) async {
    await AppLock.setBiometricPreferred(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _onChangePin() async {
    final verified = await _promptVerifyPin('Enter your current PIN');
    if (verified != true) return;
    final newPin = await _promptSetPin();
    if (newPin == null) return;
    await AppLock.changePin(newPin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated')));
    }
  }

  Future<void> _loadUnlockPasswordState() async {
    final saved = await SecureCredentials.getUnlockPassword();
    if (!mounted) return;
    setState(() => _unlockPasswordSet = saved != null && saved.isNotEmpty);
  }

  Future<void> _saveUnlockPassword() async {
    final value = _unlockPasswordController.text;
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a password first')));
      return;
    }
    await SecureCredentials.setUnlockPassword(value);
    _unlockPasswordController.clear();
    if (!mounted) return;
    setState(() {
      _unlockPasswordSet = true;
      _showUnlockPassword = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock password saved')));
  }

  Future<void> _clearUnlockPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text('Remove saved password?', style: PrimeTheme.text(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          "You'll be asked to type it again next time you unlock.",
          style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SecureCredentials.clearUnlockPassword();
    if (!mounted) return;
    setState(() => _unlockPasswordSet = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved password removed')));
  }

  /// Two-step "enter PIN" + "confirm PIN" dialog. Returns the new PIN, or
  /// null if cancelled / the two entries didn't match.
  Future<String?> _promptSetPin() async {
    final first = await _pinDialog('Set a PIN', 'Choose a 4-8 digit PIN');
    if (first == null || first.length < 4) {
      if (first != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN must be at least 4 digits')));
      }
      return null;
    }
    final second = await _pinDialog('Confirm PIN', 'Re-enter your PIN');
    if (second != first) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINs did not match')));
      }
      return null;
    }
    return first;
  }

  /// Prompts for the existing PIN and checks it against AppLock. Returns
  /// true if correct, false if wrong, null if cancelled.
  Future<bool?> _promptVerifyPin(String message) async {
    final entered = await _pinDialog('Enter PIN', message);
    if (entered == null) return null;
    final ok = await AppLock.verifyPin(entered);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
    }
    return ok;
  }

  Future<bool> _promptUseBiometric() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text('Use fingerprint too?', style: PrimeTheme.text(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'You can unlock with fingerprint instead of typing your PIN each time.',
          style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No thanks', style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enable', style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _pinDialog(String title, String subtitle) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text(title, style: PrimeTheme.text(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: PrimeTheme.text(fontSize: 16, letterSpacing: 4),
              decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('Cancel', style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('OK', style: PrimeTheme.text(fontSize: 12, color: PrimeColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: PrimeColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PrimeColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: PrimeColors.border)),
                  ),
                  child: Text(
                    'CONNECTION',
                    style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tailscale address',
                        style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _hostController,
                        style: PrimeTheme.mono(fontSize: 13),
                        decoration: const InputDecoration(hintText: '100.x.x.x'),
                      ),
                      const SizedBox(height: 16),
                      Text('Auth token', style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tokenController,
                              obscureText: !_showToken,
                              style: PrimeTheme.mono(fontSize: 13),
                              decoration: const InputDecoration(hintText: 'from ~/.config/prime/token'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _showToken = !_showToken),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: PrimeColors.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 15,
                                color: PrimeColors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: PrimeColors.primary,
                                foregroundColor: PrimeColors.primaryForeground,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _save,
                              child: Text('save', style: PrimeTheme.mono(fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _TestConnectionButton(
                        testing: _testing,
                        result: _testOk,
                        onTap: _testConnection,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_lockLoaded)
            _AppLockCard(
              enabled: _lockEnabled,
              biometricEnabled: _biometricEnabled,
              biometricHardwareAvailable: _biometricHardwareAvailable,
              onToggleLock: _onToggleLock,
              onToggleBiometric: _onToggleBiometric,
              onChangePin: _onChangePin,
            ),
          const SizedBox(height: 16),
          _UnlockPasswordCard(
            controller: _unlockPasswordController,
            isSet: _unlockPasswordSet,
            obscure: !_showUnlockPassword,
            onToggleObscure: () => setState(() => _showUnlockPassword = !_showUnlockPassword),
            onSave: _saveUnlockPassword,
            onClear: _clearUnlockPassword,
          ),
        ],
      ),
    );
  }
}

class _AppLockCard extends StatelessWidget {
  final bool enabled;
  final bool biometricEnabled;
  final bool biometricHardwareAvailable;
  final ValueChanged<bool> onToggleLock;
  final ValueChanged<bool> onToggleBiometric;
  final VoidCallback onChangePin;

  const _AppLockCard({
    required this.enabled,
    required this.biometricEnabled,
    required this.biometricHardwareAvailable,
    required this.onToggleLock,
    required this.onToggleBiometric,
    required this.onChangePin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PrimeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PrimeColors.border)),
            ),
            child: Text(
              'APP LOCK',
              style: PrimeTheme.text(fontSize: 11, fontWeight: FontWeight.w700, color: PrimeColors.prime400, letterSpacing: 1.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: PrimeGradients.tileA,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.lock_outline, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Require PIN to open', style: PrimeTheme.text(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            "Locks Prime whenever it's backgrounded",
                            style: PrimeTheme.text(fontSize: 11, color: PrimeColors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      activeThumbColor: PrimeColors.primary,
                      onChanged: onToggleLock,
                    ),
                  ],
                ),
                if (enabled && biometricHardwareAvailable) ...[
                  const Divider(color: PrimeColors.border, height: 28),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: PrimeGradients.tileB,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.fingerprint, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Use fingerprint', style: PrimeTheme.text(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Switch(
                        value: biometricEnabled,
                        activeThumbColor: PrimeColors.primary,
                        onChanged: onToggleBiometric,
                      ),
                    ],
                  ),
                ],
                if (enabled) ...[
                  const Divider(color: PrimeColors.border, height: 28),
                  InkWell(
                    onTap: onChangePin,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.password, size: 16, color: PrimeColors.mutedForeground),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Change PIN', style: PrimeTheme.text(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: PrimeColors.mutedForeground),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockPasswordCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isSet;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _UnlockPasswordCard({
    required this.controller,
    required this.isSet,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PrimeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PrimeColors.border)),
            ),
            child: Text(
              'LAPTOP UNLOCK PASSWORD',
              style: PrimeTheme.text(fontSize: 11, fontWeight: FontWeight.w700, color: PrimeColors.prime400, letterSpacing: 1.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSet ? Icons.check_circle_outline : Icons.info_outline,
                      size: 14,
                      color: isSet ? PrimeColors.success : PrimeColors.mutedForeground,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isSet ? 'Saved — used automatically on Unlock' : 'Not saved yet',
                      style: PrimeTheme.text(fontSize: 12, color: PrimeColors.mutedForeground),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        obscureText: obscure,
                        style: PrimeTheme.mono(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: isSet ? 'Enter a new password to replace it' : 'Laptop password',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onToggleObscure,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: PrimeColors.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 15,
                          color: PrimeColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Stored encrypted on this device only, never on the laptop. Fingerprint still confirms every unlock.',
                  style: PrimeTheme.text(fontSize: 11, color: PrimeColors.mutedForeground),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PrimeColors.primary,
                          foregroundColor: PrimeColors.primaryForeground,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: onSave,
                        child: Text('save', style: PrimeTheme.mono(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    if (isSet) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PrimeColors.destructive,
                            side: BorderSide(color: PrimeColors.destructive.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: onClear,
                          child: Text('remove', style: PrimeTheme.mono(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestConnectionButton extends StatelessWidget {
  final bool testing;
  final bool? result; // null=untested, true=ok, false=fail
  final VoidCallback onTap;

  const _TestConnectionButton({required this.testing, required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color color;
    Widget content;

    if (testing) {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.primary),
          ),
          const SizedBox(width: 8),
          Text('testing...', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else if (result == true) {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check, size: 13, color: color),
          const SizedBox(width: 6),
          Text('connected', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else if (result == false) {
      color = PrimeColors.destructive;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.close, size: 13, color: color),
          const SizedBox(width: 6),
          Text('unreachable', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.podcasts, size: 13, color: color),
          const SizedBox(width: 6),
          Text('test connection', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    }

    return InkWell(
      onTap: testing ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: result == false ? 0.4 : 0.35)),
          color: result == true ? PrimeColors.primary.withValues(alpha: 0.06) : null,
        ),
        child: content,
      ),
    );
  }
}
