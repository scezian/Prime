import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';
import 'settings/connection_settings_screen.dart';
import 'settings/security_settings_screen.dart';
import 'settings/theme_settings_screen.dart';

/// Top-level Settings menu — each row opens its own dedicated screen
/// rather than everything living on one long scrolling page.
class SettingsScreen extends StatelessWidget {
  final ApiClient apiClient;
  final VoidCallback onSaved;

  const SettingsScreen({super.key, required this.apiClient, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsMenuTile(
            icon: Icons.podcasts,
            title: 'Configure',
            subtitle: 'Tailscale address & auth token',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConnectionSettingsScreen(apiClient: apiClient, onSaved: onSaved),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsMenuTile(
            icon: Icons.lock_outline,
            title: 'Security',
            subtitle: 'App lock, fingerprint & laptop password',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsMenuTile(
            icon: Icons.palette_outlined,
            title: 'Themes',
            subtitle: 'Change the app color scheme',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: PrimeColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PrimeColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: PrimeGradients.tileA,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PrimeTheme.text(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: PrimeTheme.text(fontSize: 11, color: PrimeColors.mutedForeground)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: PrimeColors.mutedForeground),
          ],
        ),
      ),
    );
  }
}
