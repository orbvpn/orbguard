// The Full Forensic Scan on a phone. It used to send the server nothing but
// the device's name, and the server answered that nothing was examined. No
// app can read its phone's system logs, so the scan now reads the file the
// phone's own system makes: a sheet gives the steps, then the person chooses
// the file, the scan-credit gate is asked, and the file is sent.
//
// The rules held here:
//  - the button opens the steps; it checks and spends nothing by itself
//  - choosing the file opens the picker; picking nothing costs nothing
//  - a chosen file the server does not read is neither paid for nor sent
//  - Android sends a bug report; an iPhone sends a sysdiagnose
//  - every pop-up in the flow is a sheet

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/providers/forensics_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/forensics/forensic_guide_sheet.dart';
import 'package:orbguard/screens/forensics/forensics_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

/// Records what was sent instead of sending it.
class _Uploads extends ForensicsProvider {
  final List<String> bugreports = [];
  final List<String> sysdiagnoses = [];

  @override
  Future<void> init() async {}

  @override
  Future<ForensicAnalysisResult?> uploadAndroidBugreport(
      String filePath) async {
    bugreports.add(filePath);
    return null;
  }

  @override
  Future<ForensicAnalysisResult?> uploadSysdiagnose(String filePath) async {
    sysdiagnoses.add(filePath);
    return null;
  }

  @override
  Future<ForensicAnalysisResult?> runFullAnalysis({
    String? shutdownLog,
    String? logcatData,
  }) {
    fail('the phone scan no longer posts an empty full analysis');
  }
}

/// The file picker, standing in: what it was offered, and what it gives back.
class _Picker {
  _Picker(this.choice);

  final String? choice;
  final List<List<String>> offered = [];

