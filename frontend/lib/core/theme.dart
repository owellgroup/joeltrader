import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B0F14);
  static const panel = Color(0xFF131A22);
  static const panel2 = Color(0xFF1A232D);
  static const line = Color(0xFF263341);
  static const text = Color(0xFFE6EDF3);
  static const muted = Color(0xFF8B98A5);
  static const brand = Color(0xFF2F5BFF); // from the JMT logo blue
  static const gold = Color(0xFFFAEB00);  // from the JMT logo yellow
  static const up = Color(0xFF2EBD85);
  static const down = Color(0xFFF6465D);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(primary: C.brand, secondary: C.gold, surface: C.panel, error: C.down),
    cardColor: C.panel,
    dividerColor: C.line,
    appBarTheme: const AppBarTheme(backgroundColor: C.panel, elevation: 0, foregroundColor: C.text),
    drawerTheme: const DrawerThemeData(backgroundColor: C.panel),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.panel2,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: C.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: C.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: C.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
    chipTheme: base.chipTheme.copyWith(backgroundColor: C.panel2, side: const BorderSide(color: C.line)),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
  );
}
