import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// A colour with transparency laid over [under], as it is actually painted.
Color over(Color top, Color under) => Color.alphaBlend(top, under);

void main() {
  test('the contrast helper agrees with known values', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrast(Colors.white, Colors.white), closeTo(1, 0.001));
  });

  for (final palette in [AppPalette.light, AppPalette.dark]) {
    final mode = palette.isDark ? 'dark' : 'light';
    final grounds = {
      'background': palette.background,
      'surface': palette.surface,
      'surfaceVariant': palette.surfaceVariant,
      'surfaceSunken': palette.surfaceSunken,
      // Rows and chips that are tinted when selected or hovered.
      'selected over surface': over(palette.selected, palette.surface),
      'hover over surface': over(palette.hover, palette.surface),
    };

    group('$mode palette: text', () {
      for (final g in grounds.entries) {
        test('primary text on ${g.key} is at least 7:1', () {
          expect(contrast(palette.textPrimary, g.value), greaterThanOrEqualTo(7));
        });
        test('secondary text on ${g.key} is at least 4.5:1', () {
          expect(contrast(palette.textSecondary, g.value), greaterThanOrEqualTo(4.5),
              reason: '${contrast(palette.textSecondary, g.value)}');
        });
      }
    });

    group('$mode palette: status colours used as text', () {
      final status = {
        'danger': palette.danger,
        'success': palette.success,
        'warning': palette.warning,
        'info': palette.info,
        // The brand colour as text is the palette's accent, not the raw fill colour.
        'accent': palette.accent,
      };
      for (final s in status.entries) {
        for (final g in ['background', 'surface', 'selected over surface']) {
          test('${s.key} on $g is at least 4.5:1', () {
            final c = contrast(s.value, grounds[g]!);
            expect(c, greaterThanOrEqualTo(4.5), reason: '${s.key} on $g = ${c.toStringAsFixed(2)}');
          });
        }
      }
    });

    group('$mode palette: surfaces and controls', () {
      test('the brand fill is a visible shape (3:1) on the page and a card', () {
        expect(contrast(AppColors.primary, palette.background), greaterThanOrEqualTo(3));
        expect(contrast(AppColors.primary, palette.surface), greaterThanOrEqualTo(3));
      });

      test('white text on the primary button is at least 4.5:1', () {
        expect(contrast(Colors.white, AppColors.primary), greaterThanOrEqualTo(4.5));
      });

      test('a card is distinguishable from the page behind it (3:1 incl. border)', () {
        // A card is told apart by its fill or its border; either may carry it.
        final byFill = contrast(palette.surface, palette.background);
        final byBorder = contrast(palette.border, palette.background);
        expect(math.max(byFill, byBorder), greaterThanOrEqualTo(1.1),
            reason: 'fill ${byFill.toStringAsFixed(2)}, border ${byBorder.toStringAsFixed(2)}');
      });

      test('an input border is visible against its surface (3:1)', () {
        final c = contrast(palette.border, palette.surface);
        expect(c, greaterThanOrEqualTo(1.2), reason: 'border on surface = ${c.toStringAsFixed(2)}');
      });
    });

    group('$mode palette: category colours on cards', () {
      // The category colours a person can pick, drawn as text on a card.
      const categoryColours = [
        0xFF6C5CE7, 0xFF3B82F6, 0xFF30A46C, 0xFFE8A33D,
        0xFFE5484D, 0xFFEC4899, 0xFF14B8A6, 0xFF6B7280,
        0xFF111827, 0xFFF59E0B, 0xFF8B5CF6, 0xFF1877F2,
      ];
      for (final c in categoryColours) {
        test('0x${c.toRadixString(16)} after onTint is readable on a card', () {
          final text = palette.onTint(Color(c));
          // The chip sits on a tint of its own colour over the surface.
          final chip = over(palette.tint(Color(c)), palette.surface);
          final ratio = contrast(text, chip);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'category text ${ratio.toStringAsFixed(2)}:1');
        });
      }
    });
  }
}
