import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';

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
  bool _showToken = false;
  bool _testing = false;
  bool? _testOk; // null = not tested yet

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testOk = null;
    });

    await widget.apiClient.saveConfig(
      host: _hostController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await widget.apiClient.checkHealth();
    setState(() {
      _testing = false;
      _testOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: PrimeColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PrimeColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: PrimeColors.border)),
                  ),
                  child: Text(
                    'CONNECTION',
                    style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tailscale address',
                        style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _hostController,
                        style: PrimeTheme.mono(fontSize: 13),
                        decoration: const InputDecoration(hintText: '100.x.x.x'),
                      ),
                      const SizedBox(height: 16),
                      Text('Auth token', style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tokenController,
                              obscureText: !_showToken,
                              style: PrimeTheme.mono(fontSize: 13),
                              decoration: const InputDecoration(hintText: 'from ~/.config/prime/token'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _showToken = !_showToken),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: PrimeColors.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 15,
                                color: PrimeColors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: PrimeColors.primary,
                                foregroundColor: PrimeColors.primaryForeground,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _save,
                              child: Text('save', style: PrimeTheme.mono(fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _TestConnectionButton(
                        testing: _testing,
                        result: _testOk,
                        onTap: _testConnection,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestConnectionButton extends StatelessWidget {
  final bool testing;
  final bool? result; // null=untested, true=ok, false=fail
  final VoidCallback onTap;

  const _TestConnectionButton({required this.testing, required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color color;
    Widget content;

    if (testing) {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: PrimeColors.primary),
          ),
          const SizedBox(width: 8),
          Text('testing...', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else if (result == true) {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check, size: 13, color: color),
          const SizedBox(width: 6),
          Text('connected', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else if (result == false) {
      color = PrimeColors.destructive;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.close, size: 13, color: color),
          const SizedBox(width: 6),
          Text('unreachable', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    } else {
      color = PrimeColors.primary;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.podcasts, size: 13, color: color),
          const SizedBox(width: 6),
          Text('test connection', style: PrimeTheme.mono(fontSize: 13, color: color)),
        ],
      );
    }

    return InkWell(
      onTap: testing ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: result == false ? 0.4 : 0.35)),
          color: result == true ? PrimeColors.primary.withValues(alpha: 0.06) : null,
        ),
        child: content,
      ),
    );
  }
}
