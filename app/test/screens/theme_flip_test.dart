// Changing the theme repaints every tab at once.
//
// The brand tokens read one global, not the widget tree, so a widget built
// `const` is not rebuilt by a theme change unless its build asks for the
// theme. One that does not keeps the old theme's ink until something else
// rebuilds it: dark words on a dark card, right where the switch lives.
//
// Each test changes the theme with a tab open, notes what is painted, then
// forces every widget to build again. Nothing may look different after that.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/shell_harness.dart';

/// What the screen paints, as far as a theme decides it: every run of text
/// with its styles, every box decoration, every icon tint.
List<String> _painted(WidgetTester tester) => [
      for (final RichText t
          in tester.widgetList<RichText>(find.byType(RichText)))
        'text ${t.text.toStringDeep()}',
      for (final DecoratedBox b
          in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
        'box ${b.decoration}',
      for (final SvgPicture s
          in tester.widgetList<SvgPicture>(find.byType(SvgPicture)))
        'icon ${s.bytesLoader} ${s.colorFilter}',
    ];

void _buildEverythingAgain(WidgetTester tester) {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
}

/// The first few things in [now] that were not painted that way [before].
List<String> _changed(List<String> before, List<String> now) {
  final List<String> left = List.of(before);
  final List<String> out = [];
  for (final String item in now) {
    if (!left.remove(item)) out.add(item);
  }
  return out.take(6).toList();
}

void main() {
  for (final String tab in ['Home', 'Protect', 'Check', 'Me']) {
    for (final ThemeMode to in [ThemeMode.light, ThemeMode.dark]) {
      final ThemeMode from =
          to == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;

      testWidgets('$tab repaints when the theme turns ${to.name}',
          (tester) async {
        final ShellUnderTest shell = await mountShell(tester,
            checked: true, autoCheckSpent: true, themed: true);
        await tester.runAsync(() => shell.settings.setThemeMode(from));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        if (tab != 'Home') {
          await tester.tap(find.text(tab).last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        }

        await tester.runAsync(() => shell.settings.setThemeMode(to));
        await tester.pump();
        // The theme change eases over 200 ms.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        final List<String> shown = _painted(tester);

        _buildEverythingAgain(tester);
        await tester.pump();
        final List<String> rebuilt = _painted(tester);

        expect(_changed(shown, rebuilt), isEmpty,
            reason: 'kept the ${from.name} theme until rebuilt');

        await unmountShell(tester);
      });
    }
  }
}
