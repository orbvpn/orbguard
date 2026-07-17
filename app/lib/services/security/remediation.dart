// Turns a scan finding into a real, device-native fix action.
//
// HONESTY: OrbGuard cannot silently uninstall an app or kill another app's
// VPN without elevated/root access it doesn't have. What it CAN do on any
// device is take the user straight to the exact system screen where they
// finish the fix in one tap — the app's App Info (uninstall/disable) or the
// VPN settings (disconnect). That's what "Fix" does.
library;

import 'package:flutter/services.dart';

enum RemediationKind {
  /// Open the app's App Info screen to uninstall/disable it.
  appInfo,

  /// Open system VPN settings to disconnect a VPN.
  vpnSettings,

  /// No device-native one-tap fix — the caller should show guidance instead.
  guidanceOnly,
}

class Remediation {
  Remediation({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.orb.guard/system');

  final MethodChannel _channel;

  /// Decides how a given threat map is best remediated.
  static RemediationKind kindFor(Map<String, dynamic> threat) {
    final type = '${threat['type'] ?? ''}'.toLowerCase();
    final path = '${threat['path'] ?? ''}'.toLowerCase();
    final name = '${threat['name'] ?? ''}'.toLowerCase();
    final pkg = _packageOf(threat);

    if ((type == 'malware' || type == 'app_risk') && pkg != null) {
      return RemediationKind.appInfo;
    }
    if (type == 'network' || path == 'vpn' || name.contains('vpn')) {
      return RemediationKind.vpnSettings;
    }
    return RemediationKind.guidanceOnly;
  }

  /// The package a threat refers to, if any (malware/high-risk app findings
  /// carry it in metadata or the path).
  static String? _packageOf(Map<String, dynamic> threat) {
    final meta = threat['metadata'];
    if (meta is Map && meta['package'] is String) {
      final p = meta['package'] as String;
      if (p.isNotEmpty) return p;
    }
    final path = threat['path'];
    if (path is String && path.contains('.') && !path.contains('/')) return path;
    return null;
  }

  /// Runs the native fix for [threat]. Returns true when a system screen was
  /// opened; false when there's no one-tap fix (caller shows guidance) or the
  /// platform channel is unavailable.
  Future<bool> fix(Map<String, dynamic> threat) async {
    switch (kindFor(threat)) {
      case RemediationKind.appInfo:
        return _invoke('openAppDetails', {'package': _packageOf(threat)});
      case RemediationKind.vpnSettings:
        return _invoke('openVpnSettings');
      case RemediationKind.guidanceOnly:
        return false;
    }
  }

  Future<bool> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      final ok = await _channel.invokeMethod<bool>(method, args);
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
