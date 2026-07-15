import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/biometric_auth.dart';
import '../theme/prime_theme.dart';

enum _ViewMode { installed, search }

class PackagesScreen extends StatefulWidget {
  final ApiClient apiClient;

  const PackagesScreen({super.key, required this.apiClient});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _results = [];
  int _totalMatches = 0;
  _ViewMode _mode = _ViewMode.installed;
  bool _loading = false;
  bool _busy = false;
  String? _busyPackage;
  String? _error;

  Map<String, dynamic>? _lastResult;
  String? _lastAction; // 'install' | 'uninstall'
  String? _lastPackageName;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    setState(() {
      _mode = _ViewMode.installed;
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.getInstalledPackages();
      setState(() {
        _results = res['packages'] as List<dynamic>;
        _totalMatches = res['total'] as int;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadInstalled();
      return;
    }

    setState(() {
      _mode = _ViewMode.search;
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.apiClient.searchPackages(query);
      setState(() {
        _results = res['results'] as List<dynamic>;
        _totalMatches = res['total_matches'] as int;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshCurrentView() {
    return _mode == _ViewMode.installed ? _loadInstalled() : _search();
  }

  Future<void> _install(Map<String, dynamic> pkg) async {
    final name = (pkg['package'] as String).split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Install', style: PrimeTheme.mono(fontSize: 15)),
        content: Text(
          'Install "$name"? This may take a while for AUR packages.',
          style: PrimeTheme.mono(fontSize: 13, color: PrimeColors.mutedForeground),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.primary, foregroundColor: PrimeColors.primaryForeground),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final authorized = await BiometricAuth.confirm('Install $name');
    if (!authorized || !mounted) return;

    setState(() {
      _busy = true;
      _busyPackage = name;
    });

    try {
      final result = await widget.apiClient.installPackage(name);
      setState(() {
        _lastResult = result;
        _lastAction = 'install';
        _lastPackageName = name;
      });
      await _refreshCurrentView();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      setState(() {
        _busy = false;
        _busyPackage = null;
      });
    }
  }

  Future<void> _uninstall(Map<String, dynamic> pkg) async {
    final name = (pkg['package'] as String).split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Uninstall', style: PrimeTheme.mono(fontSize: 15)),
        content: Text('Uninstall "$name"?', style: PrimeTheme.mono(fontSize: 13, color: PrimeColors.mutedForeground)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrimeColors.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final authorized = await BiometricAuth.confirm('Uninstall $name');
    if (!authorized || !mounted) return;

    setState(() {
      _busy = true;
      _busyPackage = name;
    });

    try {
      final result = await widget.apiClient.uninstallPackage(name);
      setState(() {
        _lastResult = result;
        _lastAction = 'uninstall';
        _lastPackageName = name;
      });
      await _refreshCurrentView();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      setState(() {
        _busy = false;
        _busyPackage = null;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installedCount =
        _mode == _ViewMode.installed ? _results.length : _results.where((p) => (p as Map)['installed'] == true).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Packages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: PrimeColors.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: PrimeColors.mutedForeground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: PrimeTheme.mono(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'search to install new packages...',
                        hintStyle: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground),
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _searchController.clear();
                        _loadInstalled();
                      },
                      child: const Icon(Icons.close, size: 13, color: PrimeColors.mutedForeground),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _mode == _ViewMode.installed
                      ? 'INSTALLED'
                      : (_totalMatches > _results.length ? 'showing ${_results.length} of $_totalMatches' : 'RESULTS'),
                  style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2),
                ),
                if (_mode == _ViewMode.installed)
                  Text('$installedCount packages', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
              ],
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: PrimeColors.primary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
            ),
          if (_lastResult != null && !_busy)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF040D14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: PrimeColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: PrimeColors.primary.withValues(alpha: 0.15))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal, size: 11, color: PrimeColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              '${_lastResult!['returncode'] == 0 ? (_lastAction == 'install' ? 'installed' : 'removed') : 'failed'} · $_lastPackageName',
                              style: PrimeTheme.mono(fontSize: 9, letterSpacing: 1, color: PrimeColors.primary),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () => setState(() => _lastResult = null),
                          child: const Icon(Icons.close, size: 12, color: PrimeColors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: Text(
                        _tailOutput(_lastResult!),
                        style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, height: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_loading && _error == null && _results.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _mode == _ViewMode.installed ? 'no explicitly installed packages found' : 'no results',
                  style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground),
                ),
              ),
            ),
          if (!_loading && _results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final pkg = _results[i] as Map<String, dynamic>;
                  final isInstalled = pkg['installed'] == true;
                  final isAur = (pkg['package'] as String).startsWith('aur/');
                  final name = (pkg['package'] as String).split('/').last;
                  final isBusyThis = _busy && _busyPackage == name;
                  final hasDescription = (pkg['description'] as String?)?.isNotEmpty == true;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PrimeColors.border))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Text(pkg['package'], style: PrimeTheme.mono(fontSize: 13)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isAur ? PrimeColors.warning.withValues(alpha: 0.4) : PrimeColors.border,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      isAur ? 'aur' : 'extra',
                                      style: PrimeTheme.mono(
                                        fontSize: 8,
                                        color: isAur ? PrimeColors.warning : PrimeColors.mutedForeground,
                                      ),
                                    ),
                                  ),
                                  if (isInstalled && _mode == _ViewMode.search)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check, size: 8, color: PrimeColors.primary),
                                        const SizedBox(width: 2),
                                        Text('installed', style: PrimeTheme.mono(fontSize: 8, color: PrimeColors.primary)),
                                      ],
                                    ),
                                ],
                              ),
                              if (hasDescription) ...[
                                const SizedBox(height: 3),
                                Text(
                                  pkg['description'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground, height: 1.4),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                pkg['version'] ?? '',
                                style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isBusyThis)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.mutedForeground),
                            ),
                          )
                        else
                          InkWell(
                            onTap: _busy ? null : () => isInstalled ? _uninstall(pkg) : _install(pkg),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isInstalled
                                      ? PrimeColors.destructive.withValues(alpha: 0.3)
                                      : PrimeColors.primary.withValues(alpha: 0.35),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isInstalled ? Icons.delete_outline : Icons.download_outlined,
                                    size: 9,
                                    color: isInstalled ? PrimeColors.destructive : PrimeColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isInstalled ? 'remove' : 'install',
                                    style: PrimeTheme.mono(
                                      fontSize: 10,
                                      color: isInstalled ? PrimeColors.destructive : PrimeColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _tailOutput(Map<String, dynamic> result) {
    final text = (result['stderr'] as String?)?.isNotEmpty == true
        ? result['stderr'] as String
        : (result['stdout'] as String? ?? '');
    if (text.length <= 800) return text;
    return '...${text.substring(text.length - 800)}';
  }
}
