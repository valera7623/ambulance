import 'package:flutter/material.dart';

ThemeData buildSmpTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B3A5B),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 14),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 18, height: 1.4),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
    ),
  );
}
