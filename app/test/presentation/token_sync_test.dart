// The brand tokens follow the theme, for every widget.
//
// A token reads one global, not the widget tree. A widget built `const`
// that never asks for the theme has nothing to tell it the theme changed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';

/// Reads a token and nothing else: no theme, no media query.
class _Words extends StatelessWidget {
  const _Words();

  @override
  Widget build(BuildContext context) =>
      Text('words', style: TextStyle(color: Brand.text));
}

class _App extends StatelessWidget {
  const _App(this.mode);

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        builder: (context, child) {
          AppColors.syncWith(context);
          return child!;
        },
        home: const _Words(),
      );
}

Color? _ink(WidgetTester tester) =>
    tester.widget<Text>(find.text('words')).style?.color;

void main() {
  tearDown(() => AppColors.uiBrightness = Brightness.dark);

  for (final ThemeMode to in [ThemeMode.light, ThemeMode.dark]) {
    final ThemeMode from =
        to == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;

    testWidgets('a const widget takes the ${to.name} ink when the theme turns',
        (tester) async {
      await tester.pumpWidget(_App(from));
      final Color? before = _ink(tester);

      await tester.pumpWidget(_App(to));
      // The theme change eases over 200 ms.
      await tester.pump(const Duration(milliseconds: 400));

      expect(AppColors.uiBrightness,
          to == ThemeMode.light ? Brightness.light : Brightness.dark);
      expect(_ink(tester), Brand.text);
      expect(_ink(tester), isNot(before));
    });
  }

  testWidgets('the first frame already has the right ink', (tester) async {
    await tester.pumpWidget(const _App(ThemeMode.light));

    expect(AppColors.uiBrightness, Brightness.light);
    expect(_ink(tester), Brand.text);
  });
}
