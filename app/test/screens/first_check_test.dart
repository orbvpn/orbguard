// The first check is the app's first promise: "One tap. The check runs on
// this phone." These tests hold the shell to it.

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/scan/privacy_check_screen.dart';

import '../support/shell_harness.dart';

/// Home while a check runs on it.
final Finder _checking = find.textContaining('Checking your');

void main() {
  testWidgets('the automatic first check waits until coverage is known',
      (tester) async {
    await mountShell(tester);

    expect(find.text('Enable deeper scanning'), findsNothing,
        reason: 'coverage was judged before the device had answered');
    expect(_checking, findsOneWidget);
    expect(find.byType(PrivacyCheckScreen), findsNothing,
        reason: 'the check runs on Home, not on a page of its own');

    await unmountShell(tester);
  });

  testWidgets('the first check stays free when it starts from the button',
      (tester) async {
    await mountShell(tester, autoCheckSpent: true);

    await tester.tap(find.text('Run my first check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsNothing,
        reason: 'the first check must not ask for an account');
    expect(_checking, findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('a later check from the button still passes the credit gate',
      (tester) async {
    await mountShell(tester, checked: true, autoCheckSpent: true);

    await tester.tap(find.text('Check now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Signed out, so the gate asks for an account before any check runs.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_checking, findsNothing);

    await unmountShell(tester);
  });
}
