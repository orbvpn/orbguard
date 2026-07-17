import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/scan/findings_screen.dart';
import 'package:orbguard/screens/scan/privacy_check_screen.dart';
import 'package:orbguard/screens/scanning_screen.dart' show ScanResult;
import 'package:orbguard/services/security/device_scan_service.dart';

/// Honest scan theatre + findings.
///
/// 1. PrivacyCheckScreen "names the work" in PLAIN LANGUAGE (the labor
///    illusion that makes a scan feel trustworthy) — never the raw analyst
///    stage names like "Accessibility abuse".
/// 2. FindingsScreen states the real finding count and offers a fix path.
/// 3. The all-clear is honest proof: it counts only checks that RAN, and
///    reports unavailable checks separately — never as passed.
void main() {
  testWidgets('privacy check names each stage in plain language, not jargon',
      (tester) async {
    // A scan that stays on one running stage so we can read the label.
    final never = Completer<List<Map<String, dynamic>>>();

    await tester.pumpWidget(MaterialApp(
      home: PrivacyCheckScreen(
        onScanWithProgress: (onProgress) {
          onProgress(const DeviceScanProgress(
            stageIndex: 0,
            totalStages: 3,
            stageName: 'Accessibility abuse', // raw analyst name
            stageCompleted: false,
            threatsFound: 0,
          ));
          return never.future;
        },
      ),
    ));

    await tester.pump(); // start scan + first progress event
    await tester.pump(const Duration(milliseconds: 50));

    // The screen names the work being done…
    expect(find.text('Running your privacy check'), findsOneWidget);
    // …the consumer sees the plain-language label for the running check…
    expect(find.text('Scanning for spyware & stalkerware'), findsOneWidget);
    // …and never the raw analyst stage name.
    expect(find.text('Accessibility abuse'), findsNothing);
  });

  testWidgets('findings screen renders a card per threat and a fix path',
      (tester) async {
    // Tall surface so the cards and the CTA are all on-stage.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    var fixAllCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: FindingsScreen(
        threats: const [
          {
            'name': 'Screen recording app found',
            'severity': 'HIGH',
            'description': 'An app on this device can capture your screen.',
          },
          {
            'name': 'Location shared in the background',
            'severity': 'MEDIUM',
            'description': 'An app keeps reading your location while closed.',
          },
        ],
        checksRun: 11,
        onFixAll: () => fixAllCalls++,
      ),
    ));
    await tester.pump();

    // Honest headline with the real count.
    expect(find.textContaining('found 2 things'), findsOneWidget);
    // One card per finding, in plain language.
    expect(find.text('Screen recording app found'), findsOneWidget);
    expect(find.text('Location shared in the background'), findsOneWidget);

    // The lime CTA fires the fix path.
    await tester.tap(find.text('Fix these'));
    await tester.pump();
    expect(fixAllCalls, 1);
  });

  testWidgets('all clear proves what ran and reports unavailable separately',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FindingsScreen(
        threats: [],
        checksRun: 12,
        checksUnavailable: 3,
      ),
    ));
    await tester.pump();

    expect(find.text('All clear'), findsOneWidget);
    // Real proof of the work: only checks that genuinely ran…
    expect(find.textContaining('12 checks ran clean'), findsOneWidget);
    // …and unavailable checks stated honestly, never counted as passed.
    expect(
      find.textContaining("3 checks aren't available on this device"),
      findsOneWidget,
    );
  });

  testWidgets('pops the same ScanResult contract as ScanningScreen',
      (tester) async {
    ScanResult? popped;
    final threat = <String, dynamic>{
      'name': 'Test finding',
      'severity': 'LOW',
      'description': 'x',
    };

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            child: const Text('go'),
            onPressed: () async {
              popped = await Navigator.push<ScanResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivacyCheckScreen(
                    onScanWithProgress: (onProgress) async {
                      const stages = ['Memory', 'File system'];
                      for (var i = 0; i < stages.length; i++) {
                        onProgress(DeviceScanProgress(
                          stageIndex: i,
                          totalStages: stages.length,
                          stageName: stages[i],
                          stageCompleted: false,
                          threatsFound: i == 0 ? 0 : 1,
                        ));
                        onProgress(DeviceScanProgress(
                          stageIndex: i,
                          totalStages: stages.length,
                          stageName: stages[i],
                          stageCompleted: true,
                          threatsFound: 1,
                          // Second stage couldn't run — still a COMPLETED
                          // stage, mirroring ScanningScreen's counter.
                          stageError:
                              i == 1 ? 'not supported on this device' : null,
                        ));
                      }
                      return [threat];
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump(); // push the route
    await tester.pump(const Duration(milliseconds: 350)); // route transition
    await tester.pump(const Duration(milliseconds: 900)); // completion beat
    await tester.pump(const Duration(milliseconds: 350)); // pop transition

    expect(popped, isNotNull);
    // Real threats passed through untouched…
    expect(popped!.threats, hasLength(1));
    expect(popped!.threats.single['name'], 'Test finding');
    // …and itemsScanned = stages that completed (same as ScanningScreen,
    // including the stage that reported it couldn't run).
    expect(popped!.itemsScanned, 2);
  });
}
