import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/biometric_auth.dart';
import '../theme/prime_theme.dart';
import '../widgets/prime_toast.dart';

class CommandsScreen extends StatefulWidget {
  final ApiClient apiClient;
  const CommandsScreen({super.key, required this.apiClient});

  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  List<dynamic>? _commands;
  List<dynamic>? _services;
  String? _error;

  static const _categoryOrder = ['info', 'utility'];
  static const _categoryLabels = {
    'info': 'INFO',
    'utility': 'UTILITY',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cmds = await widget.apiClient.listCommands();
      final svcs = await widget.apiClient.listServices();
      if (!mounted) return;
      setState(() {
        _commands = cmds;
        _services = svcs;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commands')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
              ),
            )
          : (_commands == null || _services == null)
              ? Center(child: CircularProgressIndicator(color: PrimeColors.primary))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildSections(),
                ),
    );
  }

  List<Widget> _buildSections() {
    final byCategory = <String, List<dynamic>>{};
    for (final c in _commands!) {
      final cat = (c['category'] as String?) ?? 'utility';
      byCategory.putIfAbsent(cat, () => []).add(c);
    }

    final widgets = <Widget>[];

    void addHeader(String label) {
      widgets.add(Padding(
        padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 16, bottom: 8),
        child: Text(label, style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
      ));
    }

    // INFO
    final infoItems = byCategory['info'];
    if (infoItems != null && infoItems.isNotEmpty) {
      addHeader('INFO');
      for (final c in infoItems) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CommandTile(apiClient: widget.apiClient, command: c as Map<String, dynamic>),
        ));
      }
    }

    // SERVICES — dynamic, driven by app/config.py's SERVICES_TO_CHECK on the daemon
    if (_services!.isNotEmpty) {
      addHeader('SERVICES');
      for (final s in _services!) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ServiceTile(apiClient: widget.apiClient, service: s as Map<String, dynamic>),
        ));
      }
    }

    // UTILITY
    for (final cat in ['utility']) {
      final items = byCategory[cat];
      if (items == null || items.isEmpty) continue;
      addHeader(_categoryLabels[cat] ?? cat.toUpperCase());
      for (final c in items) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CommandTile(apiClient: widget.apiClient, command: c as Map<String, dynamic>),
        ));
      }
    }

    return widgets;
  }
}

/// Fire-and-forget commands that may drop the connection before the daemon
/// gets to respond (the daemon itself restarts, or the machine sleeps/exits).
const _fireCommandIds = {'reboot', 'suspend', 'logout'};

class _CommandTile extends StatefulWidget {
  final ApiClient apiClient;
  final Map<String, dynamic> command;
  const _CommandTile({required this.apiClient, required this.command});

  @override
  State<_CommandTile> createState() => _CommandTileState();
}

class _CommandTileState extends State<_CommandTile> {
  bool _confirm = false;
  bool _loading = false;
  bool _expanded = false;
  dynamic _result;
  String? _error;
  ({String url, Map<String, String> headers})? _screenshotRequest;

  String get _id => widget.command['id'] as String;
  bool get _needsConfirm => widget.command['needs_confirm'] == true;

