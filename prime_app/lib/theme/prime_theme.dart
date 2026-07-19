import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_controller.dart';

/// Design tokens ported from the bolt.new "prim3" UI (tailwind.config.js).
/// All color values below are derived at read-time from the active
/// [ThemeController] preset, so the whole app re-themes the moment the
/// user picks a different preset in Settings.
class PrimeColors {
  static PrimePreset get _p => ThemeController.instance.preset;

  static Color _shade(Color base, double delta) {
    final hsl = HSLColor.fromColor(base);
    final lightness = (hsl.lightness + delta).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  /// Like [_shade], but also caps saturation. Neutrals (card backgrounds,
  /// secondary/muted text) should read as gray with at most a faint tint
  /// of the theme's hue — not the fully-saturated background color pushed
  /// lighter, which on saturated presets (e.g. Emerald Chrome's navy)
  /// produces vivid colored text instead of readable gray.
  static Color _neutralShade(Color base, double delta) {
    final hsl = HSLColor.fromColor(base);
    final lightness = (hsl.lightness + delta).clamp(0.0, 1.0);
    final saturation = hsl.saturation.clamp(0.0, 0.16);
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  // ink (neutrals) — derived from the active preset's background, desaturated
  // so text and card surfaces stay legible even on highly saturated presets.
  static Color get ink50 => const Color(0xFFF8FAFC);
  static Color get ink100 => _neutralShade(_p.background, 0.84);
  static Color get ink200 => _neutralShade(_p.background, 0.74);
  static Color get ink300 => _neutralShade(_p.background, 0.60);
  static Color get ink400 => _neutralShade(_p.background, 0.46);
  static Color get ink500 => _neutralShade(_p.background, 0.32);
  static Color get ink600 => _neutralShade(_p.background, 0.22);
  static Color get ink700 => _neutralShade(_p.background, 0.16);
  static Color get ink800 => _neutralShade(_p.background, 0.12);
  static Color get ink900 => _neutralShade(_p.background, 0.07);
  static Color get ink950 => _p.background;

  // prime (brand accent) — derived from the active preset's accent colors.
  static Color get prime50 => _shade(_p.accent, 0.42);
  static Color get prime100 => _shade(_p.accent, 0.34);
  static Color get prime200 => _shade(_p.accent, 0.24);
  static Color get prime300 => _shade(_p.accent, 0.15);
  static Color get prime400 => _shade(_p.accent, 0.07);
  static Color get prime500 => _p.accent;
  static Color get prime600 => _shade(_p.accent, -0.06);
  static Color get prime700 => _p.accentDark;
  static Color get prime800 => _shade(_p.accentDark, -0.07);
  static Color get prime900 => _shade(_p.accentDark, -0.14);
  static Color get prime950 => _shade(_p.accentDark, -0.20);

  // Semantic aliases — kept so existing screens (control/files/packages/
  // commands/settings) keep compiling unchanged.
  static Color get background => ink950;
  static Color get foreground => ink50;
  static Color get card => ink900;
  static Color get primary => prime500;
  static const primaryForeground = Colors.white;
  static Color get secondary => ink800;
  static Color get secondaryForeground => ink300;
  static Color get muted => ink800;
  static Color get mutedForeground => ink400;
  static const destructive = Color(0xFFEF4444); // red
  static const warning = Color(0xFFF59E0B); // amber
  static const success = Color(0xFF22C55E); // green
  static const cpuAccent = Color(0xFF38BDF8); // cyan — stat colors stay fixed
  static const memAccent = Color(0xFFF472B6); // pink
  static const netAccent = Color(0xFF818CF8); // violet
  static const filesAccent = Color(0xFF4F8EF7); // blue
  static Color get packagesAccent => prime400;
  static const border = Color(0x1FFFFFFF); // rgba(255,255,255,0.12) — bumped for contrast on saturated backgrounds
  static Color get inputBackground => ink800;
}

/// Gradients matching the bolt.new QuickActions / FeatureTiles buttons.
class PrimeGradients {
  static LinearGradient get tileA => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PrimeColors.prime500, PrimeColors.prime700],
      );
  static LinearGradient get tileB => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PrimeColors.prime600, PrimeColors.prime800],
      );
  static LinearGradient get header => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PrimeColors.prime500, PrimeColors.prime700],
      );
}

class PrimeShadows {
  static List<BoxShadow> get card => [
        BoxShadow(color: PrimeColors.prime700.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2)),
      ];
  static List<BoxShadow> get tile => [
        BoxShadow(color: PrimeColors.prime700.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6)),
      ];
}

class PrimeTheme {
  /// Body/UI text style — Inter (bolt.new's font).
  static TextStyle text({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? PrimeColors.foreground,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Back-compat alias — old screens call `PrimeTheme.mono(...)`. Now just
  /// routes to the new Inter-based `text()` so nothing breaks while those
  /// screens get restyled one at a time.
  static TextStyle mono({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      text(fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: PrimeColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: PrimeColors.background,
        primary: PrimeColors.primary,
        onPrimary: Colors.white,
        secondary: PrimeColors.prime700,
        onSecondary: Colors.white,
        error: PrimeColors.destructive,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: PrimeColors.foreground,
        displayColor: PrimeColors.foreground,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: PrimeColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4),
        iconTheme: IconThemeData(color: PrimeColors.mutedForeground),
      ),
      cardTheme: CardThemeData(
        color: PrimeColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: PrimeColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PrimeColors.ink900,
        indicatorColor: PrimeColors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? PrimeColors.prime300 : PrimeColors.mutedForeground,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? PrimeColors.prime300 : PrimeColors.mutedForeground,
            size: 22,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PrimeColors.inputBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: PrimeColors.primary, width: 1.4),
        ),
        hintStyle: text(color: PrimeColors.mutedForeground),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PrimeColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: PrimeColors.border),
        ),
      ),
      dividerColor: PrimeColors.border,
    );
  }
}
