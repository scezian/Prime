import 'dart:async';
import 'dart:math' as math;
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
    _WifiStatusSheet.show(context: context, apiClient: widget.apiClient);
  }

  void _openBluetoothSheet() {
    _BluetoothStatusSheet.show(context: context, apiClient: widget.apiClient);
  }

  void _openProcessSheet() {
    _ProcessKillSheet.show(context: context, apiClient: widget.apiClient);
  }

  void _openAudioMixerSheet() {
    _AudioMixerSheet.show(context: context, apiClient: widget.apiClient);
  }

  void _openDisplaySheet() {
    _DisplaySheet.show(context: context, apiClient: widget.apiClient);
  }

  @override
  Widget build(BuildContext context) {
    final displayVolume = _draggingVolume ?? _volume.toDouble();

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
              'SYSTEM',
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
                    icon: _muted
                        ? Icons.volume_off
                        : (displayVolume > 50
                              ? Icons.volume_up
                              : Icons.volume_down),
                    label: 'Audio',
                    color: PrimeColors.primary,
                    onTap: _openAudioMixerSheet,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.brightness_6,
                    label: 'Display',
                    color: PrimeColors.warning,
                    onTap: _openDisplaySheet,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: PrimeColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: PrimeTheme.mono(
                  fontSize: 12,
                  color: PrimeColors.mutedForeground,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              size: 16,
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

class _WifiStatusSheet extends StatefulWidget {
  final ApiClient apiClient;

  const _WifiStatusSheet({required this.apiClient});

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
      builder: (_) => _WifiStatusSheet(apiClient: apiClient),
    );
  }

  @override
  State<_WifiStatusSheet> createState() => _WifiStatusSheetState();
}

enum _WifiSheetMode { status, scan }

class _WifiStatusSheetState extends State<_WifiStatusSheet> {
  _WifiSheetMode _mode = _WifiSheetMode.status;

  Map<String, dynamic>? _info;
  String? _infoError;
  bool _infoLoading = true;

