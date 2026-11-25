// One vocabulary, to the last screen: the sheet a shield opens is headed by
// the same name the shield carries on Home's orbit and on its Protect card.
// Seen on a Pixel 6, where "Spyware & Pegasus" opened a sheet called
// "Forensic Analysis".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/providers/forensics_provider.dart';
import 'package:orbguard/providers/privacy_provider.dart';
import 'package:orbguard/providers/scam_detection_provider.dart';
import 'package:orbguard/screens/shields/shields_screen.dart';
import 'package:orbguard/services/home/home_brief.dart';

import '../support/real_fonts.dart';

void main() {
  // These are full screens: with the test font's square glyphs their headers
  // overflow in ways no phone shows.
  setUpAll(loadRealFonts);

  for (final Shield shield in Shield.values) {
    testWidgets('${shield.name} opens under its own name', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ForensicsProvider()),
            ChangeNotifierProvider(create: (_) => PrivacyProvider()),
            ChangeNotifierProvider(create: (_) => ScamDetectionProvider()),
            ChangeNotifierProvider(create: (_) => DarkWebProvider()),
          ],
          child: MaterialApp(home: shieldScreen(shield)),
        ),
      );
      await tester.pump();

      expect(find.text(shield.name), findsWidgets);

      // Let whatever the screen started on its first frame run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
