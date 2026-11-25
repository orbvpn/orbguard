// BalancedText narrows a wrapped headline until its lines are near the same
// length. Tests run with the Ahem font, where every glyph is a square as wide
// as the font size, so the widths below can be worked out by hand.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/balanced_text.dart';

Future<Size> _sizeOf(WidgetTester tester, String text, double width) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width,
          child: Center(
            child: BalancedText(text, style: const TextStyle(fontSize: 10)),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(Text));
}

void main() {
  testWidgets('a wrapped line is evened out instead of leaving one word over',
      (tester) async {
    // In 100: "aaaa bbbb" (90) then "cc" alone. Evened out: "aaaa" over
    // "bbbb cc", which is 70 wide.
    final size = await _sizeOf(tester, 'aaaa bbbb cc', 100);

    expect(size.width, closeTo(70, 1),
        reason: 'the search stops within a pixel of the tightest fit');
    expect(size.height, 20, reason: 'still two lines, never a third');
  });

  testWidgets('text that fits on one line is left alone', (tester) async {
    final size = await _sizeOf(tester, 'aaaa bb', 100);

    expect(size, const Size(70, 10));
  });
}
