import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/scanning_screen.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

/// P1.5 — the checkup ritual must "name the work" in PLAIN LANGUAGE (the labor
/// illusion that makes a scan feel trustworthy), never expose the raw analyst
/// stage names like "Accessibility abuse".
void main() {
  testWidgets('names each check in plain language, not jargon', (tester) async {
    // A scan that stays on one running stage so we can read the label.
    final never = Completer<List<Map<String, dynamic>>>();

    await tester.pumpWidget(MaterialApp(
      home: ScanningScreen(
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

    // The consumer sees the plain-language label…
    expect(find.text('Scanning for spyware & stalkerware'), findsOneWidget);
    // …and never the raw analyst stage name.
    expect(find.text('Accessibility abuse'), findsNothing);
  });
}
