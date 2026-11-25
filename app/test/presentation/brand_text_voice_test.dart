// The display voice: the bigger the type, the wider and lighter Archivo runs.
//
// The width lives in one place (BrandVoice, read by BrandText). These tests hold
// the rule rather than its numbers, so the steps can be tuned freely, while a
// stray edit that flattens the voice back to the font's default width fails.
// They also guard the two things the voice must never touch: the text and data
// recipes, and the fonts of non-Latin scripts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/glass_theme.dart';

double? axis(TextStyle style, String tag) {
  for (final v in style.fontVariations ?? const <FontVariation>[]) {
    if (v.axis == tag) return v.value;
  }
  return null;
}

void main() {
  tearDown(() => Brand.script = BrandScript.latin);

  group('display voice in Latin script', () {
    test('the bigger the step, the wider and lighter Archivo runs', () {
      final display = BrandText.display();
      final h2 = BrandText.h2();
      final heading = BrandText.heading();
      final numeral = BrandText.numeral();

      final widths =
          [display, h2, heading, numeral].map((s) => axis(s, 'wdth')!).toList();
      final weights =
          [display, h2, heading, numeral].map((s) => axis(s, 'wght')!).toList();

      expect(widths, everyElement(greaterThan(100)),
          reason: '100 is the flat width the font ships with');
      expect(widths[0], greaterThan(widths[1]));
      expect(widths[1], greaterThan(widths[2]));
      expect(widths[2], greaterThan(widths[3]));
      expect(weights[0], lessThan(weights[1]));
      expect(weights[1], lessThan(weights[2]));
      expect(weights[2], lessThan(weights[3]));
      for (final style in [display, h2, heading, numeral]) {
        expect(style.fontFamily, 'Archivo');
      }
    });

    test('tracking tightens in proportion to the size', () {
      final small = BrandText.display(size: 20).letterSpacing!;
      final large = BrandText.display(size: 40).letterSpacing!;

      expect(small, lessThan(0));
      expect(large, closeTo(small * 2, 1e-9));
    });

    test('numerals use lining figures and sit proportionally at rest', () {
      final style = BrandText.numeral(size: 35);

      expect(style.fontFeatures, contains(const FontFeature.liningFigures()));
      expect(style.fontFeatures,
          isNot(contains(const FontFeature.tabularFigures())));
    });

    test('numerals go tabular when asked, so a counting score holds still', () {
      final style = BrandText.numeral(size: 35, tabular: true);

      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('a caller that names a weight keeps it, at the step width', () {
      final plain = BrandText.heading(size: 24);
      final heavy = BrandText.heading(size: 24, weight: FontWeight.w800);

      expect(axis(heavy, 'wght'), 800);
      expect(heavy.fontWeight, FontWeight.w800);
      expect(axis(heavy, 'wdth'), axis(plain, 'wdth'));
    });

    test('hero-size display sets tight, app-size display gets air', () {
      expect(BrandText.display(size: 44).height, 1.04);
      expect(BrandText.display(size: 28).height, 1.12);
    });
  });

  test('a bare size maps to its step: 30 up display, 22 up h2, else heading',
      () {
    expect(BrandVoice.forSize(44), BrandVoice.display);
    expect(BrandVoice.forSize(30), BrandVoice.display);
    expect(BrandVoice.forSize(29.5), BrandVoice.h2);
    expect(BrandVoice.forSize(22), BrandVoice.h2);
    expect(BrandVoice.forSize(21.5), BrandVoice.heading);
    expect(BrandVoice.forSize(16), BrandVoice.heading);
  });

  test('Material headline slots speak in the same voice, by their size', () {
    final text = AppTheme.dark.textTheme;

    expect(axis(text.displayLarge!, 'wdth'), BrandVoice.display.width);
    expect(axis(text.displaySmall!, 'wght'), BrandVoice.display.weight);
    expect(axis(text.headlineMedium!, 'wdth'), BrandVoice.h2.width);
    expect(axis(text.headlineSmall!, 'wdth'), BrandVoice.heading.width);
    expect(text.titleLarge!.fontVariations, isNull,
        reason: 'titles are IBM Plex Sans, which has no width to set');
    expect(axis(GlassTheme.headingStyle(), 'wdth'), BrandVoice.heading.width);
  });

  test('text and data recipes carry no width axis', () {
    for (final style in [
      BrandText.title(),
      BrandText.body(),
      BrandText.label(),
      BrandText.mono(),
    ]) {
      expect(style.fontVariations, isNull, reason: '${style.fontFamily}');
    }
  });

  group('non-Latin scripts keep their own fonts untouched', () {
    test('Persian display stays Vazirmatn 800 with no axes and no tracking',
        () {
      Brand.script = BrandScript.persian;

      final style = BrandText.display(size: 28);

      expect(style.fontFamily, 'Vazirmatn');
      expect(style.fontVariations, isNull);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.letterSpacing, 0);
    });

    test('Arabic headings stay clamped to a real 700 with no axes', () {
      Brand.script = BrandScript.arabic;

      for (final style in [
        BrandText.display(),
        BrandText.h2(),
        BrandText.heading(),
        BrandText.numeral(),
      ]) {
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontVariations, isNull);
      }
    });
  });
}
