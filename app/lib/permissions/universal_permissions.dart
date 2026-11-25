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
        final p = await Geolocator.requestPermission();
        return p == LocationPermission.whileInUse ||
            p == LocationPermission.always;
      }
      return (await Permission.location.request()).isGranted;
    } catch (e) {
      debugPrint('[OrbGuard] location request failed: ${e.runtimeType}');
      return false;
    }
  }
}
