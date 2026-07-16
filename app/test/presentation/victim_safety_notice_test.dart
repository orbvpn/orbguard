import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/presentation/widgets/victim_safety_notice.dart';

void main() {
  group('VictimSafety.mentionsSurveillance', () {
    test('flags stalkerware / spyware / monitoring vocabulary', () {
      expect(VictimSafety.mentionsSurveillance(['Known stalkerware']), isTrue);
      expect(VictimSafety.mentionsSurveillance(['SpyWare family: X']), isTrue);
      expect(
        VictimSafety.mentionsSurveillance(['This app can monitor your messages']),
        isTrue,
      );
      expect(
        VictimSafety.mentionsSurveillance(['Hidden phone tracker']),
        isTrue,
      );
    });

    test('does not flag benign findings or null/empty signals', () {
      expect(VictimSafety.mentionsSurveillance(['Outdated TLS certificate']), isFalse);
      expect(VictimSafety.mentionsSurveillance([null, '', '   -  ']), isFalse);
    });
  });

  testWidgets('VictimSafetyNotice shows the calm removal warning', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: VictimSafetyNotice()),
      ),
    ));
    await tester.pump();

    expect(find.text('Before you remove this'), findsOneWidget);
    expect(
      find.textContaining('may alert the person'),
      findsOneWidget,
    );
    expect(find.text('Quick Exit'), findsOneWidget);
  });

  testWidgets('Quick Exit returns to the neutral first route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: SingleChildScrollView(child: VictimSafetyNotice()),
                    ),
                  ),
                ),
                child: const Text('open sensitive view'),
              ),
            ),
          ),
        ),
      ),
    );

    // Neutral home is showing.
    expect(find.text('open sensitive view'), findsOneWidget);

    // Push the sensitive (stalkerware) view.
    await tester.tap(find.text('open sensitive view'));
    await tester.pumpAndSettle();
    expect(find.text('Before you remove this'), findsOneWidget);
    expect(find.text('open sensitive view'), findsNothing);

    // Duress Quick Exit pops straight back to the neutral first route.
    await tester.tap(find.text('Quick Exit'));
    await tester.pumpAndSettle();
    expect(find.text('open sensitive view'), findsOneWidget);
    expect(find.text('Before you remove this'), findsNothing);
  });
}
