import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ported from the bolt.new "prim3" UI (tailwind.config.js),
/// replacing the old navy/mono terminal look with the purple gradient style.
class PrimeColors {
  // ink (neutrals) — from tailwind `ink` scale
  static const ink50 = Color(0xFFF8FAFC);
  static const ink100 = Color(0xFFF1F5F9);
  static const ink200 = Color(0xFFE2E8F0);
  static const ink300 = Color(0xFFCBD5E1);
  static const ink400 = Color(0xFF94A3B8);
  static const ink500 = Color(0xFF64748B);
  static const ink600 = Color(0xFF475569);
  static const ink700 = Color(0xFF334155);
  static const ink800 = Color(0xFF1E293B);
  static const ink900 = Color(0xFF0F172A);
  static const ink950 = Color(0xFF020617);

  // prime (purple) — from tailwind `prime` scale
  static const prime50 = Color(0xFFF5F3FF);
  static const prime100 = Color(0xFFEDE9FE);
  static const prime200 = Color(0xFFDDD6FE);
  static const prime300 = Color(0xFFC4B5FD);
  static const prime400 = Color(0xFFA78BFA);
  static const prime500 = Color(0xFF8B5CF6);
  static const prime600 = Color(0xFF7C3AED);
  static const prime700 = Color(0xFF6D28D9);
  static const prime800 = Color(0xFF5B21B6);
  static const prime900 = Color(0xFF4C1D95);
  static const prime950 = Color(0xFF2E1065);

  // Semantic aliases — kept so existing screens (control/files/packages/
  // commands/settings) keep compiling while they're migrated over.
  static const background = ink950;
  static const foreground = ink50;
  static const card = ink900;
  static const primary = prime500;
  static const primaryForeground = Colors.white;
  static const secondary = ink800;
  static const secondaryForeground = ink300;
  static const muted = ink800;
  static const mutedForeground = ink400;
  static const destructive = Color(0xFFEF4444); // red
  static const warning = Color(0xFFF59E0B); // amber
  static const success = Color(0xFF22C55E); // green
  static const cpuAccent = Color(0xFF38BDF8); // cyan
  static const memAccent = Color(0xFFF472B6); // pink
  static const netAccent = Color(0xFF818CF8); // violet
  static const filesAccent = Color(0xFF4F8EF7); // blue
  static const packagesAccent = prime400; // purple, matches new palette
  static const border = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const inputBackground = ink800;
}

/// Gradients matching the bolt.new QuickActions / FeatureTiles buttons.
class PrimeGradients {
  static const tileA = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PrimeColors.prime500, PrimeColors.prime700],
  );
  static const tileB = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PrimeColors.prime600, PrimeColors.prime800],
  );
  static const header = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PrimeColors.prime500, PrimeColors.prime700],
  );
}

class PrimeShadows {
  static List<BoxShadow> card = [
    BoxShadow(color: PrimeColors.prime700.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> tile = [
    BoxShadow(color: PrimeColors.prime700.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6)),
  ];
}

class PrimeTheme {
  /// Body/UI text style — now Inter (bolt.new's font), replacing the old
  /// JetBrains Mono terminal look.
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
        iconTheme: const IconThemeData(color: PrimeColors.mutedForeground),
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
          borderSide: const BorderSide(color: PrimeColors.primary, width: 1.4),
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
