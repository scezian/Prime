import 'package:flutter/material.dart';
import '../services/api_client.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _status;
  List<dynamic> _commands = [];
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _lastResult;
  String? _lastResultCommand;

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
      final commands = await widget.apiClient.listCommands();
      setState(() {
        _status = status;
        _commands = commands;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _runCommand(Map<String, dynamic> command) async {
    final needsConfirm = command['needs_confirm'] == true;

    if (needsConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(command['name']),
          content: Text('Run "${command['description']}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _loading = true;
      _lastResult = null;
    });

    try {
      final result = await widget.apiClient.runCommand(command['id']);
      setState(() {
        _lastResult = result;
        _lastResultCommand = command['name'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prime'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),
            if (_loading) const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (_status != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.green, size: 12),
                          const SizedBox(width: 8),
                          Text(_status!['hostname'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Uptime: ${_status!['daemon_uptime']}'),
                      Text(
                        'Disk: ${_status!['disk']['used_gb']} / ${_status!['disk']['total_gb']} GB used',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Commands', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ..._commands.map((cmd) => Card(
                  child: ListTile(
                    title: Text(cmd['name']),
                    subtitle: Text(cmd['description']),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => _runCommand(cmd),
                  ),
                )),
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              Text('Result: $_lastResultCommand', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _lastResult.toString(),
                  style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
