// Firewall Realtime Bridge
//
// Thin read-only wrapper over the native firewall channel
// (com.orbvpn.orbguard/firewall) for the real-time layer:
//   - blockedToday():   DNS queries the on-device firewall blocked so far
//                       today (local date), for the home proof-of-work feed.
//   - survivesReboot(): whether the firewall will restore itself after a
//                       reboot (persisted enabled flag AND VPN consent still
//                       valid), so the UI can be honest about persistence.
//
// Honest degrade: every call returns its zero value (0 / false) when the
// native engine is missing (iOS/desktop/web, or an old Android build) or
// errors — it never throws to the UI. A zero is never a fabricated "safe";
// it simply means "nothing counted / no auto-restore", which is the truth
// whenever the native side cannot answer.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only bridge to the native firewall's real-time state.
class FirewallRealtime {
  FirewallRealtime({MethodChannel? channel}) : _channel = channel ?? _default;

  /// Same channel the firewall engine registers natively
  /// (FirewallChannelHandler.kt).
  static const MethodChannel _default =
      MethodChannel('com.orbvpn.orbguard/firewall');

  final MethodChannel _channel;

  /// DNS queries blocked by the firewall so far today (local date).
  ///
  /// Returns 0 when nothing was blocked, when the firewall never ran today,
  /// or when the native engine is absent/errors (honest degrade — never
  /// throws).
  Future<int> blockedToday() async {
    try {
      return await _channel.invokeMethod<int>('getBlockedToday') ?? 0;
    } on MissingPluginException {
      return 0; // No native engine on this platform/build.
    } on PlatformException catch (e) {
      debugPrint('FirewallRealtime: getBlockedToday failed: ${e.message}');
      return 0;
    } catch (e) {
      debugPrint('FirewallRealtime: getBlockedToday failed: $e');
      return 0;
    }
  }

  /// Whether the firewall will come back by itself after a reboot: the user
  /// left it enabled AND the system still honours the VPN consent.
  ///
  /// Returns false when either condition fails or the native engine is
  /// absent/errors (honest degrade — never throws).
  Future<bool> survivesReboot() async {
    try {
      return await _channel.invokeMethod<bool>('survivesReboot') ?? false;
    } on MissingPluginException {
      return false; // No native engine on this platform/build.
    } on PlatformException catch (e) {
      debugPrint('FirewallRealtime: survivesReboot failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('FirewallRealtime: survivesReboot failed: $e');
      return false;
    }
  }
}
