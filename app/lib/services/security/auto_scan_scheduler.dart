// Auto-Scan Scheduler
//
// Makes the "Auto Scan" settings real. A periodic on-device security scan runs
// when it is due (per `scan_freq`), honoring the `scan_wifi` (Wi-Fi-only)
// constraint. It self-throttles via a persisted timestamp, so the same entry
// point is safe to call from anywhere:
//   - Foreground catch-up on app launch/resume (all platforms).
//   - The device agent's existing Android WorkManager cycle (runHeadlessCycle)
//     calls runIfDue(), giving true background scans on Android without a
//     second background task.
//
// iOS/desktop have no guaranteed OS background window, so there the scan runs
// on the next launch/resume when it is due — the honest limit of app-side
// scheduling.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_service.dart';
import 'device_scan_service.dart';

class AutoScanScheduler {
  AutoScanScheduler._();

  static final AutoScanScheduler instance = AutoScanScheduler._();

  /// Timestamp (ms since epoch) of the last automatic scan attempt.
  static const _kLastAutoScanKey = 'auto_scan_last_at';

  /// Guards against overlapping runs within a single isolate. Cross-isolate
  /// throttling is handled by the persisted timestamp.
  bool _running = false;

  /// Run an automatic scan if auto-scan is enabled and enough time has elapsed
  /// since the last one (per `scan_freq`), honoring the Wi-Fi-only setting.
  /// Safe to call on every launch/resume and from the background isolate.
  Future<void> runIfDue() async {
    if (_running) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('scan_auto') ?? true)) return;

    final freqHours = (prefs.getInt('scan_freq') ?? 24).clamp(1, 24 * 7);
    final last = prefs.getInt(_kLastAutoScanKey) ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - last;
    if (elapsedMs < Duration(hours: freqHours).inMilliseconds) return;

    // Wi-Fi-only constraint (best effort; the Android WorkManager task also
    // enforces an unmetered-network constraint at the OS level).
    if (prefs.getBool('scan_wifi') ?? true) {
      try {
        final conn = await Connectivity().checkConnectivity();
        final onWifi = conn.contains(ConnectivityResult.wifi) ||
            conn.contains(ConnectivityResult.ethernet);
        if (!onWifi) return;
      } catch (_) {
        // Connectivity unknown — skip this cycle rather than scan on cellular.
        return;
      }
    }

    await _runOnce(prefs);
  }

  Future<void> _runOnce(SharedPreferences prefs) async {
    _running = true;
    final startedAt = DateTime.now();
    try {
      final threats = await DeviceScanService.instance.performScan();
      await _stamp(prefs);
      // Respects the "Scan Completed" notification toggle inside the service.
      await NotificationService.instance.showScanCompleteNotification(
        scanType: 'Automatic',
        threatsFound: threats.length,
        duration: DateTime.now().difference(startedAt).inSeconds,
      );
    } on DeviceScanUnavailableException catch (e) {
      // Scan engine not available on this build/platform. Record the attempt
      // so we don't retry every cycle.
      await _stamp(prefs);
      debugPrint('AutoScanScheduler: scan unavailable: $e');
    } catch (e) {
      debugPrint('AutoScanScheduler: scan failed: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _stamp(SharedPreferences prefs) =>
      prefs.setInt(_kLastAutoScanKey, DateTime.now().millisecondsSinceEpoch);
}
