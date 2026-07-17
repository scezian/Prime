import 'dart:async';
import 'package:flutter/material.dart';
import '../services/biometric_auth.dart';
import '../services/secure_credentials.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';

class ControlScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ControlScreen({super.key, required this.apiClient});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  Map<String, dynamic>? _nowPlaying;
  int _volume = 0;
  bool _muted = false;
  double? _draggingVolume;
  int _brightness = 0;
  double? _draggingBrightness;
  int _kbdBacklight = 0;
  double? _draggingKbdBacklight;
  bool? _wifiEnabled;
  bool? _bluetoothEnabled;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadAll(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!widget.apiClient.isConfigured) {
      if (!silent) setState(() => _error = 'Not configured. Go to Settings first.');
      return;
    }
    try {
      final playing = await widget.apiClient.getNowPlaying();
      final vol = await widget.apiClient.getVolume();
      final brightness = await widget.apiClient.getBrightness();
      final kbdBacklight = await widget.apiClient.getKbdBacklight();
      if (!mounted) return;
      setState(() {
        _nowPlaying = playing;
        _volume = vol['volume'] as int;
        _muted = vol['muted'] as bool;
        if (_draggingBrightness == null) _brightness = brightness['percent'] as int;
        if (_draggingKbdBacklight == null) _kbdBacklight = kbdBacklight['percent'] as int;
        _error = null;
      });
    } catch (e) {
      if (!silent && mounted) setState(() => _error = e.toString());
    }

    // Radio status is best-effort and polled separately so a hiccup here
    // doesn't blank out the rest of the screen.
    try {
      final wifiRadio = await widget.apiClient.getWifiRadio();
      final btRadio = await widget.apiClient.getBluetoothRadio();
      if (!mounted) return;
      setState(() {
        _wifiEnabled = wifiRadio['enabled'] as bool;
        _bluetoothEnabled = btRadio['enabled'] as bool;
      });
    } catch (_) {
      // ignore — leave last known state
    }
  }

  Future<void> _playPause() async {
    try {
      await widget.apiClient.mediaPlayPause();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _next() async {
    try {
      await widget.apiClient.mediaNext();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _previous() async {
    try {
      await widget.apiClient.mediaPrevious();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onVolumeChangeEnd(double value) async {
    final level = value.round();
    setState(() {
      _volume = level;
      _draggingVolume = null;
    });
    try {
      await widget.apiClient.setVolume(level);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onBrightnessChangeEnd(double value) async {
    final level = value.round();
    setState(() {
      _brightness = level;
      _draggingBrightness = null;
    });
    try {
      await widget.apiClient.setBrightness(level);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onKbdBacklightChangeEnd(double value) async {
    setState(() => _draggingKbdBacklight = null);
    try {
      final res = await widget.apiClient.setKbdBacklight(value.round());
      setState(() => _kbdBacklight = res['percent'] as int);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleMute() async {
    try {
      final res = await widget.apiClient.toggleMute();
      setState(() {
        _volume = res['volume'] as int;
        _muted = res['muted'] as bool;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleWifiRadio(bool value) async {
    final previous = _wifiEnabled;
    setState(() => _wifiEnabled = value);
    try {
      await widget.apiClient.setWifiRadio(value);
    } catch (e) {
      if (mounted) {
        setState(() => _wifiEnabled = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleBluetoothRadio(bool value) async {
    final previous = _bluetoothEnabled;
    setState(() => _bluetoothEnabled = value);
    try {
      await widget.apiClient.setBluetoothRadio(value);
    } catch (e) {
      if (mounted) {
        setState(() => _bluetoothEnabled = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openWifiSheet() {
    _DevicePickerSheet.show(
      context: context,
      title: 'WIFI',
      icon: Icons.wifi,
      fetch: () => widget.apiClient.getWifiNetworks().then((r) => r['networks'] as List<dynamic>),
      connect: (item) => widget.apiClient.connectWifi(item['ssid'] as String),
      disconnect: (item) => widget.apiClient.disconnectWifi(),
      idOf: (item) => item['ssid'] as String,
      labelOf: (item) => item['ssid'] as String,
      connectedOf: (item) => item['connected'] == true,
      subtitleOf: (item) => '${item['signal']}%',
      emptyMessage: 'no known networks in range',
    );
  }

  void _openBluetoothSheet() {
    _DevicePickerSheet.show(
      context: context,
      title: 'BLUETOOTH',
      icon: Icons.bluetooth,
      fetch: () => widget.apiClient.getBluetoothDevices().then((r) => r['devices'] as List<dynamic>),
      connect: (item) => widget.apiClient.connectBluetooth(item['mac'] as String),
      disconnect: (item) => widget.apiClient.disconnectBluetooth(item['mac'] as String),
      idOf: (item) => item['mac'] as String,
      labelOf: (item) => item['name'] as String,
      connectedOf: (item) => item['connected'] == true,
      subtitleOf: (item) => item['mac'] as String,
      emptyMessage: 'no paired devices',
    );
  }

  void _openProcessSheet() {
    _ProcessKillSheet.show(context: context, apiClient: widget.apiClient);
  }

  @override
  Widget build(BuildContext context) {
    final displayVolume = _draggingVolume ?? _volume.toDouble();
    final displayBrightness = _draggingBrightness ?? _brightness.toDouble();
    final displayKbdBacklight = _draggingKbdBacklight ?? _kbdBacklight.toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Control')),
      body: RefreshIndicator(
        color: PrimeColors.primary,
        backgroundColor: PrimeColors.card,
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PrimeColors.destructive.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.3)),
                ),
                child: Text(_error!, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
              ),
            _NowPlayingCard(
              apiClient: widget.apiClient,
              nowPlaying: _nowPlaying,
              onPlayPause: _playPause,
              onNext: _next,
              onPrevious: _previous,
              formatTime: _formatTime,
            ),
            const SizedBox(height: 16),
            Text('VOLUME', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayVolume,
              leadingIcon: _muted ? Icons.volume_off : (displayVolume > 50 ? Icons.volume_up : Icons.volume_down),
              iconColor: _muted ? PrimeColors.destructive : PrimeColors.primary,
              activeColor: _muted ? PrimeColors.mutedForeground : PrimeColors.primary,
              onIconTap: _toggleMute,
              onChanged: (v) => setState(() => _draggingVolume = v),
              onChangeEnd: _onVolumeChangeEnd,
            ),
            const SizedBox(height: 16),
            Text('BRIGHTNESS', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayBrightness,
              leadingIcon: displayBrightness > 50 ? Icons.brightness_high : Icons.brightness_low,
              iconColor: PrimeColors.warning,
              activeColor: PrimeColors.warning,
              onIconTap: null,
              onChanged: (v) => setState(() => _draggingBrightness = v),
              onChangeEnd: _onBrightnessChangeEnd,
            ),
            const SizedBox(height: 16),
            Text('KEYBOARD BACKLIGHT', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayKbdBacklight,
              leadingIcon: Icons.keyboard,
              iconColor: PrimeColors.netAccent,
              activeColor: PrimeColors.netAccent,
              onIconTap: null,
              onChanged: (v) => setState(() => _draggingKbdBacklight = v),
              onChangeEnd: _onKbdBacklightChangeEnd,
            ),
            const SizedBox(height: 20),
            Text('NETWORK', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _RadioQuickButton(
                    icon: Icons.wifi,
                    label: 'WiFi',
                    color: PrimeColors.netAccent,
                    enabled: _wifiEnabled,
                    onTap: _openWifiSheet,
                    onToggle: _toggleWifiRadio,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RadioQuickButton(
                    icon: Icons.bluetooth,
                    label: 'Bluetooth',
                    color: PrimeColors.netAccent,
                    enabled: _bluetoothEnabled,
                    onTap: _openBluetoothSheet,
                    onToggle: _toggleBluetoothRadio,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('PROCESSES', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _openProcessSheet,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: PrimeColors.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.power_settings_new, size: 16, color: PrimeColors.destructive),
                    const SizedBox(width: 8),
                    Text('Terminate', style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, size: 16, color: PrimeColors.mutedForeground),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WiFi/Bluetooth tile: a switch flips the radio on/off directly, tapping
/// the rest of the tile opens the connect/disconnect picker sheet.
class _RadioQuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool? enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _RadioQuickButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final knownOff = enabled == false;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: PrimeColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(icon, size: 16, color: knownOff ? PrimeColors.mutedForeground : color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: enabled ?? false,
                onChanged: enabled == null ? null : onToggle,
                activeColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic confirm(-optional) + biometric + fire power action button. Reused
/// for Lock, Log Out, Restart, and Shutdown — `needsConfirm` mirrors the
/// daemon's own `needs_confirm` flag per command in commands.py.
/// `expectDaemonDeath` suppresses the error snackbar for commands where the
/// daemon dies before it can respond (reboot/shutdown).
class _PowerActionButton extends StatefulWidget {
  final ApiClient apiClient;
  final String commandId;
  final String label;
  final IconData icon;
  final bool needsConfirm;
  final bool expectDaemonDeath;

  const _PowerActionButton({
    required this.apiClient,
    required this.commandId,
    required this.label,
    required this.icon,
    required this.needsConfirm,
    this.expectDaemonDeath = false,
  });

  @override
  State<_PowerActionButton> createState() => _PowerActionButtonState();
}

class _PowerActionButtonState extends State<_PowerActionButton> {
  bool _confirm = false;
  bool _loading = false;

  Future<void> _handleTap() async {
    if (widget.needsConfirm && !_confirm) {
      setState(() => _confirm = true);
      return;
    }

    final authorized = await BiometricAuth.confirm('Confirm: ${widget.label}');
    if (!authorized) {
      if (mounted) setState(() => _confirm = false);
      return;
    }

    setState(() {
      _loading = true;
      _confirm = false;
    });
    try {
      await widget.apiClient.runCommand(widget.commandId);
    } catch (e) {
      if (!widget.expectDaemonDeath && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _loading ? null : _handleTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _confirm ? PrimeColors.destructive.withValues(alpha: 0.08) : PrimeColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.destructive),
              )
            else
              Icon(widget.icon, size: 18, color: PrimeColors.destructive),
            const SizedBox(height: 6),
            Text(
              _confirm ? 'confirm?' : widget.label,
              style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.destructive),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lock/Unlock toggle — same confirm+biometric+fire pattern as
/// _PowerActionButton, but the command id, label, icon, and confirm
/// requirement swap based on current lock state (reported by the daemon's
/// /power/lock-status). Unlocking bypasses the OS lock screen entirely, so
/// it always requires confirm regardless of the daemon's needs_confirm flag.
class _LockToggleButton extends StatefulWidget {
  final ApiClient apiClient;
  final bool? locked;
  final ValueChanged<bool> onChanged;

  const _LockToggleButton({
    required this.apiClient,
    required this.locked,
    required this.onChanged,
  });

  @override
  State<_LockToggleButton> createState() => _LockToggleButtonState();
}

class _LockToggleButtonState extends State<_LockToggleButton> {
  bool _confirm = false;
  bool _loading = false;

  Future<String?> _promptForPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text('Laptop Password', style: PrimeTheme.mono(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stored securely on this device only, never on the laptop.',
              style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: PrimeTheme.mono(fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('Cancel', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUnlock() async {
    final authorized = await BiometricAuth.confirm('Confirm: Unlock');
    if (!authorized) {
      if (mounted) setState(() => _confirm = false);
      return;
    }

    var password = await SecureCredentials.getUnlockPassword();
    if (password == null || password.isEmpty) {
      if (!mounted) return;
      password = await _promptForPassword();
      if (password == null || password.isEmpty) {
        if (mounted) setState(() => _confirm = false);
        return;
      }
      await SecureCredentials.setUnlockPassword(password);
    }

    setState(() {
      _loading = true;
      _confirm = false;
    });
    try {
      final res = await widget.apiClient.unlockScreen(password);
      final unlocked = res['unlocked'] == true;
      if (unlocked) {
        widget.onChanged(false);
      } else if (mounted) {
        // Not auto-clearing the saved password here: the daemon can't
        // reliably tell "wrong password" apart from "hyprlock hadn't
        // exited yet", so treating every failure as a bad password and
        // deleting it was too aggressive. Update it from Settings if it
        // actually is wrong.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlock failed — try again, or update the password in Settings')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLock() async {
    final authorized = await BiometricAuth.confirm('Confirm: Lock');
    if (!authorized) {
      if (mounted) setState(() => _confirm = false);
      return;
    }

    setState(() {
      _loading = true;
      _confirm = false;
    });
    try {
      await widget.apiClient.runCommand('lock-screen');
      widget.onChanged(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleTap() async {
    final isLocked = widget.locked ?? false;

    if (!_confirm) {
      setState(() => _confirm = true);
      return;
    }

    if (isLocked) {
      await _handleUnlock();
    } else {
      await _handleLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.locked ?? false;
    final icon = isLocked ? Icons.lock_open : Icons.lock_outline;
    final label = isLocked ? 'Unlock' : 'Lock';

    return InkWell(
      onTap: _loading ? null : _handleTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _confirm ? PrimeColors.destructive.withValues(alpha: 0.08) : PrimeColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.destructive),
              )
            else
              Icon(icon, size: 18, color: PrimeColors.destructive),
            const SizedBox(height: 6),
            Text(
              _confirm ? 'confirm?' : label,
              style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.destructive),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared bottom sheet for both WiFi networks and Bluetooth devices — lists
/// already-known items, tap to connect, tap the connected item to
/// disconnect (if a disconnect handler is provided). No password/pairing
/// UI by design.
class _ProcessKillSheet extends StatefulWidget {
  final ApiClient apiClient;
  const _ProcessKillSheet({required this.apiClient});

  static void show({required BuildContext context, required ApiClient apiClient}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PrimeColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _ProcessKillSheet(apiClient: apiClient),
    );
  }

  @override
  State<_ProcessKillSheet> createState() => _ProcessKillSheetState();
}

class _ProcessKillSheetState extends State<_ProcessKillSheet> {
  List<Map<String, dynamic>>? _processes;
  String? _error;
  int? _killingPid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiClient.getProcesses();
      final list = (res['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _processes = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _kill(int pid) async {
    setState(() => _killingPid = pid);
    try {
      await widget.apiClient.killProcess(pid);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _killingPid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.power_settings_new, size: 16, color: PrimeColors.destructive),
                  const SizedBox(width: 8),
                  Text('TERMINATE', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground, letterSpacing: 2)),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(_error!, style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.destructive))
              else if (_processes == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground)),
                )
              else if (_processes!.isEmpty)
                Text('no active processes', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _processes!.length,
                    itemBuilder: (context, index) {
                      final item = _processes![index];
                      final pid = item['pid'] as int;
                      final name = item['name'] as String;
                      final title = item['title'] as String? ?? '';
                      final killing = _killingPid == pid;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: PrimeColors.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: PrimeColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: PrimeTheme.mono(fontSize: 13)),
                                    if (title.isNotEmpty && title != name) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (killing)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.destructive),
                                )
                              else
                                InkWell(
                                  onTap: () => _kill(pid),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close, size: 18, color: PrimeColors.destructive),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DevicePickerSheet extends StatefulWidget {
  final String title;
  final IconData icon;
  final Future<List<dynamic>> Function() fetch;
  final Future<dynamic> Function(Map<String, dynamic> item) connect;
  final Future<dynamic> Function(Map<String, dynamic> item)? disconnect;
  final String Function(Map<String, dynamic> item) idOf;
  final String Function(Map<String, dynamic> item) labelOf;
  final String Function(Map<String, dynamic> item) subtitleOf;
  final bool Function(Map<String, dynamic> item) connectedOf;
  final String emptyMessage;

  const _DevicePickerSheet({
    required this.title,
    required this.icon,
    required this.fetch,
    required this.connect,
    this.disconnect,
    required this.idOf,
    required this.labelOf,
    required this.subtitleOf,
    required this.connectedOf,
    required this.emptyMessage,
  });

  static void show({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Future<List<dynamic>> Function() fetch,
    required Future<dynamic> Function(Map<String, dynamic> item) connect,
    Future<dynamic> Function(Map<String, dynamic> item)? disconnect,
    required String Function(Map<String, dynamic> item) idOf,
    required String Function(Map<String, dynamic> item) labelOf,
    required String Function(Map<String, dynamic> item) subtitleOf,
    required bool Function(Map<String, dynamic> item) connectedOf,
    required String emptyMessage,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PrimeColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _DevicePickerSheet(
        title: title,
        icon: icon,
        fetch: fetch,
        connect: connect,
        disconnect: disconnect,
        idOf: idOf,
        labelOf: labelOf,
        subtitleOf: subtitleOf,
        connectedOf: connectedOf,
        emptyMessage: emptyMessage,
      ),
    );
  }

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String? _connectingId;
  String? _disconnectingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.fetch();
      if (!mounted) return;
      setState(() {
        _items = items.cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _handleConnect(Map<String, dynamic> item) async {
    final id = widget.idOf(item);
    setState(() => _connectingId = id);
    try {
      await widget.connect(item);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  Future<void> _handleDisconnect(Map<String, dynamic> item) async {
    final disconnect = widget.disconnect;
    if (disconnect == null) return;
    final id = widget.idOf(item);
    setState(() => _disconnectingId = id);
    try {
      await disconnect(item);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _disconnectingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, size: 16, color: PrimeColors.netAccent),
                  const SizedBox(width: 8),
                  Text(widget.title, style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground, letterSpacing: 2)),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(_error!, style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.destructive))
              else if (_items == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground)),
                )
              else if (_items!.isEmpty)
                Text(widget.emptyMessage, style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _items!.length,
                    itemBuilder: (context, index) {
                      final item = _items![index];
                      final id = widget.idOf(item);
                      final connected = widget.connectedOf(item);
                      final connecting = _connectingId == id;
                      final disconnecting = _disconnectingId == id;
                      final canDisconnect = connected && widget.disconnect != null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: connecting || disconnecting
                              ? null
                              : connected
                                  ? (canDisconnect ? () => _handleDisconnect(item) : null)
                                  : () => _handleConnect(item),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: PrimeColors.card,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PrimeColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(widget.labelOf(item), style: PrimeTheme.mono(fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text(widget.subtitleOf(item), style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground)),
                                    ],
                                  ),
                                ),
                                if (connecting || disconnecting)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground),
                                  )
                                else if (connected)
                                  Text(
                                    canDisconnect ? 'disconnect' : 'connected',
                                    style: PrimeTheme.mono(
                                      fontSize: 10,
                                      color: canDisconnect ? PrimeColors.destructive : PrimeColors.primary,
                                    ),
                                  )
                                else
                                  Text('connect', style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.netAccent)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  final double value;
  final IconData leadingIcon;
  final Color iconColor;
  final Color activeColor;
  final VoidCallback? onIconTap;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderCard({
    required this.value,
    required this.leadingIcon,
    required this.iconColor,
    required this.activeColor,
    required this.onIconTap,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onIconTap,
            child: Icon(leadingIcon, size: 16, color: iconColor),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor,
                inactiveTrackColor: PrimeColors.secondary,
                thumbColor: activeColor,
                overlayColor: activeColor.withValues(alpha: 0.1),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(0, 100),
                min: 0,
                max: 100,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.right,
              style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatefulWidget {
  final ApiClient apiClient;
  final Map<String, dynamic>? nowPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final String Function(int) formatTime;

  const _NowPlayingCard({
    required this.apiClient,
    required this.nowPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.formatTime,
  });

  @override
  State<_NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<_NowPlayingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    if (playing && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!playing && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  Widget _buildArt(String? artUrl) {
    const size = 64.0;
    final proxied = widget.apiClient.proxiedArtRequest(artUrl);

    Widget fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: PrimeColors.secondary, shape: BoxShape.circle),
      child: const Icon(Icons.music_note, color: PrimeColors.mutedForeground, size: 24),
    );

    ImageProvider? provider;
    if (proxied != null) {
      provider = NetworkImage(proxied.url, headers: proxied.headers);
    } else if (artUrl != null && artUrl.startsWith('http')) {
      provider = NetworkImage(artUrl);
    }

    if (provider == null) return fallback;

    return ClipOval(
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowPlaying = widget.nowPlaying;
    final active = nowPlaying?['active'] == true;
    final playing = nowPlaying?['status'] == 'Playing';
    _syncSpin(playing);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: !active
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('nothing playing', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground)),
              ),
            )
          : Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RotationTransition(
                      turns: _spinController,
                      child: _buildArt(nowPlaying!['art_url'] as String?),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (nowPlaying['title'] as String?)?.isNotEmpty == true ? nowPlaying['title'] : 'unknown title',
                            style: PrimeTheme.mono(fontSize: 15, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [nowPlaying['artist'], nowPlaying['album']]
                                .where((s) => s != null && (s as String).isNotEmpty)
                                .join(' — '),
                            style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if ((nowPlaying['duration_seconds'] as int? ?? 0) > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (nowPlaying['position_seconds'] as int) / (nowPlaying['duration_seconds'] as int),
                      minHeight: 3,
                      backgroundColor: PrimeColors.secondary,
                      valueColor: const AlwaysStoppedAnimation(PrimeColors.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.formatTime(nowPlaying['position_seconds'] as int),
                          style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
                      Text(widget.formatTime(nowPlaying['duration_seconds'] as int),
                          style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.onPrevious,
                      icon: const Icon(Icons.skip_previous, color: PrimeColors.foreground),
                      iconSize: 26,
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: widget.onPlayPause,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: PrimeColors.primary, shape: BoxShape.circle),
                        child: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: PrimeColors.primaryForeground,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: widget.onNext,
                      icon: const Icon(Icons.skip_next, color: PrimeColors.foreground),
                      iconSize: 26,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
