// Visual QA sweep: boots the real app, opens every drawer screen and captures
// a screenshot of each into build/screen_sweep/ (via the test_driver).
//
// Run on a booted simulator:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screen_sweep_test.dart -d <udid>
//
// The app has continuous glass/pulse animations, so pumpAndSettle would hang —
// fixed-duration pumps are used instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orbguard/main.dart' as app;

/// Drawer items to visit, in drawer order (titles as rendered).
const drawerScreens = <String>[
  'Dashboard',
  'SMS Protection',
  'URL Protection',
  'QR Scanner',
  'Scam Detection',
  'App Security',
  'Network Security',
  'Dark Web Monitor',
  'Rogue AP Detection',
  'Network Firewall',
  'Device Security',
  'Forensics',
  'Intelligence Core',
  'MITRE ATT&CK',
  'Threat Hunting',
  'Supply Chain',
  'Threat Graph',
  'Correlation',
  'ML Analysis',
  'Campaigns',
  'Threat Actors',
  'Identity Protection',
  'Social Media',
  'Privacy Protection',
  'Executive Protection',
  'Enterprise Policy',
  'Enterprise Overview',
  'SIEM Integration',
  'Compliance Reports',
  'STIX/TAXII',
];

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sweep every drawer screen and screenshot it', (tester) async {
    app.main();
    await pumpFor(tester, const Duration(seconds: 6)); // init + first data

    await binding.takeScreenshot('00-home');

    var index = 0;
    for (final title in drawerScreens) {
      index++;
      final shotName =
          '${index.toString().padLeft(2, '0')}-${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
      try {
        // Open the drawer on the root scaffold.
        final scaffold = find.byType(Scaffold).first;
        tester.firstState<ScaffoldState>(scaffold).openDrawer();
        await pumpFor(tester, const Duration(milliseconds: 700));

        // Find the item; scroll the drawer list if it's off-screen.
        var item = find.text(title);
        if (item.evaluate().isEmpty) {
          final scrollable = find
              .descendant(
                  of: find.byType(Drawer), matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(item, 300, scrollable: scrollable);
          await tester.pump(const Duration(milliseconds: 300));
          item = find.text(title);
        }
        expect(item, findsWidgets, reason: 'drawer item "$title" not found');
        await tester.tap(item.first, warnIfMissed: false);
        await pumpFor(tester, const Duration(seconds: 4)); // screen load

        await binding.takeScreenshot(shotName);
      } catch (e) {
        debugPrint('SWEEP-ERROR on "$title": $e');
        try {
          await binding.takeScreenshot('$shotName-ERROR');
        } catch (_) {}
      } finally {
        // Return to the root screen for the next iteration.
        final nav = tester.firstState<NavigatorState>(find.byType(Navigator).first);
        nav.popUntil((r) => r.isFirst);
        await pumpFor(tester, const Duration(milliseconds: 800));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
