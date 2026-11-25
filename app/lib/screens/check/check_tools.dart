/// The on-demand tools on the Check tab, each a doorway into a screen that
/// already exists, and the platforms where that screen can really work.
library;

import 'package:flutter/widgets.dart';

import '../../presentation/widgets/duotone_icon.dart';
import '../../services/home/home_brief.dart';
import '../network/network_security_screen.dart';
import '../qr_scanner/qr_scanner_screen.dart';
import '../scan/apk_scan_screen.dart';
import '../shields/shields_screen.dart';

enum CheckTool {
  qr(
      title: 'Scan a QR code',
      line: 'Before you open it',
      icon: AppIcons.qrCode),
  email(
      title: 'Check an email',
      line: 'Known data breaches',
      icon: AppIcons.letter),
  wifi(title: 'Check this Wi-Fi', line: 'Fake hotspots', icon: AppIcons.wifi),
  // The secure call check runs a different number of its checks on each
  // phone, so the line names none.
  call(
      title: 'Before a call',
      line: 'Checks this phone first',
      icon: AppIcons.phoneCalling),
  vpn(title: 'Hidden VPN', line: 'Rerouted traffic', icon: AppIcons.eyeClosed),
  apk(
      title: 'Check an app file',
      line: 'Before you install',
      icon: AppIcons.fileCheck);

  const CheckTool(
      {required this.title, required this.line, required this.icon});

  final String title;
  final String line;
  final String icon;

  /// Whether this tool's screen can do its job on [platform]. A tool that
  /// cannot is left off the tab, never shown dead. Null is a browser.
  bool runsOn(TargetPlatform? platform) => switch (this) {
        // mobile_scanner has no Windows or Linux camera.
        qr => platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS,
        // The breach lookup is a request to OrbGuard; it runs anywhere.
        email => true,
        // Only these three answer the com.orb.guard/wifi channel.
        wifi => platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS,
        // The secure call check only has checks on a phone.
        call =>
          platform == TargetPlatform.android || platform == TargetPlatform.iOS,
        // The detector reads the native network state; a browser has none.
        vpn => platform != null,
        // Only Android installs app files.
        apk => platform == TargetPlatform.android,
      };

  /// The tools for [platform], in the order the tab shows them.
  static List<CheckTool> availableOn(TargetPlatform? platform) => [
        for (final CheckTool t in values)
          if (t.runsOn(platform)) t
      ];

  /// The screen this tool opens. The breach check, the call check and the
  /// hidden VPN check are shields, so they open exactly where their shield
  /// does.
  Widget screen() => switch (this) {
        qr => const QrScannerScreen(),
        email => shieldScreen(Shield.identity),
        wifi => const NetworkSecurityScreen(),
        call => shieldScreen(Shield.secureCall),
        vpn => shieldScreen(Shield.hiddenVpn),
        apk => const ApkScanScreen(),
      };
}
