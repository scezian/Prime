import 'package:flutter/material.dart';
import '../services/api_client.dart';

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
  bool _searching = false;
  bool _busy = false;
  String? _error;
  String? _busyPackage;

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final res = await widget.apiClient.searchPackages(query);
      setState(() {
        _results = res['results'] as List<dynamic>;
        _totalMatches = res['total_matches'] as int;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  Future<void> _install(Map<String, dynamic> pkg) async {
    final name = (pkg['package'] as String).split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install'),
        content: Text('Install "$name"? This may take a while for AUR packages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Install')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyPackage = name;
    });

    try {
      final result = await widget.apiClient.installPackage(name);
      final ok = result['returncode'] == 0;
      if (mounted) {
        _showResultDialog(ok ? 'Installed $name' : 'Install failed', result['stderr'] ?? result['stdout'] ?? '');
      }
      await _search();
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
        title: const Text('Uninstall'),
        content: Text('Uninstall "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyPackage = name;
    });

    try {
      final result = await widget.apiClient.uninstallPackage(name);
      final ok = result['returncode'] == 0;
      if (mounted) {
        _showResultDialog(ok ? 'Uninstalled $name' : 'Uninstall failed', result['stderr'] ?? result['stdout'] ?? '');
      }
      await _search();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      setState(() {
        _busy = false;
        _busyPackage = null;
      });
    }
  }

  void _showResultDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            body.length > 1500 ? '...${body.substring(body.length - 1500)}' : body,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Search packages...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_totalMatches > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing ${_results.length} of $_totalMatches matches',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ),
          if (_searching) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final pkg = _results[i] as Map<String, dynamic>;
                final isInstalled = pkg['installed'] == true;
                final name = (pkg['package'] as String).split('/').last;
                final isBusyThis = _busy && _busyPackage == name;

                return ListTile(
                  title: Text(pkg['package']),
                  subtitle: Text('${pkg['version']} — ${pkg['description']}'),
                  trailing: isBusyThis
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : isInstalled
                          ? OutlinedButton(
                              onPressed: _busy ? null : () => _uninstall(pkg),
                              child: const Text('Uninstall'),
                            )
                          : FilledButton(
                              onPressed: _busy ? null : () => _install(pkg),
                              child: const Text('Install'),
                            ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
