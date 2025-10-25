import 'package:flutter/material.dart';

// Matches cinna-tracker-web palette from globals.css
class _WebTokensLight {
  static const background = Color(0xFFFFFFFF); // --background
  static const foreground = Color(0xFF0A0A0A); // --foreground
  static const muted = Color(0xFF4B5563); // --muted
  static const card = Color(0xFFFFFFFF); // --card
  static const cardContrast = Color(0xFFF8FAFC); // --card-contrast
  static const border = Color(0xFFE5E7EB); // --border
  static const ring = Color(0xFF16A34A); // --ring
  static const accent = Color(0xFF059669); // --accent
}

class _WebTokensDark {
  static const background = Color(0xFF0B0C0F);
  static const foreground = Color(0xFFE7E9EE);
  static const muted = Color(0xFF9AA3B2);
  static const card = Color(0xFF0F1115);
  static const cardContrast = Color(0xFF12151B);
  static const border = Color(0xFF1B1F2A);
  static const ring = Color(0xFF22C55E);
  static const accent = Color(0xFF10B981);
}

ThemeData buildLightTheme() {
  final colorScheme = const ColorScheme.light(
    primary: _WebTokensLight.accent,
    secondary: _WebTokensLight.ring,
    background: _WebTokensLight.background,
    surface: _WebTokensLight.card,
    surfaceVariant: _WebTokensLight.cardContrast,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onBackground: _WebTokensLight.foreground,
    onSurface: _WebTokensLight.foreground,
    outline: _WebTokensLight.border,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _WebTokensLight.background,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: _WebTokensLight.background,
      foregroundColor: _WebTokensLight.foreground,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensLight.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensLight.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensLight.ring, width: 1.5),
      ),
      hintStyle: const TextStyle(color: _WebTokensLight.muted),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      labelStyle: const TextStyle(color: _WebTokensLight.foreground),
      backgroundColor: _WebTokensLight.cardContrast,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _WebTokensLight.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _WebTokensLight.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: _WebTokensLight.border, thickness: 1),
    bottomAppBarTheme: const BottomAppBarThemeData(color: _WebTokensLight.background),
  );
}

ThemeData buildDarkTheme() {
  final colorScheme = const ColorScheme.dark(
    primary: _WebTokensDark.accent,
    secondary: _WebTokensDark.ring,
    background: _WebTokensDark.background,
    surface: _WebTokensDark.card,
    surfaceVariant: _WebTokensDark.cardContrast,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onBackground: _WebTokensDark.foreground,
    onSurface: _WebTokensDark.foreground,
    outline: _WebTokensDark.border,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _WebTokensDark.background,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: _WebTokensDark.background,
      foregroundColor: _WebTokensDark.foreground,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensDark.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensDark.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _WebTokensDark.ring, width: 1.5),
      ),
      hintStyle: const TextStyle(color: _WebTokensDark.muted),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      labelStyle: const TextStyle(color: _WebTokensDark.foreground),
      backgroundColor: _WebTokensDark.cardContrast,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _WebTokensDark.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _WebTokensDark.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: _WebTokensDark.border, thickness: 1),
    bottomAppBarTheme: const BottomAppBarThemeData(color: _WebTokensDark.background),
  );
}


