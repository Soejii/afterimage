import 'package:flutter/material.dart';

class AfterimageTheme {
  static const accent = Color(0xFFB8F1D3);
  static const accentStrong = Color(0xFF6FD6A1);
  static const canvas = Color(0xFF0C1011);
  static const panel = Color(0xFF151B1C);
  static const panelRaised = Color(0xFF1B2324);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentStrong,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: const Color(0xFF082016),
      secondary: accentStrong,
      onSecondary: const Color(0xFF082016),
      surface: canvas,
      surfaceContainerHighest: panel,
      outline: const Color(0xFF465352),
      outlineVariant: const Color(0xFF2B3434),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF26302F)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF2B3434)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: accentStrong, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: const BorderSide(color: Color(0xFF465352)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelRaised,
        selectedColor: const Color(0xFF2C5947),
        side: const BorderSide(color: Color(0xFF354140)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF26302F),
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: Color(0xFF2C5947),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
