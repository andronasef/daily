import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Blue accent + card surfaces, echoing the existing leyaana / god-work pages.
/// Cairo via google_fonts (cached; falls back to the system Arabic font offline).
ThemeData buildTheme(Brightness brightness) {
  const seed = Color(0xFF1877F2);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  );
  return base.copyWith(
    textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: base.dividerColor),
      ),
    ),
  );
}
