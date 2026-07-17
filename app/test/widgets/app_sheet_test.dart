import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/app_sheet.dart';
import 'package:orbguard/presentation/widgets/sheet_panel.dart';

/// Every pop-up presents as an iOS-style modal sheet (slides up, tap-outside /
/// action dismisses) — never a full-screen push or centered dialog.
void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));
    return ctx;
  }

  testWidgets('showAppSheet presents content and the barrier dismisses it',
      (tester) async {
    final ctx = await pumpHost(tester);

    showAppSheet(ctx, child: const Text('SHEET BODY'));
    await tester.pumpAndSettle();
    expect(find.text('SHEET BODY'), findsOneWidget);

    // A modal bottom sheet route is on top (not a full page push).
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // the dimmed barrier above it
    await tester.pumpAndSettle();
    expect(find.text('SHEET BODY'), findsNothing);
  });

  testWidgets('full-height sheet (heightFactor) lays out a full page cleanly',
      (tester) async {
    final ctx = await pumpHost(tester);

    // A full page (Scaffold, like FindingsScreen) inside the sheet at 0.94.
    showAppSheet(
      ctx,
      heightFactor: 0.94,
      child: const Scaffold(body: Center(child: Text('FULL PAGE SHEET'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('FULL PAGE SHEET'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the bounded-height Expanded path must not overflow/throw');
  });

  testWidgets('SheetPanel primary action dismisses the sheet then fires',
      (tester) async {
    final ctx = await pumpHost(tester);
    var fired = false;

    showAppSheet(
      ctx,
      child: SheetPanel(
        title: 'Enable deeper scanning',
        body: const Text('body'),
        secondaryLabel: 'Not now',
        primaryLabel: 'Set up permissions',
        onPrimary: () => fired = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable deeper scanning'), findsOneWidget);

    await tester.tap(find.text('Set up permissions'));
    await tester.pumpAndSettle();

    expect(fired, isTrue);
    expect(find.text('Enable deeper scanning'), findsNothing,
        reason: 'the sheet dismisses before the action runs');
  });
}
