import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/screens/playbooks/playbooks_screen.dart';

void main() {
  testWidgets('a failed load is not shown as an empty playbook list',
      (tester) async {
    // The API client is not initialized in this test, so the load fails
    // before any request is made.
    await tester.pumpWidget(const MaterialApp(home: PlaybooksScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Playbooks Unavailable'), findsOneWidget);
    expect(find.text('No Playbooks'), findsNothing);
  });
}
