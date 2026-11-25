// Lime-coloured text and icons on the light theme have to be readable: at
// least 4.5 to 1 (WCAG AA for body text) against the light background and
// both light surfaces.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUp(() => AppColors.uiBrightness = Brightness.light);
  tearDown(() => AppColors.uiBrightness = Brightness.dark);

  test('every lime ink reads at 4.5 to 1 or better on light', () {
    final Map<String, Color> inks = {
      'Brand.limeInk': Brand.limeInk,
      'Brand.navActive': Brand.navActive,
      'AppColors.accentInk': AppColors.accentInk,
      'AppColors.accentOnLight': AppColors.accentOnLight,
      'AppColors.brandLight': AppColors.brandLight,
      'AppTheme.light active ink':
          AppTheme.light.colorScheme.onPrimaryContainer,
    };
    final Map<String, Color> grounds = {
      'background': Brand.bg,
      'surface': Brand.surface,
      'surface2': Brand.surface2,
    };
    for (final MapEntry<String, Color> ink in inks.entries) {
      for (final MapEntry<String, Color> ground in grounds.entries) {
        expect(_contrast(ink.value, ground.value), greaterThanOrEqualTo(4.5),
            reason: '${ink.key} on ${ground.key}');
      }
    }
  });

  test('the light lime ink is #4A7000', () {
    expect(Brand.limeInk, const Color(0xFF4A7000));
    expect(AppColors.accentInk, const Color(0xFF4A7000));
  });
}
