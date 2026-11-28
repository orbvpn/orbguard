// Spyware & Pegasus on a computer. Seen on a real Mac: "Full Forensic Scan"
// sent nothing to examine and showed the server's raw answer,
// "ApiError(422): Nothing was examined...".
//
// The rules held here:
//  - on a computer, the analysis asks for the file first: an iPhone backup
//    or a sysdiagnose, which is what a computer has to examine
//  - a failed analysis is said in plain words, never as a raw error

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/providers/forensics_provider.dart';
import 'package:orbguard/screens/forensics/forensics_screen.dart';
import 'package:orbguard/services/api/api_interceptors.dart';

import '../support/real_fonts.dart';

void main() {
  setUpAll(loadRealFonts);

  Future<void> open(WidgetTester tester, TargetPlatform platform) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ForensicsProvider(),
        child: MaterialApp(home: ForensicsScreen(platform: platform)),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  for (final TargetPlatform computer in const [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('on ${computer.name}, it asks for a file to examine',
        (tester) async {
      await open(tester, computer);

      expect(find.text('Full Forensic Scan'), findsNothing,
          reason: 'it would send nothing to examine');
      expect(find.text('iPhone backup'), findsOneWidget);
      expect(find.text('iPhone sysdiagnose'), findsOneWidget);

      await close(tester);
    });
  }

  testWidgets('on a phone the full scan is still offered', (tester) async {
    await open(tester, TargetPlatform.android);
    expect(find.text('Full Forensic Scan'), findsOneWidget);
    await close(tester);
  });

  group('a failed analysis, in plain words', () {
    test('nothing to examine asks for a file', () {
      final String said = ForensicsProvider.plainError(ApiError(
          statusCode: 422,
          message: 'Nothing was examined. Provide a log or backup.'));
      expect(said, isNot(contains('ApiError')));
      expect(said, isNot(contains('422')));
      expect(said, contains('Choose'));
    });

    test('a file read only in part is not called clean', () {
      final String said = ForensicsProvider.plainError(ApiError(
          statusCode: 422,
          code: 'partly_examined',
          message: 'Part of this could not be read'));
      expect(said, contains('not an all-clear'));
      expect(said, isNot(contains('Choose')),
          reason: 'a file was chosen; part of it was read');
    });

    test('a busy server is not an all-clear', () {
      final String said = ForensicsProvider.plainError(ApiError(
          statusCode: 503, code: 'analysis_busy', message: 'busy'));
      expect(said, contains('busy'));
      expect(said, contains('not an all-clear'));
    });

    test('a file that did not arrive in full says so', () {
      final String said = ForensicsProvider.plainError(
          ApiError(statusCode: 413, message: 'failed to read multipart body'));
      expect(said, contains('did not reach OrbGuard in full'));
      expect(said, isNot(contains('multipart')));
    });

    test('no connection says so', () {
      final String said = ForensicsProvider.plainError(
          ApiError(message: 'Unable to connect', code: 'CONNECTION_ERROR'));
      expect(said, contains('internet'));
    });

    test('anything else is a plain try again', () {
      final String said =
          ForensicsProvider.plainError(StateError('Bad state: boom'));
      expect(said, isNot(contains('boom')));
      expect(said, isNot(contains('StateError')));
    });
  });
}
