// PlatformInfo abstraction — native-side contract.
//
// The app was made web-compatible by replacing every dart:io `Platform.*`
// use with `PlatformInfo.*` (lib/utils/platform_info.dart), which resolves
// via conditional export to a dart:io-backed implementation on the VM and a
// web stub in the browser. These tests run on the VM, so they pin two
// things:
//   1. The io implementation is selected and delegates EXACTLY to
//      dart:io Platform — i.e. behavior on Android/iOS/macOS/Windows/Linux
//      is unchanged by the migration.
//   2. Importing main.dart (and with it every screen/provider/service that
//      was touched) still compiles for native targets.

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Compiles the full app for the VM: main.dart transitively imports all the
// files migrated off dart:io Platform, including the conditional export.
import 'package:orbguard/main.dart' show AntiSpywareApp;
import 'package:orbguard/utils/platform_info.dart';

void main() {
  test('PlatformInfo delegates exactly to dart:io Platform on the VM', () {
    expect(PlatformInfo.isWeb, isFalse);
    expect(PlatformInfo.isAndroid, Platform.isAndroid);
    expect(PlatformInfo.isIOS, Platform.isIOS);
    expect(PlatformInfo.isMacOS, Platform.isMacOS);
    expect(PlatformInfo.isWindows, Platform.isWindows);
    expect(PlatformInfo.isLinux, Platform.isLinux);
    expect(PlatformInfo.isFuchsia, Platform.isFuchsia);
    expect(PlatformInfo.isDesktop,
        Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    expect(PlatformInfo.isMobile, Platform.isAndroid || Platform.isIOS);
    expect(PlatformInfo.operatingSystem, Platform.operatingSystem);
    expect(
        PlatformInfo.operatingSystemVersion, Platform.operatingSystemVersion);
    expect(PlatformInfo.localHostname, Platform.localHostname);
    expect(PlatformInfo.pathSeparator, Platform.pathSeparator);
    expect(PlatformInfo.environment, Platform.environment);
  });

  test('app root widget is constructible (native compile smoke)', () {
    expect(const AntiSpywareApp(), isA<Widget>());
  });
}
