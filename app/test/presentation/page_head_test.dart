import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/presentation/widgets/page_head.dart';

import '../support/real_fonts.dart';

/// The head of a tab: its name, read out as a heading, and one line under it.
void main() {
  setUpAll(loadRealFonts);

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 390}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
    ));
  }

  testWidgets('names the tab as a heading, with one line under it',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
        tester,
        const PageHead(
            title: 'Check', subtitle: 'Not sure about something? Ask.'));

    expect(find.text('Check'), findsOneWidget);
    expect(find.text('Not sure about something? Ask.'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Check')),
      matchesSemantics(label: 'Check', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('is at least a press target tall, with or without a line',
      (tester) async {
    await pump(tester, const PageHead(title: 'Me'));
    expect(tester.getSize(find.byType(PageHead)).height,
        greaterThanOrEqualTo(PageHead.minHeight));
  });

  testWidgets('keeps a long line on the screen at 320 wide', (tester) async {
    await pump(
      tester,
      const PageHead(
        title: 'Protect',
        subtitle: 'Six shields. Each one tells you what it did.',
        trailing: SizedBox.square(dimension: 44),
      ),
      width: 320,
    );
    expect(tester.takeException(), isNull);
    final RenderBox box = tester.renderObject(find.byType(PageHead));
    expect(box.size.width, lessThanOrEqualTo(320));
  });
}