  Future<void> _handleTap() async {
    if (_needsConfirm && !_confirm) {
      setState(() => _confirm = true);
      return;
    }

    if (_needsConfirm) {
      final name = widget.command['name'] as String;
      final authorized = await BiometricAuth.confirm('Confirm: $name');
      if (!authorized) {
        if (mounted) setState(() => _confirm = false);
        return;
      }
    }

    setState(() {
      _loading = true;
      _confirm = false;
      _error = null;
    });
    final name = widget.command['name'] as String;
    try {
      final result = await widget.apiClient.runCommand(_id);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _expanded = true;
        if (_id == 'screenshot') {
          _screenshotRequest = widget.apiClient.screenshotImageRequest();
        }
      });
      final failed = result is Map && result['returncode'] != null && result['returncode'] != 0;
      PrimeToast.show(
        context,
        message: failed ? '$name failed' : '$name ran successfully',
        kind: failed ? ToastKind.error : ToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_fireCommandIds.contains(_id)) {
          // Expected — the session may not survive long enough to respond.
          _result = {'started': true};
          _expanded = true;
        } else {
          _error = e.toString();
        }
      });
      if (_fireCommandIds.contains(_id)) {
        PrimeToast.show(context, message: '$name sent', kind: ToastKind.info);
      } else {
        PrimeToast.show(context, message: '$name failed', kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.command['name'] as String;
    final description = widget.command['description'] as String;

    return Container(
      decoration: BoxDecoration(
        color: _confirm ? PrimeColors.destructive.withValues(alpha: 0.08) : PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _handleTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _confirm ? 'confirm: $name?' : name,
                          style: PrimeTheme.mono(
                            fontSize: 13,
                            color: _confirm ? PrimeColors.destructive : PrimeColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground),
                    )
                  else if (_confirm)
                    InkWell(
                      onTap: () => setState(() => _confirm = false),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 13, color: PrimeColors.mutedForeground),
                      ),
                    )
                  else if (_result != null || _error != null)
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.chevron_right, size: 14, color: PrimeColors.mutedForeground),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && (_result != null || _error != null))
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: PrimeColors.border)),
                color: Color(0xFF06101A),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: _error != null
                  ? Text(_error!, style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.destructive))
                  : _buildResultBody(),
            ),
        ],
      ),
    );
  }

  Widget _buildResultBody() {
    if (_id == 'git-status') {
      final repos = (_result['repos'] as List<dynamic>? ?? []);
      if (repos.isEmpty) {
        return Text('no repos found', style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: repos.map((r) {
          final repo = r as Map<String, dynamic>;
          final dirty = repo['dirty'] == true;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(repo['repo'], style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground)),
                Text(
                  dirty ? '● ${repo['changed_files']} modified' : '✓ clean',
                  style: PrimeTheme.mono(fontSize: 11, color: dirty ? PrimeColors.warning : PrimeColors.primary),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    if (_id == 'screenshot' && _screenshotRequest != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          _screenshotRequest!.url,
          headers: _screenshotRequest!.headers,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Text(
            'could not load screenshot',
            style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.destructive),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground)),
            );
          },
        ),
      );
    }

    final result = _result;
    if (result is Map && result.containsKey('started')) {
      return Text('sent', style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.primary));
    }

    if (result is Map && result.containsKey('stdout')) {
      final stdout = (result['stdout'] as String? ?? '').trim();
      final stderr = (result['stderr'] as String? ?? '').trim();
      final text = stdout.isNotEmpty ? stdout : (stderr.isNotEmpty ? stderr : '(no output)');
      return Text(text, style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground));
    }

    const encoder = JsonEncoder.withIndent('  ');
    String pretty;
    try {
      pretty = encoder.convert(result);
    } catch (_) {
      pretty = result.toString();
    }
    return Text(pretty, style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground));
  }
}

/// A single systemd --user service, sourced dynamically from GET /services
/// (which itself just reflects config.py's SERVICES_TO_CHECK on the daemon).
/// Restart always requires confirm + biometric, same as other disruptive
/// actions in this screen.
class _ServiceTile extends StatefulWidget {
  final ApiClient apiClient;
  final Map<String, dynamic> service;
  const _ServiceTile({required this.apiClient, required this.service});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _confirm = false;
  bool _loading = false;
  String? _error;
  String? _lastActionResult;

  String get _name => widget.service['name'] as String;
  String get _status => widget.service['status'] as String;

  Color get _statusColor {
    switch (_status) {
      case 'active':
        return PrimeColors.primary;
      case 'failed':
        return PrimeColors.destructive;
      default:
        return PrimeColors.mutedForeground;
    }
  }

  Future<void> _handleTap() async {
    if (!_confirm) {
      setState(() => _confirm = true);
      return;
    }

    final authorized = await BiometricAuth.confirm('Restart $_name');
    if (!authorized) {
      if (mounted) setState(() => _confirm = false);
      return;
    }

    setState(() {
      _loading = true;
      _confirm = false;
      _error = null;
      _lastActionResult = null;
    });
    try {
      await widget.apiClient.restartService(_name);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastActionResult = 'restarted';
      });
      PrimeToast.show(context, message: '$_name restarted', kind: ToastKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_name == 'prime-daemon.service') {
          // Restarting the daemon itself drops the connection — expected.
          _lastActionResult = 'restarted';
        } else {
          _error = e.toString();
        }
      });
      if (_name == 'prime-daemon.service') {
        PrimeToast.show(context, message: '$_name restarted', kind: ToastKind.success);
      } else {
        PrimeToast.show(context, message: '$_name restart failed', kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _confirm ? PrimeColors.destructive.withValues(alpha: 0.08) : PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _handleTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _confirm ? 'confirm restart: $_name?' : _name,
                          style: PrimeTheme.mono(
                            fontSize: 13,
                            color: _confirm ? PrimeColors.destructive : PrimeColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _status,
                          style: PrimeTheme.mono(fontSize: 10, color: _statusColor),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground),
                    )
                  else if (_confirm)
                    InkWell(
                      onTap: () => setState(() => _confirm = false),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 13, color: PrimeColors.mutedForeground),
                      ),
                    )
                  else
                    Icon(Icons.restart_alt, size: 15, color: PrimeColors.mutedForeground),
                ],
              ),
            ),
          ),
          if (_error != null || _lastActionResult != null)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: PrimeColors.border)),
                color: Color(0xFF06101A),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                _error ?? _lastActionResult!,
                style: PrimeTheme.mono(
                  fontSize: 11,
                  color: _error != null ? PrimeColors.destructive : PrimeColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
