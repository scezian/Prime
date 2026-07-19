import 'package:flutter/material.dart';
import '../../theme/prime_theme.dart';
import '../../theme/theme_controller.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [_ThemePickerCard()],
      ),
    );
  }
}

class _ThemePickerCard extends StatelessWidget {
  const _ThemePickerCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final active = ThemeController.instance.preset;
        return Container(
          decoration: BoxDecoration(
            color: PrimeColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: PrimeColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: PrimeColors.border)),
                ),
                child: Text(
                  'THEME',
                  style: PrimeTheme.text(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: PrimeColors.prime400,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: PrimePresets.all.map((preset) {
                    final selected = preset.id == active.id;
                    return InkWell(
                      onTap: () => ThemeController.instance.setPreset(preset),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 84,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? preset.accent : PrimeColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [preset.accent, preset.accentDark],
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              preset.label,
                              textAlign: TextAlign.center,
                              style: PrimeTheme.text(fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
