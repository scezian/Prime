import 'package:flutter/material.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onSaved;

  const SettingsScreen({super.key, required this.apiClient, required this.onSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _hostController.text = widget.apiClient.host ?? '';
    _tokenController.text = widget.apiClient.token ?? '';
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.apiClient.saveConfig(
      host: _hostController.text.trim(),
      token: _tokenController.text.trim(),
    );
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    await widget.apiClient.saveConfig(
      host: _hostController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await widget.apiClient.checkHealth();
    setState(() {
      _testing = false;
      _testResult = ok ? 'Connected' : 'Could not reach the laptop';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Laptop address (Tailscale IP)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '100.x.x.x',
            ),
          ),
          const SizedBox(height: 16),
          const Text('Auth token', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'from ~/.config/prime/token on scez-2',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test connection'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Text(
              _testResult!,
              style: TextStyle(
                color: _testResult == 'Connected' ? Colors.green : Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
