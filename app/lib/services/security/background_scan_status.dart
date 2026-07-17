// Background-scan status bridge (iOS BGTaskScheduler honesty surface).
//
// Reads the REAL state of native background scanning over the existing
// com.orb.guard/system channel: whether a BGAppRefreshTask request is
// actually pending with the OS scheduler, and when the last background run
// genuinely executed. iOS alone decides if and when a pending request runs —
// `scheduled: true` is never a promise of periodic execution.
//
// Honest degrade: on platforms with no native implementation (Android,
// desktop, tests) `fetch()` returns null instead of a fabricated status.

import 'package:flutter/services.dart';

/// Snapshot of the native background-scan state, as reported by the platform.
class BackgroundScanStatus {
  const BackgroundScanStatus({
    required this.scheduled,
    required this.lastFindings,
    required this.lastSuccess,
    this.lastRunAt,
  });

  /// True when a background-scan request is currently pending with the OS
  /// scheduler (iOS: BGTaskScheduler's real pending-request list). The OS
  /// decides if and when it actually runs.
  final bool scheduled;

  /// When the last background run actually executed, or null if a background
  /// scan has never run on this install.
  final DateTime? lastRunAt;

  /// Number of findings recorded by the last background run.
  final int lastFindings;

  /// Whether the last background run completed within its OS time budget
  /// (false also covers "never run").
  final bool lastSuccess;

  /// Parses the platform payload
  /// `{scheduled: bool, lastRunIso: String?, lastFindings: int,
  /// lastSuccess: bool}`. Missing or malformed values degrade to the
  /// "never ran" reading rather than inventing state.
  static BackgroundScanStatus fromMap(Map<Object?, Object?> map) {
    final iso = map['lastRunIso'];
    return BackgroundScanStatus(
      scheduled: map['scheduled'] == true,
      lastRunAt: iso is String ? DateTime.tryParse(iso) : null,
      lastFindings: (map['lastFindings'] as num?)?.toInt() ?? 0,
      lastSuccess: map['lastSuccess'] == true,
    );
  }
}

/// Fetches the background-scan status from the native layer.
class BackgroundScanStatusBridge {
  const BackgroundScanStatusBridge();

  /// The existing OrbGuard system channel that also serves the scan methods.
  static const MethodChannel channel = MethodChannel('com.orb.guard/system');

  /// Returns the real native status, or null when the platform provides no
  /// background-scan implementation (MissingPluginException) — the honest
  /// "unknown", never a fake "scheduled".
  Future<BackgroundScanStatus?> fetch() async {
    try {
      final raw =
          await channel.invokeMapMethod<Object?, Object?>('getBackgroundScanStatus');
      if (raw == null) return null;
      return BackgroundScanStatus.fromMap(raw);
    } on MissingPluginException {
      return null;
    }
  }
}
