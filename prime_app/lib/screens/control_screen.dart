import 'dart:async';
import 'package:flutter/material.dart';
import '../services/biometric_auth.dart';
import '../widgets/liquid_confirm_button.dart';
import '../services/secure_credentials.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';
import 'touchpad_screen.dart';

class ControlScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ControlScreen({super.key, required this.apiClient});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
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
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadAll(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!widget.apiClient.isConfigured) {
      if (!silent)
        setState(() => _error = 'Not configured. Go to Settings first.');
      return;
    }
    try {
      final vol = await widget.apiClient.getVolume();
      final brightness = await widget.apiClient.getBrightness();
      final kbdBacklight = await widget.apiClient.getKbdBacklight();
      if (!mounted) return;
      setState(() {
        _volume = vol['volume'] as int;
        _muted = vol['muted'] as bool;
        if (_draggingBrightness == null)
          _brightness = brightness['percent'] as int;
        if (_draggingKbdBacklight == null)
          _kbdBacklight = kbdBacklight['percent'] as int;
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

  Future<void> _onVolumeChangeEnd(double value) async {
    final level = value.round();
    setState(() {
      _volume = level;
      _draggingVolume = null;
    });
    try {
      await widget.apiClient.setVolume(level);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onKbdBacklightChangeEnd(double value) async {
    setState(() => _draggingKbdBacklight = null);
    try {
      final res = await widget.apiClient.setKbdBacklight(value.round());
      setState(() => _kbdBacklight = res['percent'] as int);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleWifiRadio(bool value) async {
    final previous = _wifiEnabled;
    setState(() => _wifiEnabled = value);
    try {
      await widget.apiClient.setWifiRadio(value);
    } catch (e) {
      if (mounted) {
        setState(() => _wifiEnabled = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openWifiSheet() {
    _DevicePickerSheet.show(
      context: context,
      title: 'WIFI',
      icon: Icons.wifi,
      fetch: () => widget.apiClient.getWifiNetworks().then(
        (r) => r['networks'] as List<dynamic>,
      ),
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
      fetch: () => widget.apiClient.getBluetoothDevices().then(
        (r) => r['devices'] as List<dynamic>,
      ),
      connect: (item) =>
          widget.apiClient.connectBluetooth(item['mac'] as String),
      disconnect: (item) =>
          widget.apiClient.disconnectBluetooth(item['mac'] as String),
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
    final displayKbdBacklight =
        _draggingKbdBacklight ?? _kbdBacklight.toDouble();

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
                  border: Border.all(
                    color: PrimeColors.destructive.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _error!,
                  style: PrimeTheme.mono(
                    color: PrimeColors.destructive,
                    fontSize: 12,
                  ),
                ),
              ),
            Text(
              'VOLUME',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayVolume,
              leadingIcon: _muted
                  ? Icons.volume_off
                  : (displayVolume > 50 ? Icons.volume_up : Icons.volume_down),
              iconColor: _muted ? PrimeColors.destructive : PrimeColors.primary,
              activeColor: _muted
                  ? PrimeColors.mutedForeground
                  : PrimeColors.primary,
              onIconTap: _toggleMute,
              onChanged: (v) => setState(() => _draggingVolume = v),
              onChangeEnd: _onVolumeChangeEnd,
            ),
            const SizedBox(height: 16),
            Text(
              'BRIGHTNESS',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayBrightness,
              leadingIcon: displayBrightness > 50
                  ? Icons.brightness_high
                  : Icons.brightness_low,
              iconColor: PrimeColors.warning,
              activeColor: PrimeColors.warning,
              onIconTap: null,
              onChanged: (v) => setState(() => _draggingBrightness = v),
              onChangeEnd: _onBrightnessChangeEnd,
            ),
            const SizedBox(height: 16),
            Text(
              'KEYBOARD BACKLIGHT',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
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
            Text(
              'NETWORK',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
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
            Text(
              'QUICK ACTIONS',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.mouse_outlined,
                    label: 'Touchpad',
                    color: PrimeColors.primary,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TouchpadScreen(apiClient: widget.apiClient),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.power_settings_new,
                    label: 'Terminate',
                    color: PrimeColors.destructive,
                    onTap: _openProcessSheet,
                  ),
                ),
              ],
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
                  Icon(
                    icon,
                    size: 16,
                    color: knownOff ? PrimeColors.mutedForeground : color,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: PrimeTheme.mono(
                        fontSize: 10,
                        color: PrimeColors.mutedForeground,
                      ),
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

/// Compact tile matching the WiFi/Bluetooth row style — used for quick
/// actions (Touchpad, Terminate) that don't have an on/off state, just a
/// tap target with a chevron instead of a switch.
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: PrimeTheme.mono(
                  fontSize: 10,
                  color: PrimeColors.mutedForeground,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: PrimeColors.mutedForeground,
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
class _PowerActionButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LiquidConfirmButton(
      apiClient: apiClient,
      commandId: commandId,
      label: label,
      icon: icon,
      needsConfirm: needsConfirm,
      expectDaemonDeath: expectDaemonDeath,
      variant: LiquidButtonVariant.outlined,
    );
  }
}

/// Lock/Unlock toggle — same confirm+biometric+fire pattern as
/// _PowerActionButton, but the command id, label, icon, and confirm
/// requirement swap based on current lock state (reported by the daemon's
/// /power/lock-status). Unlocking bypasses the OS lock screen entirely, so
/// it always requires confirm regardless of the daemon's needs_confirm flag.
class _LockToggleButton extends StatelessWidget {
  final ApiClient apiClient;
  final bool? locked;
  final ValueChanged<bool> onChanged;
  const _LockToggleButton({
    required this.apiClient,
    required this.locked,
    required this.onChanged,
  });

  Future<String?> _promptForPassword(BuildContext context) {
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
              style: PrimeTheme.mono(
                fontSize: 11,
                color: PrimeColors.mutedForeground,
              ),
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
            child: Text(
              'Cancel',
              style: PrimeTheme.mono(
                fontSize: 12,
                color: PrimeColors.mutedForeground,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(
              'Save',
              style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unlock(BuildContext context) async {
    var password = await SecureCredentials.getUnlockPassword();
    if (password == null || password.isEmpty) {
      if (!context.mounted) return;
      password = await _promptForPassword(context);
      if (password == null || password.isEmpty) return;
      await SecureCredentials.setUnlockPassword(password);
    }
    final res = await apiClient.unlockScreen(password);
    final unlocked = res['unlocked'] == true;
    if (unlocked) {
      onChanged(false);
    } else if (context.mounted) {
      // Not auto-clearing the saved password here: the daemon can't
      // reliably tell "wrong password" apart from "hyprlock hadn't
      // exited yet", so treating every failure as a bad password and
      // deleting it was too aggressive. Update it from Settings if it
      // actually is wrong.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unlock failed — try again, or update the password in Settings',
          ),
        ),
      );
    }
  }

  Future<void> _lock(BuildContext context) async {
    await apiClient.runCommand('lock-screen');
    onChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = locked ?? false;
    return LiquidConfirmButton(
      key: ValueKey(isLocked),
      label: isLocked ? 'Unlock' : 'Lock',
      icon: isLocked ? Icons.lock_open : Icons.lock_outline,
      onConfirmed: (ctx) => isLocked ? _unlock(ctx) : _lock(ctx),
      variant: LiquidButtonVariant.outlined,
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

  static void show({
    required BuildContext context,
    required ApiClient apiClient,
  }) {
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
      final list = (res['processes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
                  const Icon(
                    Icons.power_settings_new,
                    size: 16,
                    color: PrimeColors.destructive,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TERMINATE',
                    style: PrimeTheme.mono(
                      fontSize: 12,
                      color: PrimeColors.mutedForeground,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(
                  _error!,
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.destructive,
                  ),
                )
              else if (_processes == null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PrimeColors.mutedForeground,
                    ),
                  ),
                )
              else if (_processes!.isEmpty)
                Text(
                  'no active processes',
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.mutedForeground,
                  ),
                )
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
                                    Text(
                                      name,
                                      style: PrimeTheme.mono(fontSize: 13),
                                    ),
                                    if (title.isNotEmpty && title != name) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PrimeTheme.mono(
                                          fontSize: 10,
                                          color: PrimeColors.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (killing)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: PrimeColors.destructive,
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: () => _kill(pid),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: PrimeColors.destructive,
                                    ),
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
                  Text(
                    widget.title,
                    style: PrimeTheme.mono(
                      fontSize: 12,
                      color: PrimeColors.mutedForeground,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(
                  _error!,
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.destructive,
                  ),
                )
              else if (_items == null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PrimeColors.mutedForeground,
                    ),
                  ),
                )
              else if (_items!.isEmpty)
                Text(
                  widget.emptyMessage,
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.mutedForeground,
                  ),
                )
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
                      final canDisconnect =
                          connected && widget.disconnect != null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: connecting || disconnecting
                              ? null
                              : connected
                              ? (canDisconnect
                                    ? () => _handleDisconnect(item)
                                    : null)
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.labelOf(item),
                                        style: PrimeTheme.mono(fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.subtitleOf(item),
                                        style: PrimeTheme.mono(
                                          fontSize: 10,
                                          color: PrimeColors.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (connecting || disconnecting)
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: PrimeColors.mutedForeground,
                                    ),
                                  )
                                else if (connected)
                                  Text(
                                    canDisconnect ? 'disconnect' : 'connected',
                                    style: PrimeTheme.mono(
                                      fontSize: 10,
                                      color: canDisconnect
                                          ? PrimeColors.destructive
                                          : PrimeColors.primary,
                                    ),
                                  )
                                else
                                  Text(
                                    'connect',
                                    style: PrimeTheme.mono(
                                      fontSize: 10,
                                      color: PrimeColors.netAccent,
                                    ),
                                  ),
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
              style: PrimeTheme.mono(
                fontSize: 11,
                color: PrimeColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
