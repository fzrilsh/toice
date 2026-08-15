/// Toice theme: built for a gloved rider glancing at a bar-mounted phone in
/// direct sun at 60-80 km/h (ADR context, Phase 4.5). Every choice serves
/// legibility under those constraints, not decoration.
///
/// - Pure black / pure white grounds for maximum luminance contrast in sunlight.
/// - Hi-vis amber accent (safety-vest yellow) on the one primary action per
///   screen; hazard red for destructive/error states.
/// - Oversized, heavy type and 64px minimum touch targets for gloved taps.
///
/// ponytail: no custom font dependency. Under a helmet in sun, size + weight +
/// contrast carry legibility, not typeface personality; add a display face only
/// if field testing shows Roboto isn't enough.
library;

import 'package:flutter/material.dart';

const _asphalt = Color(0xFF0A0A0A); // near-black ground, dark mode
const _roadLine = Color(0xFFFFFFFF); // white ground, light mode
const _hiVis = Color(0xFFFFD400); // safety-amber signature accent
const _hazard = Color(0xFFFF3B30); // destructive + error

/// Minimum tap target for a gloved hand (Material's default is 48).
const kGloveTarget = 64.0;

ThemeData toiceLightTheme() => _build(Brightness.light);
ThemeData toiceDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ground = dark ? _asphalt : _roadLine;
  final ink = dark ? _roadLine : _asphalt;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: _hiVis,
    onPrimary: _asphalt, // black text on amber is the most readable pairing
    secondary: _hiVis,
    onSecondary: _asphalt,
    error: _hazard,
    onError: _roadLine,
    surface: ground,
    onSurface: ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ground,
    // Glove-friendly: never shrink targets below kGloveTarget.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  final display = base.textTheme.apply(bodyColor: ink, displayColor: ink);

  return base.copyWith(
    textTheme: display.copyWith(
      // Oversized, heavy scale for a glance at speed.
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: display.bodyLarge?.copyWith(fontSize: 18),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ground,
      foregroundColor: ink,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _hiVis,
        foregroundColor: _asphalt,
        minimumSize: const Size.fromHeight(kGloveTarget),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink, width: 2),
        minimumSize: const Size.fromHeight(kGloveTarget),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _hazard, // text buttons are the End-trip / cancel slot
        minimumSize: const Size(kGloveTarget, kGloveTarget),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: ground, fontSize: 16),
      actionTextColor: _hiVis,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
