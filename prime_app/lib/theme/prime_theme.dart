import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens lifted directly from the Figma design's theme.css.
class PrimeColors {
  static const background = Color(0xFF090D13);
  static const foreground = Color(0xFFE1EAF5);
  static const card = Color(0xFF0D1520);
  static const primary = Color(0xFF22D3A0); // green - online/success/clean
  static const primaryForeground = Color(0xFF060E18);
  static const secondary = Color(0xFF111B28);
  static const secondaryForeground = Color(0xFF8BA3BC);
  static const muted = Color(0xFF111B28);
  static const mutedForeground = Color(0xFF4D6A85);
  static const destructive = Color(0xFFEF4444); // red - delete/uninstall
  static const warning = Color(0xFFF59E0B); // amber - dirty/AUR/caution
  static const cpuAccent = Color(0xFF38BDF8); // cyan - cpu stat
  static const memAccent = Color(0xFFF472B6); // pink - memory stat
  static const netAccent = Color(0xFF818CF8); // violet - network stat
  static const filesAccent = Color(0xFF4F8EF7); // blue - files action
  static const packagesAccent = Color(0xFFC084FC); // purple - packages action
  static const border = Color(0x12FFFFFF); // rgba(255,255,255,0.07)
  static const inputBackground = Color(0xFF111B28);
}

class PrimeTheme {
  static TextStyle mono({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? PrimeColors.foreground,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: PrimeColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: PrimeColors.background,
        primary: PrimeColors.primary,
        onPrimary: PrimeColors.primaryForeground,
        secondary: PrimeColors.secondary,
        onSecondary: PrimeColors.secondaryForeground,
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
        titleTextStyle: mono(fontSize: 20, fontWeight: FontWeight.w500),
        iconTheme: const IconThemeData(color: PrimeColors.mutedForeground),
      ),
      cardTheme: CardThemeData(
        color: PrimeColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: PrimeColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF07101A),
        indicatorColor: PrimeColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return mono(
            fontSize: 9,
            letterSpacing: 1.2,
            color: selected ? PrimeColors.primary : PrimeColors.mutedForeground,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? PrimeColors.primary : PrimeColors.mutedForeground,
            size: 19,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PrimeColors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: PrimeColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: PrimeColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: PrimeColors.primary, width: 1.2),
        ),
        hintStyle: mono(color: PrimeColors.mutedForeground),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PrimeColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: PrimeColors.border),
        ),
      ),
      dividerColor: PrimeColors.border,
    );
  }
}
