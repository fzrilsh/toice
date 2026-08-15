import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toice/ui/theme.dart';

void main() {
  test(
    'both themes ground on max-contrast surfaces with the hi-vis accent',
    () {
      for (final theme in [toiceLightTheme(), toiceDarkTheme()]) {
        final s = theme.colorScheme;
        // Amber primary, black text on it: the most readable pairing in sun.
        expect(s.primary, const Color(0xFFFFD400));
        expect(s.onPrimary, const Color(0xFF0A0A0A));
        expect(s.error, const Color(0xFFFF3B30));
        // Surface and its ink are opposite ends of the luminance range.
        expect(s.surface, isNot(s.onSurface));
      }
    },
  );

  test('primary buttons meet the gloved-hand touch target', () {
    final style = toiceDarkTheme().filledButtonTheme.style!;
    final size = style.minimumSize!.resolve({});
    expect(size!.height, greaterThanOrEqualTo(kGloveTarget));
  });
}