  Future<String?> pick(List<String> extensions) async {
    offered.add(extensions);
    return choice;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, Finder what) async {
  await tester.ensureVisible(what);
  await tester.pump();
  await tester.tap(what);
  await _settle(tester);
}

Future<void> _open(
  WidgetTester tester, {
  required GateUser user,
  required _Uploads uploads,
  required _Picker picker,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ...user.providers,
      ChangeNotifierProvider<ForensicsProvider>.value(value: uploads),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: ForensicsScreen(platform: platform, pickFile: picker.pick),
    ),
  ));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRealFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IapService.instance.debugSeed(available: false, products: []);
  });

  group('on Android', () {
    testWidgets('the card says what the scan reads', (tester) async {
      await _open(tester,
          user: GateUser(signedIn: true, credits: 1),
          uploads: _Uploads(),
          picker: _Picker(null));

      expect(
          find.text('Make a bug report, and OrbGuard looks through this '
              'phone\'s logs for known spyware.'),
          findsOneWidget);
    });

    testWidgets('the button opens the steps, as a sheet, and checks nothing',
        (tester) async {
      final GateUser user = GateUser(signedIn: true, credits: 1);
      final _Uploads uploads = _Uploads();
      final _Picker picker = _Picker('/downloads/bugreport.zip');
      await _open(tester, user: user, uploads: uploads, picker: picker);

      await _tap(tester, find.text('Full Forensic Scan'));

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ForensicGuideSheet), findsOneWidget);
      for (final ForensicGuideStep step in ForensicGuide.android.steps) {
        expect(find.text(step.title), findsOneWidget);
        expect(find.text(step.detail), findsOneWidget);
      }
      expect(find.text('Choose the bug report'), findsOneWidget);
      expect(picker.offered, isEmpty, reason: 'nothing is picked yet');
      expect(user.spent, 0, reason: 'reading the steps costs nothing');
      expect(uploads.bugreports, isEmpty);
    });

    testWidgets('choosing the bug report picks it, pays once, and sends it',
        (tester) async {
      const String path = '/downloads/bugreport-pixel-2026-11-28.zip';
      final GateUser user = GateUser(signedIn: true, credits: 1);
      final _Uploads uploads = _Uploads();
      final _Picker picker = _Picker(path);
      await _open(tester, user: user, uploads: uploads, picker: picker);

      await _tap(tester, find.text('Full Forensic Scan'));
      await _tap(tester, find.text('Choose the bug report'));

      expect(find.byType(ForensicGuideSheet), findsNothing);
      // Every file is offered; the name is checked after.
      expect(picker.offered, [<String>[]]);
      expect(user.spent, 1);
      expect(uploads.bugreports, [path]);
      expect(uploads.sysdiagnoses, isEmpty);
    });

    testWidgets('signed out, sign-in is asked for once a file is chosen',
        (tester) async {
      final GateUser user = GateUser();
      final _Uploads uploads = _Uploads();
      await _open(tester,
          user: user,
          uploads: uploads,
          picker: _Picker('/downloads/bugreport.zip'));

      await _tap(tester, find.text('Full Forensic Scan'));
      expect(find.byType(LoginScreen), findsNothing);
      await _tap(tester, find.text('Choose the bug report'));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(uploads.bugreports, isEmpty);
    });

    testWidgets('picking nothing costs nothing', (tester) async {
      final GateUser user = GateUser(signedIn: true, credits: 1);
      final _Uploads uploads = _Uploads();
      final _Picker picker = _Picker(null);
      await _open(tester, user: user, uploads: uploads, picker: picker);

      await _tap(tester, find.text('Full Forensic Scan'));
      await _tap(tester, find.text('Choose the bug report'));

      expect(picker.offered, hasLength(1));
      expect(user.spent, 0);
      expect(uploads.bugreports, isEmpty);
    });

    testWidgets('Not now closes the steps and nothing happens', (tester) async {
      final GateUser user = GateUser(signedIn: true, credits: 1);
      final _Uploads uploads = _Uploads();
      final _Picker picker = _Picker('/downloads/bugreport.zip');
      await _open(tester, user: user, uploads: uploads, picker: picker);

      await _tap(tester, find.text('Full Forensic Scan'));
      await _tap(tester, find.text('Not now'));

      expect(find.byType(ForensicGuideSheet), findsNothing);
      expect(picker.offered, isEmpty);
      expect(user.spent, 0);
      expect(uploads.bugreports, isEmpty);
    });

    testWidgets('a file that is not a bug report is not paid for or sent',
        (tester) async {
      final GateUser user = GateUser(signedIn: true, credits: 1);
      final _Uploads uploads = _Uploads();
      await _open(tester,
          user: user,
          uploads: uploads,
          picker: _Picker('/downloads/screenshot.png'));

      await _tap(tester, find.text('Full Forensic Scan'));
      await _tap(tester, find.text('Choose the bug report'));

      expect(find.text(ForensicGuide.android.wrongFile), findsOneWidget);
      expect(user.spent, 0);
      expect(uploads.bugreports, isEmpty);
    });
  });

  group('on an iPhone', () {
    testWidgets('the card says what the scan reads', (tester) async {
      await _open(tester,
          user: GateUser(
              signedIn: true, credits: 1, platform: TargetPlatform.iOS),
          uploads: _Uploads(),
          picker: _Picker(null),
          platform: TargetPlatform.iOS);

      expect(
          find.text('Make a sysdiagnose, and OrbGuard looks through this '
              'iPhone\'s logs for known spyware.'),
          findsOneWidget);
    });

    testWidgets('the steps are for a sysdiagnose, and it is sent as one',
        (tester) async {
      const String path = '/files/sysdiagnose_2026.11.28_07-40-56-0800_'
          'iPhone-OS_iPhone_23A341.tar.gz';
      final GateUser user =
          GateUser(signedIn: true, credits: 1, platform: TargetPlatform.iOS);
      final _Uploads uploads = _Uploads();
      final _Picker picker = _Picker(path);
      await _open(tester,
          user: user,
          uploads: uploads,
          picker: picker,
          platform: TargetPlatform.iOS);

      await _tap(tester, find.text('Full Forensic Scan'));

      expect(find.byType(BottomSheet), findsOneWidget);
      for (final ForensicGuideStep step in ForensicGuide.iphone.steps) {
        expect(find.text(step.title), findsOneWidget);
        expect(find.text(step.detail), findsOneWidget);
      }
      expect(find.text('Take a bug report'), findsNothing);
      expect(user.spent, 0);

      await _tap(tester, find.text('Choose the sysdiagnose'));

      expect(picker.offered, [<String>[]]);
      expect(user.spent, 1);
      expect(uploads.sysdiagnoses, [path]);
      expect(uploads.bugreports, isEmpty);
    });
  });

  group('the guides', () {
    test('a phone has one, a computer and the web do not', () {
      expect(ForensicGuide.of(TargetPlatform.android), ForensicGuide.android);
      expect(ForensicGuide.of(TargetPlatform.iOS), ForensicGuide.iphone);
      for (final TargetPlatform other in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(ForensicGuide.of(other), isNull);
      }
      expect(ForensicGuide.of(null), isNull);
    });

    test('each accepts only what the server reads', () {
      expect(ForensicGuide.android.acceptedSuffixes, ['.zip', '.txt']);
      expect(
          ForensicGuide.iphone.acceptedSuffixes, ['.tar.gz', '.tgz', '.zip']);
    });

    test('the words have no dashes and say the file is deleted', () {
      for (final ForensicGuide guide in const [
        ForensicGuide.android,
        ForensicGuide.iphone,
      ]) {
        final List<String> words = [
          guide.lead,
          guide.choose,
          guide.wrongFile,
          for (final ForensicGuideStep step in guide.steps) ...[
            step.title,
            step.detail,
          ],
        ];
        for (final String said in words) {
          expect(said, isNot(matches(RegExp('[—–]'))));
        }
        expect(guide.steps.last.detail, contains('then deletes it'));
      }
    });
  });
}