  List<Map<String, dynamic>>? _networks;
  String? _networksError;
  String? _connectingSsid;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() => _infoLoading = true);
    try {
      final info = await widget.apiClient.getWifiConnectionInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _infoError = null;
        _infoLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _infoError = e.toString();
        _infoLoading = false;
      });
    }
  }

  Future<void> _loadNetworks() async {
    try {
      final res = await widget.apiClient.getWifiNetworks();
      if (!mounted) return;
      setState(() {
        _networks = (res['networks'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _networksError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _networksError = e.toString());
    }
  }

  void _enterScanMode() {
    setState(() {
      _mode = _WifiSheetMode.scan;
      _networks = null;
      _networksError = null;
    });
    _loadNetworks();
  }

  Future<void> _handleTapNetwork(Map<String, dynamic> item) async {
    final ssid = item['ssid'] as String;
    final connected = item['connected'] == true;
    setState(() => _connectingSsid = ssid);
    try {
      if (connected) {
        await widget.apiClient.disconnectWifi();
      } else {
        await widget.apiClient.connectWifi(ssid);
      }
      await _loadInfo();
      if (!mounted) return;
      setState(() {
        _mode = _WifiSheetMode.status;
        _connectingSsid = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _connectingSsid = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PrimeColors.netAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: PrimeTheme.text(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: PrimeTheme.text(
                    fontSize: 10,
                    color: PrimeColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusView() {
    if (_infoLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_infoError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          _infoError!,
          style: PrimeTheme.text(color: PrimeColors.destructive, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_info?['connected'] != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.wifi_off, size: 40, color: PrimeColors.mutedForeground),
            const SizedBox(height: 12),
            Text(
              'not connected to WiFi',
              style: PrimeTheme.text(
                color: PrimeColors.mutedForeground,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    final info = _info!;
    return Column(
      key: const ValueKey('status'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: PrimeGradients.tileA,
            boxShadow: PrimeShadows.tile,
          ),
          child: const Icon(Icons.wifi, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          info['ssid'] as String,
          style: PrimeTheme.text(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Connected',
          style: PrimeTheme.text(fontSize: 12, color: PrimeColors.success),
        ),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: [
            _infoTile(
              Icons.settings_input_antenna,
              'Band',
              info['band'] as String? ?? '—',
            ),
            _infoTile(
              Icons.language,
              'IP Address',
              info['ip_address'] as String? ?? '—',
            ),
            _infoTile(
              Icons.lock_outline,
              'Security',
              info['security'] as String? ?? '—',
            ),
            _infoTile(
              Icons.signal_cellular_alt,
              'Signal',
              '${info['signal']}%',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScanView() {
    if (_networksError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          _networksError!,
          style: PrimeTheme.text(color: PrimeColors.destructive, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_networks == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_networks!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'no known networks in range',
          style: PrimeTheme.text(
            color: PrimeColors.mutedForeground,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      key: const ValueKey('scan'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _OrbitView(
          items: _networks!.take(7).toList(),
          idOf: (item) => item['ssid'] as String,
          labelOf: (item) => item['ssid'] as String,
          subtitleOf: (item) => '${item['signal']}%',
          connectedOf: (item) => item['connected'] == true,
          icon: Icons.wifi,
          centerIcon: Icons.smartphone,
          busyId: _connectingSsid,
          onTap: _handleTapNetwork,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: PrimeColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.wifi, size: 16, color: PrimeColors.netAccent),
                const SizedBox(width: 8),
                Text(
                  'WIFI',
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.mutedForeground,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 380,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _mode == _WifiSheetMode.status
                      ? _buildStatusView()
                      : _buildScanView(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _mode == _WifiSheetMode.status
                    ? _enterScanMode
                    : () => setState(() => _mode = _WifiSheetMode.status),
                icon: Icon(
                  _mode == _WifiSheetMode.status ? Icons.search : Icons.close,
                  size: 16,
                ),
                label: Text(
                  _mode == _WifiSheetMode.status ? 'Scan networks' : 'Back',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PrimeColors.primary,
                  side: BorderSide(color: PrimeColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nearby known networks arranged in a circle around a central "you are
/// here" phone icon -- a radar-style scan view instead of a flat list.
/// Items arranged in a loose circle around a central "you are here" icon,
/// each node gently drifting in angle and radius (out of sync per node)
/// so the whole thing reads as alive rather than a static, perfectly
/// even ring. Shared by both the WiFi and Bluetooth scan views.
class _OrbitView extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic> item) idOf;
  final String Function(Map<String, dynamic> item) labelOf;
  final String Function(Map<String, dynamic> item) subtitleOf;
  final bool Function(Map<String, dynamic> item) connectedOf;
  final IconData icon;
  final IconData centerIcon;
  final String? busyId;
  final void Function(Map<String, dynamic> item) onTap;

  const _OrbitView({
    required this.items,
    required this.idOf,
    required this.labelOf,
    required this.subtitleOf,
    required this.connectedOf,
    required this.icon,
    required this.centerIcon,
    required this.busyId,
    required this.onTap,
  });

  @override
  State<_OrbitView> createState() => _OrbitViewState();
}

class _OrbitViewState extends State<_OrbitView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const double _canvasSize = 300;
  static const double _centerSize = 76;
  static const double _baseRadius = 108;
  static const double _nodeSize = 66;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    return SizedBox(
      width: _canvasSize,
      height: _canvasSize,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value * 2 * math.pi;
          final points = List.generate(count, (i) {
            final baseAngle = -math.pi / 2 + (2 * math.pi * i / count);
            final phase = i * 2.4;
            final angle = baseAngle + math.sin(t + phase) * 0.16;
            final radius = _baseRadius + math.sin(t * 1.3 + phase) * 12;
            return Offset(radius * math.cos(angle), radius * math.sin(angle));
          });
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(_canvasSize, _canvasSize),
                painter: _OrbitLinesPainter(
                  points: points,
                  color: PrimeColors.border,
                ),
              ),
              ...List.generate(count, (i) {
                final item = widget.items[i];
                final id = widget.idOf(item);
                final connected = widget.connectedOf(item);
                final busy = widget.busyId == id;
                final pos = points[i];
                return Positioned(
                  left: _canvasSize / 2 + pos.dx - _nodeSize / 2,
                  top: _canvasSize / 2 + pos.dy - _nodeSize / 2,
                  child: GestureDetector(
                    onTap: busy ? null : () => widget.onTap(item),
                    child: Container(
                      width: _nodeSize,
                      height: _nodeSize,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: PrimeColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: connected
                              ? PrimeColors.primary
                              : PrimeColors.border,
                          width: connected ? 2 : 1,
                        ),
                        boxShadow: PrimeShadows.card,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              widget.icon,
                              size: 16,
                              color: connected
                                  ? PrimeColors.primary
                                  : PrimeColors.netAccent,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            widget.labelOf(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PrimeTheme.text(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.subtitleOf(item),
                            style: PrimeTheme.mono(
                              fontSize: 7,
                              color: PrimeColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Container(
                width: _centerSize,
                height: _centerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: PrimeGradients.tileA,
                  boxShadow: PrimeShadows.tile,
                ),
                child: Icon(widget.centerIcon, color: Colors.white, size: 30),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrbitLinesPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  _OrbitLinesPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final p in points) {
      canvas.drawLine(center, center + p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitLinesPainter old) => true;
}

class _BluetoothStatusSheet extends StatefulWidget {
  final ApiClient apiClient;

  const _BluetoothStatusSheet({required this.apiClient});

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
      builder: (_) => _BluetoothStatusSheet(apiClient: apiClient),
    );
  }

  @override
  State<_BluetoothStatusSheet> createState() => _BluetoothStatusSheetState();
}

class _BluetoothStatusSheetState extends State<_BluetoothStatusSheet> {
  _WifiSheetMode _mode = _WifiSheetMode.status;

  List<Map<String, dynamic>>? _devices;
  String? _error;
  String? _connectingMac;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiClient.getBluetoothDevices();
      if (!mounted) return;
      setState(() {
        _devices = (res['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Map<String, dynamic>? get _connectedDevice {
    final devices = _devices;
    if (devices == null) return null;
    for (final d in devices) {
      if (d['connected'] == true) return d;
    }
    return null;
  }

  void _enterScanMode() {
    setState(() => _mode = _WifiSheetMode.scan);
    _load();
  }

  Future<void> _handleTapDevice(Map<String, dynamic> item) async {
    final mac = item['mac'] as String;
    final connected = item['connected'] == true;
    setState(() => _connectingMac = mac);
    try {
      if (connected) {
        await widget.apiClient.disconnectBluetooth(mac);
      } else {
        await widget.apiClient.connectBluetooth(mac);
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _mode = _WifiSheetMode.status;
        _connectingMac = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _connectingMac = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PrimeColors.netAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: PrimeTheme.text(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: PrimeTheme.text(
                    fontSize: 10,
                    color: PrimeColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusView() {
    if (_devices == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          _error!,
          style: PrimeTheme.text(color: PrimeColors.destructive, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    final device = _connectedDevice;
    if (device == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 40,
              color: PrimeColors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              'no device connected',
              style: PrimeTheme.text(
                color: PrimeColors.mutedForeground,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('status'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: PrimeGradients.tileA,
            boxShadow: PrimeShadows.tile,
          ),
          child: const Icon(Icons.bluetooth, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          device['name'] as String,
          style: PrimeTheme.text(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Connected',
          style: PrimeTheme.text(fontSize: 12, color: PrimeColors.success),
        ),
        const SizedBox(height: 20),
        _infoTile(Icons.tag, 'Address', device['mac'] as String),
      ],
    );
  }

  Widget _buildScanView() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          _error!,
          style: PrimeTheme.text(color: PrimeColors.destructive, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_devices == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_devices!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'no paired devices',
          style: PrimeTheme.text(
            color: PrimeColors.mutedForeground,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      key: const ValueKey('scan'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _OrbitView(
          items: _devices!.take(7).toList(),
          idOf: (item) => item['mac'] as String,
          labelOf: (item) => item['name'] as String,
          subtitleOf: (item) => item['mac'] as String,
          connectedOf: (item) => item['connected'] == true,
          icon: Icons.bluetooth,
          centerIcon: Icons.smartphone,
          busyId: _connectingMac,
          onTap: _handleTapDevice,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: PrimeColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.bluetooth, size: 16, color: PrimeColors.netAccent),
                const SizedBox(width: 8),
                Text(
                  'BLUETOOTH',
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.mutedForeground,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 380,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _mode == _WifiSheetMode.status
                      ? _buildStatusView()
                      : _buildScanView(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _mode == _WifiSheetMode.status
                    ? _enterScanMode
                    : () => setState(() => _mode = _WifiSheetMode.status),
                icon: Icon(
                  _mode == _WifiSheetMode.status ? Icons.search : Icons.close,
                  size: 16,
                ),
                label: Text(
                  _mode == _WifiSheetMode.status ? 'Scan devices' : 'Back',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PrimeColors.primary,
                  side: BorderSide(color: PrimeColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioButtonCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _AudioButtonCard({
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PrimeColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  'AUDIO MIXER',
                  style: PrimeTheme.mono(
                    fontSize: 11,
                    color: PrimeColors.mutedForeground,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioMixerSheet extends StatefulWidget {
  final ApiClient apiClient;
  const _AudioMixerSheet({required this.apiClient});

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
      builder: (_) => _AudioMixerSheet(apiClient: apiClient),
    );
  }

  @override
  State<_AudioMixerSheet> createState() => _AudioMixerSheetState();
}

class _AudioMixerSheetState extends State<_AudioMixerSheet> {
  List<Map<String, dynamic>>? _apps;
  String? _error;
  final Map<int, double> _dragging = {};
  int? _masterVolume;
  bool _masterMuted = false;
  double? _draggingMaster;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiClient.getAudioApps();
      final list = (res['apps'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _apps = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }

    try {
      final vol = await widget.apiClient.getVolume();
      if (!mounted) return;
      setState(() {
        _masterVolume = vol['volume'] as int;
        _masterMuted = vol['muted'] as bool;
      });
    } catch (_) {
      // Master volume is best-effort; leave last known state.
    }
  }

  Future<void> _onMasterChangeEnd(double value) async {
    final level = value.round();
    try {
      await widget.apiClient.setVolume(level);
      if (!mounted) return;
      setState(() {
        _draggingMaster = null;
        _masterVolume = level;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _draggingMaster = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleMasterMute() async {
    try {
      final res = await widget.apiClient.toggleMute();
      if (!mounted) return;
      setState(() => _masterMuted = res['muted'] as bool);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onChangeEnd(int index, double value) async {
    final level = value.round();
    try {
      await widget.apiClient.setAppVolume(index, level);
      if (!mounted) return;
      setState(() {
        _dragging.remove(index);
        final app = _apps?.firstWhere(
          (a) => a['index'] == index,
          orElse: () => {},
        );
        if (app != null && app.isNotEmpty) app['volume'] = level;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _dragging.remove(index));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleMute(int index) async {
    try {
      final res = await widget.apiClient.toggleAppMute(index);
      if (!mounted) return;
      setState(() {
        final app = _apps?.firstWhere(
          (a) => a['index'] == index,
          orElse: () => {},
        );
        if (app != null && app.isNotEmpty) {
          app['muted'] = res['muted'] ?? !(app['muted'] as bool);
        }
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
                  Icon(Icons.tune, size: 16, color: PrimeColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'AUDIO MIXER',
                    style: PrimeTheme.mono(
                      fontSize: 12,
                      color: PrimeColors.mutedForeground,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_masterVolume != null) ...[
                Text(
                  'MASTER',
                  style: PrimeTheme.mono(
                    fontSize: 9,
                    color: PrimeColors.mutedForeground,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final displayMaster =
                        _draggingMaster ?? _masterVolume!.toDouble();
                    return _SliderCard(
                      value: displayMaster,
                      leadingIcon: _masterMuted
                          ? Icons.volume_off
                          : (displayMaster > 50
                                ? Icons.volume_up
                                : Icons.volume_down),
                      iconColor: _masterMuted
                          ? PrimeColors.destructive
                          : PrimeColors.primary,
                      activeColor: _masterMuted
                          ? PrimeColors.mutedForeground
                          : PrimeColors.primary,
                      onIconTap: _toggleMasterMute,
                      onChanged: (v) => setState(() => _draggingMaster = v),
                      onChangeEnd: _onMasterChangeEnd,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'APPS',
                  style: PrimeTheme.mono(
                    fontSize: 9,
                    color: PrimeColors.mutedForeground,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: PrimeTheme.mono(
                    fontSize: 12,
                    color: PrimeColors.destructive,
                  ),
                )
              else if (_apps == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PrimeColors.mutedForeground,
                    ),
                  ),
                )
              else if (_apps!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No apps are playing audio.',
                    style: PrimeTheme.mono(
                      fontSize: 12,
                      color: PrimeColors.mutedForeground,
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final app in _apps!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Builder(
                              builder: (context) {
                                final index = app['index'] as int;
                                final muted = app['muted'] as bool;
                                final baseVolume = (app['volume'] as num)
                                    .toDouble();
                                final displayVolume =
                                    _dragging[index] ?? baseVolume;
                                final name =
                                    app['name'] as String? ?? 'Unknown';
                                final subtitle =
                                    (app['subtitle'] as String?) ?? '';

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.podcasts,
                                          size: 14,
                                          color: PrimeColors.mutedForeground,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: PrimeTheme.mono(
                                                  fontSize: 12,
                                                  color: PrimeColors.foreground,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (subtitle.isNotEmpty)
                                                Text(
                                                  subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: PrimeTheme.mono(
                                                    fontSize: 10,
                                                    color: PrimeColors
                                                        .mutedForeground,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _SliderCard(
                                      value: displayVolume,
                                      leadingIcon: muted
                                          ? Icons.volume_off
                                          : (displayVolume > 50
                                                ? Icons.volume_up
                                                : Icons.volume_down),
                                      iconColor: muted
                                          ? PrimeColors.destructive
                                          : PrimeColors.primary,
                                      activeColor: muted
                                          ? PrimeColors.mutedForeground
                                          : PrimeColors.primary,
                                      onIconTap: () => _toggleMute(index),
                                      onChanged: (v) =>
                                          setState(() => _dragging[index] = v),
                                      onChangeEnd: (v) =>
                                          _onChangeEnd(index, v),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
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

class _DisplaySheet extends StatefulWidget {
  final ApiClient apiClient;
  const _DisplaySheet({required this.apiClient});

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
      builder: (_) => _DisplaySheet(apiClient: apiClient),
    );
  }

  @override
  State<_DisplaySheet> createState() => _DisplaySheetState();
}

class _DisplaySheetState extends State<_DisplaySheet> {
  int? _brightness;
  int? _kbdBacklight;
  double? _draggingBrightness;
  double? _draggingKbdBacklight;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final brightness = await widget.apiClient.getBrightness();
      final kbdBacklight = await widget.apiClient.getKbdBacklight();
      if (!mounted) return;
      setState(() {
        _brightness = brightness['percent'] as int;
        _kbdBacklight = kbdBacklight['percent'] as int;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _onBrightnessChangeEnd(double value) async {
    final level = value.round();
    try {
      await widget.apiClient.setBrightness(level);
      if (!mounted) return;
      setState(() {
        _draggingBrightness = null;
        _brightness = level;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _draggingBrightness = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _onKbdBacklightChangeEnd(double value) async {
    try {
      final res = await widget.apiClient.setKbdBacklight(value.round());
      if (!mounted) return;
      setState(() {
        _draggingKbdBacklight = null;
        _kbdBacklight = res['percent'] as int;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _draggingKbdBacklight = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayBrightness =
        _draggingBrightness ?? (_brightness ?? 0).toDouble();
    final displayKbdBacklight =
        _draggingKbdBacklight ?? (_kbdBacklight ?? 0).toDouble();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.brightness_6, size: 16, color: PrimeColors.warning),
                const SizedBox(width: 8),
                Text(
                  'DISPLAY',
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
            else if (_brightness == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PrimeColors.mutedForeground,
                  ),
                ),
              )
            else ...[
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
            ],
          ],
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
