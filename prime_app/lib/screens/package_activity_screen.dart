import 'package:flutter/material.dart';
import '../services/package_activity.dart';
import '../theme/prime_theme.dart';

/// Panel listing package install/uninstall activity: whatever's currently
/// running up top, then history below. Opened from the activity icon in
/// the Packages screen's app bar.
class PackageActivityScreen extends StatefulWidget {
  const PackageActivityScreen({super.key});

  @override
  State<PackageActivityScreen> createState() => _PackageActivityScreenState();
}

class _PackageActivityScreenState extends State<PackageActivityScreen> {
  final _center = PackageActivityCenter.instance;

  @override
  void initState() {
    super.initState();
    _center.addListener(_onChanged);
  }

  @override
  void dispose() {
    _center.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text('Delete all?', style: PrimeTheme.text(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'This clears your entire install/uninstall history. This can\'t be undone.',
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
            child: Text('Delete all', style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) _center.deleteAll();
  }

  @override
  Widget build(BuildContext context) {
    final items = _center.items;
    final running = items.where((i) => i.status == PackageActivityStatus.running).toList();
    final history = items.where((i) => i.status != PackageActivityStatus.running).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: items.isEmpty ? null : _center.markAllRead,
            icon: const Icon(Icons.done_all, size: 20),
          ),
          IconButton(
            tooltip: 'Delete all',
            onPressed: items.isEmpty ? null : _confirmDeleteAll,
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                'No package activity yet',
                style: PrimeTheme.text(fontSize: 13, color: PrimeColors.mutedForeground),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (running.isNotEmpty) ...[
                  _SectionLabel('IN PROGRESS'),
                  const SizedBox(height: 10),
                  ...running.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ActivityTile(item: i),
                      )),
                  const SizedBox(height: 22),
                ],
                if (history.isNotEmpty) ...[
                  _SectionLabel('HISTORY'),
                  const SizedBox(height: 10),
                  ...history.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ActivityTile(item: i),
                      )),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PrimeTheme.text(fontSize: 11, fontWeight: FontWeight.w700, color: PrimeColors.prime400, letterSpacing: 1.8),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final PackageActivityItem item;
  const _ActivityTile({required this.item});

  Color get _accent {
    switch (item.status) {
      case PackageActivityStatus.running:
        return PrimeColors.primary;
      case PackageActivityStatus.success:
        return PrimeColors.success;
      case PackageActivityStatus.failed:
        return PrimeColors.destructive;
    }
  }

  IconData get _icon {
    if (item.status == PackageActivityStatus.running) {
      return item.action == PackageActivityAction.install ? Icons.download_outlined : Icons.delete_outline;
    }
    return item.status == PackageActivityStatus.success ? Icons.check_circle_outline : Icons.error_outline;
  }

  String get _statusLabel {
    final verb = item.action == PackageActivityAction.install ? 'Installing' : 'Uninstalling';
    switch (item.status) {
      case PackageActivityStatus.running:
        return verb;
      case PackageActivityStatus.success:
        return item.action == PackageActivityAction.install ? 'Installed' : 'Uninstalled';
      case PackageActivityStatus.failed:
        return item.action == PackageActivityAction.install ? 'Install failed' : 'Uninstall failed';
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.read ? PrimeColors.border : _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: item.status == PackageActivityStatus.running
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.primary),
                  )
                : Icon(_icon, size: 18, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.packageName,
                        overflow: TextOverflow.ellipsis,
                        style: PrimeTheme.text(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!item.read)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: PrimeColors.primary),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text('$_statusLabel · ${_timeAgo(item.startedAt)}', style: PrimeTheme.text(fontSize: 11, color: _accent)),
                if (item.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.errorMessage!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: PrimeTheme.text(fontSize: 11, color: PrimeColors.mutedForeground),
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
