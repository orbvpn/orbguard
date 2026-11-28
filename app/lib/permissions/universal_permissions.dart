// lib/permissions/universal_permissions.dart
//
// Notifications + Location permission checks/requests that work on EVERY
// supported platform — the two asks that exist everywhere the app ships.
//
// Why this exists: permission_handler has NO macOS implementation, so every
// `Permission.*.status/request()` call on the Mac build threw
// MissingPluginException. That left the App-Review-visible symptoms of the
// Aug 2026 macOS 2.1(a) rejection: the Permission Setup screen's spinner never
// resolved and "Grant Essential" did nothing. On macOS these helpers route
// through plugins that DO implement macOS:
//   • notifications — flutter_local_notifications (via NotificationService);
//   • location      — geolocator (geolocator_apple's darwin implementation).
// Everywhere else they keep the existing permission_handler paths, and every
// call is exception-safe: a missing platform implementation reads as "not
// granted", never a hang or an escaped MissingPluginException.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notifications/notification_service.dart';
import '../utils/platform_info.dart';

abstract final class UniversalPermissions {
  // ---- Notifications -------------------------------------------------------

  static Future<bool> notificationsGranted() async {
    try {
      if (PlatformInfo.isMacOS) {
        return await NotificationService.instance.hasPermissions();
      }
      return await Permission.notification.isGranted;
    } catch (e) {
      debugPrint('[OrbGuard] notificationsGranted failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Fires the OS notification prompt and reports the REAL post-request state.
  static Future<bool> requestNotifications() async {
    try {
      await NotificationService.instance.requestPermissions();
    } catch (e) {
      debugPrint('[OrbGuard] notification request failed: ${e.runtimeType}');
      // Fall back so first run still asks where the service is unavailable.
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    // Honesty: report the real post-request state, not the call result.
    return notificationsGranted();
  }

  // ---- Location ------------------------------------------------------------

  static Future<bool> locationGranted() async {
    try {
      if (PlatformInfo.isMacOS) {
        final p = await Geolocator.checkPermission();
        return p == LocationPermission.whileInUse ||
            p == LocationPermission.always;
      }
      return await Permission.location.isGranted;
    } catch (e) {
      debugPrint('[OrbGuard] locationGranted failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Fires the OS location prompt and reports the REAL post-request state.
  static Future<bool> requestLocation() async {
    try {
      if (PlatformInfo.isMacOS) {
        return requestMacLocation(
          servicesOn: Geolocator.isLocationServiceEnabled,
          request: Geolocator.requestPermission,
        );
      }
      return (await Permission.location.request()).isGranted;
    } catch (e) {
      debugPrint('[OrbGuard] location request failed: ${e.runtimeType}');
      return false;
    }
  }

  /// How long the Mac location question may stay open before the app stops
  /// waiting for it.
  static const Duration macLocationWait = Duration(seconds: 60);

  /// The Mac location request. macOS shows no question while Location
  /// Services is off for the whole Mac, and the plugin then waits for an
  /// answer that never comes: the button spun with no response (App Review,
  /// 2.1(a), September 2026). So it does not ask when Location Services is
  /// off, and it stops waiting after [wait]. Either way it reports "not
  /// granted", and the step the person pressed ends.
  static Future<bool> requestMacLocation({
    required Future<bool> Function() servicesOn,
    required Future<LocationPermission> Function() request,
    Duration wait = macLocationWait,
  }) async {
    if (!await servicesOn()) return false;
    final LocationPermission p =
        await request().timeout(wait, onTimeout: () => LocationPermission.denied);
    return p == LocationPermission.whileInUse ||
        p == LocationPermission.always;
  }
}
