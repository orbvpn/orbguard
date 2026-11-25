// A sheet's action has to read whole. Seen on a Pixel 6, where the sheet that
// asks for more access offered "Set up permissi…".

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/presentation/widgets/sheet_panel.dart';

import '../support/real_fonts.dart';

void main() {
  // Whether a label fits is a question about the real typeface.
  setUpAll(loadRealFonts);

  // The narrowest phone the app meets, and a common Android width.
  for (final double width in <double>[320, 411]) {
    testWidgets(
        'the primary action reads whole beside a second one, $width wide',
        (tester) async {
      tester.view.physicalSize = Size(width, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SheetPanel(
              title: 'Enable deeper scanning',
              body: Text('A few extra permissions let a check see more.'),
              secondaryLabel: 'Not now',
              primaryLabel: 'Set up permissions',
            ),
          ),
        ),
      ));

      final RenderParagraph label = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.widgetWithText(BrandButton, 'Set up permissions'),
          matching: find.byType(RichText),
        ),
      );
      expect(label.didExceedMaxLines, isFalse, reason: 'the label was cut off');
    });
  }

  // A dismiss is not an alert: pink punctuates alerts and live things, so
  // "Not now" is quiet neutral ink, and lime stays with the one action.
  for (final bool dark in [true, false]) {
    testWidgets('the second action is neutral, ${dark ? 'dark' : 'light'}',
        (tester) async {
      AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
      addTearDown(() => AppColors.uiBrightness = Brightness.dark);

      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: const Align(
            alignment: Alignment.bottomCenter,
            child: SheetPanel(
              title: 'Enable deeper scanning',
              body: Text('A few extra permissions let a check see more.'),
              secondaryLabel: 'Not now',
              primaryLabel: 'Set up permissions',
            ),
          ),
        ),
      ));

      final RenderParagraph notNow =
          tester.renderObject<RenderParagraph>(find.text('Not now'));
      final Color ink = notNow.text.style!.color!;
      expect(ink, isNot(Brand.pinkInk));
      expect(ink, isNot(AppColors.secondaryInk));
      expect(ink, Brand.text);

      // Still exactly one lime action.
      final Iterable<BrandButton> buttons =
          tester.widgetList<BrandButton>(find.byType(BrandButton));
      expect(buttons.where((b) => b.variant == BrandButtonVariant.primary),
          hasLength(1));
      expect(
          buttons
              .firstWhere((b) => b.variant == BrandButtonVariant.primary)
              .label,
          'Set up permissions');
    });
  }
}
