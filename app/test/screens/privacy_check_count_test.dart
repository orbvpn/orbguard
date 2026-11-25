// The Pro privacy check hands back how many checks really ran: a stage that
// could not run, or broke, is never counted, and is named instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/scan/privacy_check_screen.dart';
import 'package:orbguard/screens/scanning_screen.dart' show ScanResult;
import 'package:orbguard/services/security/device_scan_service.dart';

DeviceScanProgress _p(int i, String name, bool done, {String? error}) =>
    DeviceScanProgress(
      stageIndex: i,
      totalStages: 4,
      stageName: name,
      stageCompleted: done,
      threatsFound: 0,
      stageError: error,
    );

void main() {
  testWidgets('counts only the stages that ran, and names the rest',
      (tester) async {
    ScanResult? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<ScanResult>(
              MaterialPageRoute(
                builder: (_) => PrivacyCheckScreen(
                  onScanWithProgress: (onProgress) async {
                    onProgress(_p(0, 'Network connections', false));
                    onProgress(_p(0, 'Network connections', true));
                    onProgress(_p(1, 'App databases', false));
                    onProgress(_p(1, 'App databases', true,
                        error: DeviceScanService.notSupported));
                    onProgress(_p(2, 'Memory', false));
                    onProgress(_p(2, 'Memory', true));
                    onProgress(_p(3, 'Certificate analysis', false));
                    onProgress(_p(3, 'Certificate analysis', true,
                        error: 'channel broke'));
                    return const [];
                  },
                ),
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1)); // the completion beat
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isNotNull);
    // The last stage to finish was the fourth, but only two ran.
    expect(result!.itemsScanned, 2);
    expect(result!.stagesRan, ['Network connections', 'Memory']);
    expect(result!.stagesNotPossible, ['App databases']);
    expect(result!.stagesFailed, ['Certificate analysis']);
    expect(result!.checksUnavailable, 2);
  });
}
