// Home's gap card says "See what it is and how to remove it." A phone closes
// apps all the time, so the card has to keep that promise after a restart:
// it shows what the last check found, and starts no new check to do it.

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/widgets/home/results_sheet.dart';

import '../support/shell_harness.dart';

const Map<String, dynamic> _keyboard = {
  'name': 'Suspicious Keyboard App',
  'severity': 'MEDIUM',
  'description': 'Keyboard with internet access',
};

final Finder _checking = find.textContaining('Checking your');

Future<void> _closeTheGap(WidgetTester tester) async {
  await tester.tap(find.text('Close the gap'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('after a restart the gap card shows what the last check found',
      (tester) async {
    await mountShell(tester, autoCheckSpent: true, found: [_keyboard]);

    await _closeTheGap(tester);

    expect(find.byType(LoginScreen), findsNothing,
        reason: 'seeing what was found must not ask for an account');
    expect(_checking, findsNothing,
        reason: 'seeing what was found must not start a new check');
    expect(find.byType(ResultsSheet), findsOneWidget);
    expect(find.text('Your check found 1 thing'), findsOneWidget);
    expect(find.text('Suspicious Keyboard App'), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('with only a count kept, the gap card asks for a fresh check',
      (tester) async {
    await mountShell(tester,
        autoCheckSpent: true, found: [_keyboard], keepFound: false);

    await _closeTheGap(tester);

    // Nothing to show, so a new check is the honest way to see what is
    // there. It is not this person's first, so it passes the credit gate.
    expect(find.byType(ResultsSheet), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    await unmountShell(tester);
  });
}
