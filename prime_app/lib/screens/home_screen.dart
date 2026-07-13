import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _refresh();
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
        onTap: () => _open(ControlScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.folder_outlined,
        label: 'Files',
        onTap: () => _open(FilesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.inventory_2_outlined,
        label: 'Packages',
        onTap: () => _open(PackagesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.terminal_outlined,
        label: 'Commands',
        onTap: () => _open(CommandsScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: () => _open(SettingsScreen(
          apiClient: widget.apiClient,
          onSaved: () => Navigator.pop(context),
        )),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prime'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18)),
        ],
      ),
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
              _HostCard(status: _status!, host: widget.apiClient.host ?? ''),
              const SizedBox(height: 8),
              _DiskCard(status: _status!),
              const SizedBox(height: 16),
            ],
            Text(
              'Actions',
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
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: actions.map((a) => _ActionTile(item: a)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionItem({required this.icon, required this.label, required this.onTap});
}

class _ActionTile extends StatelessWidget {
  final _ActionItem item;
  const _ActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: PrimeColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PrimeColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: PrimeColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: PrimeTheme.mono(fontSize: 12, letterSpacing: 0.5),
              ),
            ),
          ],
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

class _HostCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final String host;
  const _HostCard({required this.status, required this.host});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: [
                  const PulseDot(),
                  const SizedBox(width: 8),
                  Text(
                    'ONLINE',
                    style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.primary, letterSpacing: 2),
                  ),
                ],
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
            ],
          ),
          const SizedBox(height: 12),
          Text(
            status['hostname'] ?? '',
            style: PrimeTheme.mono(fontSize: 22, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'uptime ${status['daemon_uptime'] ?? ''}',
            style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _DiskCard extends StatelessWidget {
  final Map<String, dynamic> status;
  const _DiskCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final disk = status['disk'] as Map<String, dynamic>;
    final used = (disk['used_gb'] as num).toDouble();
    final total = (disk['total_gb'] as num).toDouble();
    final free = (disk['free_gb'] as num).toDouble();
    final pct = total > 0 ? (used / total * 100).round() : 0;
    final barColor = pct > 80 ? PrimeColors.warning : PrimeColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'DISK',
                style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 4,
              backgroundColor: PrimeColors.secondary,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$pct% used', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
              Text(
                '${free.toStringAsFixed(1)} GB free',
                style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
