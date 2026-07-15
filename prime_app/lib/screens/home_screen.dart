import 'dart:async';
import 'package:flutter/material.dart';
import '../services/biometric_auth.dart';
import '../services/secure_credentials.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';
import '../widgets/pulse_dot.dart';
import 'control_screen.dart';
import 'files_screen.dart';
import 'packages_screen.dart';
import 'settings_screen.dart';
import 'commands_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  String? _error;
  bool? _locked;
  Timer? _lockPollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollLockStatus();
    _lockPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollLockStatus());
  }

  @override
  void dispose() {
    _lockPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.apiClient.isConfigured) {
      setState(() => _error = 'Not configured. Go to Settings first.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await widget.apiClient.getStatus();
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pollLockStatus() async {
    if (!widget.apiClient.isConfigured) return;
    try {
      final res = await widget.apiClient.getLockStatus();
      if (!mounted) return;
      setState(() => _locked = res['locked'] as bool);
    } catch (_) {
      // best-effort, ignore
    }
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      // Refresh status in case something changed (e.g. settings) while away.
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionItem>[
      _ActionItem(
        icon: Icons.tune_outlined,
        label: 'Control',
        subtitle: 'media · system',
        accent: PrimeColors.cpuAccent,
        onTap: () => _open(ControlScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.folder_outlined,
        label: 'Files',
        subtitle: widget.apiClient.host ?? '',
        stat: _status != null
            ? '${(_status!['disk']['free_gb'] as num).toStringAsFixed(0)} GB free'
            : null,
        statColor: PrimeColors.filesAccent,
        accent: PrimeColors.filesAccent,
        onTap: () => _open(FilesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.inventory_2_outlined,
        label: 'Packages',
        subtitle: 'pacman / paru',
        accent: PrimeColors.packagesAccent,
        onTap: () => _open(PackagesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.terminal_outlined,
        label: 'Commands',
        subtitle: '17 actions',
        accent: PrimeColors.warning,
        onTap: () => _open(CommandsScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.settings_outlined,
        label: 'Settings',
        subtitle: 'tailscale · auth',
        stat: widget.apiClient.host,
        statColor: PrimeColors.destructive,
        accent: PrimeColors.destructive,
        onTap: () => _open(SettingsScreen(
          apiClient: widget.apiClient,
          onSaved: () => Navigator.pop(context),
        )),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Prime')),
      body: RefreshIndicator(
        color: PrimeColors.primary,
        backgroundColor: PrimeColors.card,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) _ErrorBanner(message: _error!),
            if (_loading && _status == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: PrimeColors.primary)),
              ),
            if (_status != null) ...[
              // PRIME_OVERVIEW_CARD_REMOVED
              Text('POWER', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _LockToggleButton(
                      apiClient: widget.apiClient,
                      locked: _locked,
                      onChanged: (v) => setState(() => _locked = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PowerActionButton(
                      apiClient: widget.apiClient,
                      commandId: 'logout',
                      label: 'Log Out',
                      icon: Icons.logout,
                      needsConfirm: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PowerActionButton(
                      apiClient: widget.apiClient,
                      commandId: 'reboot',
                      label: 'Restart',
                      icon: Icons.restart_alt,
                      needsConfirm: true,
                      expectDaemonDeath: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PowerActionButton(
                      apiClient: widget.apiClient,
                      commandId: 'shutdown',
                      label: 'Shutdown',
                      icon: Icons.power_settings_new,
                      needsConfirm: true,
                      expectDaemonDeath: true,
                    ),
                  ),
                ],
              ),
            ],
            Text(
              'ACTIONS',
              style: PrimeTheme.mono(
                fontSize: 9,
                color: PrimeColors.mutedForeground,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: actions.take(4).map((a) => _ActionTile(item: a)).toList(),
            ),
            const SizedBox(height: 10),
            _ActionTile(item: actions.last, fullWidth: true),
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final String? stat;
  final Color? statColor;
  final Color accent;
  final VoidCallback onTap;
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.stat,
    this.statColor,
    required this.accent,
    required this.onTap,
  });
}

class _ActionTile extends StatefulWidget {
  final _ActionItem item;
  final bool fullWidth;
  const _ActionTile({required this.item, this.fullWidth = false});

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: item.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: widget.fullWidth ? double.infinity : null,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PrimeColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: item.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: item.accent),
              const SizedBox(height: 10),
              Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: PrimeTheme.mono(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                overflow: TextOverflow.ellipsis,
                style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
              ),
              if (item.stat != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.stat!,
                  overflow: TextOverflow.ellipsis,
                  style: PrimeTheme.mono(fontSize: 11, color: item.statColor ?? item.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.3)),
      ),
      child: Text(message, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
    );
  }
}

/// Merged system overview: online pill, hostname/uptime, cpu/mem/disk/net
/// stat row, and the disk usage bar — replaces the old separate host+disk cards.
class _OverviewCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final String host;
  final bool loading;
  final VoidCallback onRefresh;

  const _OverviewCard({
    required this.status,
    required this.host,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final disk = status['disk'] as Map<String, dynamic>;
    final diskUsed = (disk['used_gb'] as num).toDouble();
    final diskTotal = (disk['total_gb'] as num).toDouble();
    final diskFree = (disk['free_gb'] as num).toDouble();
    final diskPct = diskTotal > 0 ? (diskUsed / diskTotal * 100).round() : 0;
    final diskBarColor = diskPct > 80 ? PrimeColors.warning : PrimeColors.primary;

    final cpuPct = (status['cpu_percent'] as num?)?.round() ?? 0;
    final mem = status['memory'] as Map<String, dynamic>?;
    final memUsedGb = mem != null ? (mem['used_gb'] as num).toStringAsFixed(1) : '--';
    final net = status['network'] as Map<String, dynamic>?;
    final downKbps = net != null ? (net['download_kbps'] as num).toDouble() : 0.0;
    final netLabel = downKbps >= 1024
        ? '${(downKbps / 1024).toStringAsFixed(1)}m'
        : '${downKbps.toStringAsFixed(0)}k';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PrimeColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulseDot(),
              const SizedBox(width: 8),
              Text(
                'ONLINE',
                style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.primary, letterSpacing: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRefresh,
                child: AnimatedRotation(
                  turns: loading ? 1 : 0,
                  duration: const Duration(milliseconds: 600),
                  child: Icon(Icons.refresh, size: 16, color: PrimeColors.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            status['hostname'] ?? '',
            style: PrimeTheme.mono(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'uptime ${status['daemon_uptime'] ?? ''}',
            style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(icon: Icons.memory, label: 'cpu', value: '$cpuPct%', color: PrimeColors.cpuAccent),
              _StatTile(icon: Icons.developer_board, label: 'mem', value: '${memUsedGb}g', color: PrimeColors.memAccent),
              _StatTile(icon: Icons.sd_card_outlined, label: 'disk', value: '$diskPct%', color: PrimeColors.warning),
              _StatTile(icon: Icons.swap_vert, label: 'net', value: netLabel, color: PrimeColors.netAccent),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('DISK', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
              const Spacer(),
              Text(
                '${diskUsed.toStringAsFixed(1)} / ${diskTotal.toStringAsFixed(1)} GB',
                style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: diskPct / 100),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: PrimeColors.secondary,
                valueColor: AlwaysStoppedAnimation(diskBarColor),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$diskPct% used', style: PrimeTheme.mono(fontSize: 9, color: diskBarColor)),
              Text('${diskFree.toStringAsFixed(1)} GB free', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 5),
          Text(label, style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              value,
              key: ValueKey(value),
              style: PrimeTheme.mono(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic confirm(-optional) + biometric + fire power action button, used
/// for Log Out, Restart, and Shutdown. Mirrors the daemon's own
/// `needs_confirm` flag per command in commands.py.
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

/// Lock/Unlock toggle. Locking uses the existing fire-and-forget
/// `lock-screen` command. Unlocking sends your stored laptop password to
/// the daemon, which types it into the running hyprlock prompt so
/// hyprlock's own PAM check validates it — not a bypass, the same path a
/// physical keystroke takes. The password lives only in this device's
/// secure storage (Android Keystore-backed) and is sent fresh per
/// request; the daemon never writes it to disk.
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
        await SecureCredentials.clearUnlockPassword();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlock failed — check the password and try again')),
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
