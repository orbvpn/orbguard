// What a sandboxed Mac can still read of itself. Seen on a real Mac in the
// App Sandbox: `lsof` could name no process ("can't get PID byte count:
// Operation not permitted") and `socketfilterfw` would not start.
//
// The rule held here: what macOS keeps out of reach is said in plain words,
// and a firewall setting out of reach is never read as on or off.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/providers/desktop_security_provider.dart';
import 'package:orbguard/services/security/desktop_host_collector.dart';

void main() {
  group('the connections on a Mac', () {
    test('kept out of reach by macOS, said plainly', () {
      final String said = macLsofFailure(
          1, "lsof: can't get PID byte count: Operation not permitted\n");
      expect(said, isNot(contains('lsof')));
      expect(said, contains('macOS'));
    });

    test('any other failure keeps what lsof said', () {
      expect(macLsofFailure(1, 'lsof: boom'), contains('boom'));
    });
  });

  group('the firewall on a Mac', () {
    test('a tool macOS will not start is out of reach, said plainly', () {
      final HostFirewallStatus s =
          DesktopSecurityProvider.macFirewallOutOfReach(const ProcessException(
              '/usr/libexec/ApplicationFirewall/socketfilterfw',
              ['--getglobalstate'],
              'Operation not permitted',
              1));
      expect(s.state, HostFirewallState.unavailable);
      expect(s.detail, isNot(contains('socketfilterfw')));
      expect(s.detail, isNot(contains('Operation not permitted')));
      expect(s.detail, contains('System Settings'));
    });
  });
}
