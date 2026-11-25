// On the breach screen, each watched address with an open breach can be
// marked dealt with, and that can be undone. The same state Home reads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/screens/darkweb/darkweb_screen.dart';

import '../support/real_fonts.dart';

MonitoredAsset _email(String id, String value, {int breachCount = 0}) =>
    MonitoredAsset(
      id: id,
      type: AssetType.email,
      value: value,
      addedAt: DateTime(2026),
      lastChecked: DateTime(2026, 11, 20),
      breachCount: breachCount,
    );

void main() {
  setUpAll(loadRealFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DarkWebProvider> pump(
      WidgetTester tester, List<MonitoredAsset> assets) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.reset);
    final p = DarkWebProvider(autoInit: false);
    await p.debugLoad(assets: assets);
    await tester.pumpWidget(ChangeNotifierProvider<DarkWebProvider>.value(
      value: p,
      child: MaterialApp(theme: AppTheme.dark, home: const DarkWebScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return p;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('an open address offers "I dealt with this", then "Undo"',
      (tester) async {
    final p = await pump(tester, [
      _email('a1', 'alex@example.com', breachCount: 2),
      _email('a2', 'sam@example.com'),
    ]);

    expect(find.text('I dealt with this'), findsOneWidget,
        reason: 'only the breached address offers it');
    expect(find.text('Dealt with'), findsNothing);

    await tap(tester, 'I dealt with this');
    expect(p.openBreachedAccounts, 0);
    expect(find.text('I dealt with this'), findsNothing);
    expect(find.text('Dealt with'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tap(tester, 'Undo');
    expect(p.openBreachedAccounts, 1);
    expect(find.text('I dealt with this'), findsOneWidget);
    expect(find.text('Dealt with'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a clean address offers neither', (tester) async {
    await pump(tester, [_email('a1', 'alex@example.com')]);
    expect(find.text('I dealt with this'), findsNothing);
    expect(find.text('Dealt with'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
