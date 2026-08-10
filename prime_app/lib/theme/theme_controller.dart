import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single selectable theme: a background color and two accent colors
/// (vibrant + deep) used to derive every other shade in [PrimeColors] and
/// [PrimeGradients].
class PrimePreset {
  final String id;
  final String label;
  final Color background;
  final Color accent;
  final Color accentDark;

  const PrimePreset({
    required this.id,
    required this.label,
    required this.background,
    required this.accent,
    required this.accentDark,
  });
}

class PrimePresets {
  static const violet = PrimePreset(
    id: 'violet',
    label: 'Violet',
    background: Color(0xFF020617),
    accent: Color(0xFF8B5CF6),
    accentDark: Color(0xFF6D28D9),
  );

  static const carbonLime = PrimePreset(
    id: 'carbon_lime',
    label: 'Carbon & Lime',
    background: Color(0xFF171717),
    accent: Color(0xFF8BC34A),
    accentDark: Color(0xFF558B2F),
  );

  static const royalAurora = PrimePreset(
    id: 'royal_aurora',
    label: 'Royal Aurora',
    background: Color(0xFF3E2F5B),
    accent: Color(0xFFE94560),
    accentDark: Color(0xFF4E3B72),
  );

  static const midnightGold = PrimePreset(
    id: 'midnight_gold',
    label: 'Midnight Gold',
    background: Color(0xFF1A1A1A),
    accent: Color(0xFFB3945B),
    accentDark: Color(0xFF2B2620),
  );

  static const emeraldChrome = PrimePreset(
    id: 'emerald_chrome',
    label: 'Emerald Chrome',
    background: Color(0xFF010528),
    accent: Color(0xFF004B8E),
    accentDark: Color(0xFF0A1B4D),
  );

  static const oceanRose = PrimePreset(
    id: 'ocean_rose',
    label: 'Ocean Rose',
    background: Color(0xFF060F11),
    accent: Color(0xFFAA4B6B),
    accentDark: Color(0xFF2F6570),
  );

  static const solarPop = PrimePreset(
    id: 'solar_pop',
    label: 'Solar Pop',
    background: Color(0xFF140900),
    accent: Color(0xFFFF6A00),
    accentDark: Color(0xFF7A4400),
  );

  static const neonPulse = PrimePreset(
    id: 'neon_pulse',
    label: 'Neon Pulse',
    background: Color(0xFF0D0313),
    accent: Color(0xFFE94057),
    accentDark: Color(0xFF8A2387),
  );

  static const sunriseSorbet = PrimePreset(
    id: 'sunrise_sorbet',
    label: 'Sunrise Sorbet',
    background: Color(0xFF061410),
    accent: Color(0xFFF7797D),
    accentDark: Color(0xFF1F5C42),
  );

  static const auroraDust = PrimePreset(
    id: 'aurora_dust',
    label: 'Aurora Dust',
    background: Color(0xFF05070F),
    accent: Color(0xFFB993D6),
    accentDark: Color(0xFF3D4E7A),
  );

  static const all = <PrimePreset>[
    violet,
    carbonLime,
    royalAurora,
    midnightGold,
    emeraldChrome,
    oceanRose,
    solarPop,
    neonPulse,
    sunriseSorbet,
    auroraDust,
  ];
}

/// Holds the active [PrimePreset] and persists the choice across launches.
/// [PrimeColors]/[PrimeGradients] read from [instance.preset] to derive
/// every color used in the app, so calling [setPreset] (which fires
/// [notifyListeners]) is enough to re-theme the whole UI once the widget
/// tree above [MaterialApp] rebuilds in response.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _prefsKey = 'prime_theme_preset_id';

  PrimePreset _preset = PrimePresets.violet;
  PrimePreset get preset => _preset;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    if (id == null) return;
    final match = PrimePresets.all.where((p) => p.id == id);
    if (match.isEmpty) return;
    _preset = match.first;
    notifyListeners();
  }

  Future<void> setPreset(PrimePreset preset) async {
    if (preset.id == _preset.id) return;
    _preset = preset;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, preset.id);
  }
}
