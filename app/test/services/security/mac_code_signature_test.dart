// A Mac's code signatures are read natively, so they can be read inside the
// App Sandbox. Seen on a real sandboxed Mac: `codesign` could not run, and
// every app it could not read was listed as unsigned, and two of Apple's own
// launch daemons (shell scripts in /System and /usr/sbin) were rated high.
//
// The rules held here:
//  - a signature that could not be read says nothing: never "unsigned"
//  - what sits in a folder System Integrity Protection guards is Apple's
//  - a signature that no longer checks out is told apart from none at all

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/mac_code_signature.dart';
import 'package:orbguard/services/security/macos_persistence_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.orb.guard/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('reading', () {
    test('asks the native side once for every path', () async {
      final List<MethodCall> calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          '/Applications/Safari.app': {'status': 'apple'},
          '/Applications/Slack.app': {
            'status': 'valid',
            'authority': 'Developer ID Application: Slack Technologies',
            'teamId': 'BQR82RBBHL',
            'identifier': 'com.tinyspeck.slackmacgap',
          },
          '/Users/a/tool': {'status': 'unsigned'},
          '/Applications/Changed.app': {'status': 'broken'},
          '/Applications/Locked.app': {'status': 'unknown', 'error': -67060},
        };
      });

      final read = await MacCodeSignature.read(const [
        '/Applications/Safari.app',
        '/Applications/Slack.app',
        '/Users/a/tool',
        '/Applications/Changed.app',
        '/Applications/Locked.app',
        '/Applications/Unanswered.app',
      ]);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'codeSignatures');
      expect((calls.single.arguments as Map)['paths'], hasLength(6));
      expect(read['/Applications/Safari.app']!.state, MacSignature.apple);
      expect(read['/Applications/Slack.app']!.teamId, 'BQR82RBBHL');
      expect(read['/Users/a/tool']!.state, MacSignature.unsigned);
      expect(read['/Applications/Changed.app']!.state, MacSignature.broken);
      expect(read['/Applications/Locked.app']!.state, MacSignature.unknown);
      expect(read['/Applications/Unanswered.app']!.state, MacSignature.unknown);
    });

    test('with no native side, every signature is unknown, not unsigned',
        () async {
      final read = await MacCodeSignature.read(const ['/Applications/X.app']);
      expect(read['/Applications/X.app']!.state, MacSignature.unknown);
      expect(read['/Applications/X.app']!.signed, isFalse);
      expect(read['/Applications/X.app']!.appRow, isNull);
    });
  });

  group('the Code signing tab', () {
    MacCodeSignature sig(String path, MacSignature state) =>
        MacCodeSignature(path: path, state: state);

    test('lists what could be read, and leaves out what could not', () {
      final rows = MacCodeSignature.appRows([
        sig('/Applications/Safari.app', MacSignature.apple),
        sig('/Applications/Locked.app', MacSignature.unknown),
        sig('/Users/a/tool', MacSignature.unsigned),
        sig('/Applications/Changed.app', MacSignature.broken),
      ]);

      expect([for (final r in rows) r['name']], ['Safari', 'tool', 'Changed']);
      expect(rows[0]['is_signed'], isTrue);
      expect(rows[0]['is_valid'], isTrue);
      expect(rows[0]['developer'], 'Apple');
      expect(rows[1]['is_signed'], isFalse);
      expect(rows[2]['is_signed'], isTrue);
      expect(rows[2]['is_valid'], isFalse);
    });

    test('when nothing could be read, it says so instead of a list', () {
      expect(
          MacCodeSignature.unreadable([
            sig('/Applications/A.app', MacSignature.unknown),
            sig('/Applications/B.app', MacSignature.unknown),
          ]),
          isNotNull);
      expect(
          MacCodeSignature.unreadable([
            sig('/Applications/A.app', MacSignature.unknown),
            sig('/Applications/B.app', MacSignature.valid),
          ]),
          isNull);
      expect(MacCodeSignature.unreadable(const []), isNull);
    });
  });

  group('System Integrity Protection', () {
    test('guards the system folders, not the ones people install into', () {
      for (final String p in const [
        '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        '/usr/sbin/snmpd',
        '/usr/libexec/rapportd',
        '/bin/sh',
        '/sbin/launchd',
        '/Library/Apple/System/Library/LaunchDaemons/x.plist',
      ]) {
        expect(MacCodeSignature.isProtectedBySip(p), isTrue, reason: p);
      }
      for (final String p in const [
        '/usr/local/bin/tool',
        '/Library/LaunchDaemons/com.vendor.helper.plist',
        '/Applications/Slack.app',
        '/Users/a/Library/LaunchAgents/x.plist',
      ]) {
        expect(MacCodeSignature.isProtectedBySip(p), isFalse, reason: p);
      }
    });
  });

  group('a startup item', () {
    Map<String, dynamic> result(String path, MacSignature state) =>
        MacOSPersistenceScannerService.signingResult(
            MacCodeSignature(path: path, state: state, authority: 'Dev'));

    test('a program macOS would not let it read is unknown, not unsigned', () {
      expect(result('/Library/Helper/tool', MacSignature.unknown)['status'],
          SigningStatus.unknown);
    });

    test("Apple's own unsigned script in a protected folder is not unsigned",
        () {
      expect(result('/usr/sbin/snmpd', MacSignature.unsigned)['status'],
          SigningStatus.unknown);
    });

    test('an unsigned program elsewhere is unsigned', () {
      expect(result('/Library/Helper/tool', MacSignature.unsigned)['status'],
          SigningStatus.unsigned);
    });

    test('a broken signature is invalid; a good one keeps its signer', () {
      expect(result('/Library/Helper/tool', MacSignature.broken)['status'],
          SigningStatus.invalid);
      final Map<String, dynamic> good =
          result('/Library/Helper/tool', MacSignature.valid);
      expect(good['status'], SigningStatus.thirdPartySigned);
      expect(good['authority'], 'Dev');
      expect(result('/Library/Helper/tool', MacSignature.apple)['status'],
          SigningStatus.appleSigned);
    });
  });
}
