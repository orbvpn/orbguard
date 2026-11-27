// Where a sheet opens.
//
// On a phone a sheet slides up over the whole screen. On a foldable or a
// tablet the shell names the pane sheets belong to, and every sheet opens
// there, whichever pane asked for it, so a sheet never lies across the
// hinge. On a desktop window a sheet is a column of its own in the middle,
// never a strip across the whole window.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/app_sheet.dart';

const Key _body = Key('sheet-body');

Widget _opener(String label, {double? heightFactor}) => Builder(
      builder: (context) => TextButton(
        onPressed: () => showAppSheet<void>(
          context,
          heightFactor: heightFactor,
          child: const SizedBox(key: _body, height: 200, width: 2000),
        ),
        child: Text(label),
      ),
    );

Future<void> _open(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {});

  testWidgets('with no host, a sheet spans the screen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _opener('Open'))));
    await _open(tester, 'Open');
    expect(tester.getSize(find.byKey(_body)).width, 400);
  });

  testWidgets('with a pane host, a sheet from the other pane opens in it',
      (tester) async {
    tester.view.physicalSize = const Size(840, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GlobalKey<NavigatorState> pane = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SheetHost(
          navigator: pane,
          child: Row(
            children: [
              SizedBox(width: 420, child: _opener('From the ring')),
              SizedBox(
                width: 420,
                child: Navigator(
                  key: pane,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await _open(tester, 'From the ring');
    final Rect sheet = tester.getRect(find.byKey(_body));
    expect(sheet.left, greaterThanOrEqualTo(420));
    expect(sheet.right, lessThanOrEqualTo(840));
  });

  testWidgets('a desktop sheet is a centred column, never the full width',
      (tester) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SheetHost(
          maxWidth: 480,
          maxHeightFactor: 0.9,
          child: _opener('Open', heightFactor: 0.94),
        ),
      ),
    ));
    await _open(tester, 'Open');
    final Rect sheet = tester.getRect(find.byKey(_body));
    expect(sheet.width, 480);
    expect(sheet.center.dx, closeTo(590, 0.5));
    // 0.94 of the window would be 714; the host allows 0.9 of it at most.
    final double height = tester
        .getSize(find.ancestor(
            of: find.byKey(_body), matching: find.byType(ClipRRect)))
        .height;
    expect(height, lessThanOrEqualTo(760 * 0.9));
  });
}
