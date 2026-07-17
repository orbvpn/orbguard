// The last LOCAL scan's verdict — the honest source for the home status.
//
// P4.1, and the fix for the "always says needs attention" defect: the old
// home read a backend features-configured score that the on-device scan
// never touched, so no amount of scanning could improve it. This controller
// persists the verdict of the user's latest real checkup — score derived
// from what the scan actually found AND how much it could actually check —
// and the home reads THIS.
//
// Honesty rubric (never fake a good score):
//  - No scan yet → score -1 (ProtectionVerdict.notAssessed, "Let's check").
//  - A clean scan is capped by its real coverage: if permissions blocked
//    most checks, "clean" can only reach the attention band — the honest
//    message is "we couldn't see much; grant access to be sure".
//  - Any found threat drags the score down by its real severity; a critical
//    or high finding always lands in the at-risk band.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted verdict of the most recent on-device checkup.
class LastScanVerdictController extends ChangeNotifier {
  LastScanVerdictController({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static const String _kScore = 'verdict_score';
  static const String _kAt = 'verdict_at_iso';
  static const String _kThreats = 'verdict_threat_count';
  static const String _kCoverage = 'verdict_coverage_pct';

  int _score = -1;
  DateTime? _lastScanAt;
  int _threatCount = 0;
  int _coveragePercent = 0;

  /// 0–100 verdict score, or -1 when no scan has ever run
  /// (feed straight into `ProtectionVerdict.fromScore`).
  int get score => _score;
  DateTime? get lastScanAt => _lastScanAt;
  int get threatCount => _threatCount;

  /// How much of the device the scan could genuinely check (0–100), from
  /// granted permissions / supported stages — NOT a fabricated number.
  int get coveragePercent => _coveragePercent;
  bool get hasScanned => _lastScanAt != null;

  Future<SharedPreferences> _resolvePrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Hydrate from storage. Safe to call more than once.
  Future<void> load() async {
    final prefs = await _resolvePrefs();
    _score = prefs.getInt(_kScore) ?? -1;
    final iso = prefs.getString(_kAt);
    _lastScanAt = iso == null ? null : DateTime.tryParse(iso);
    _threatCount = prefs.getInt(_kThreats) ?? 0;
    _coveragePercent = prefs.getInt(_kCoverage) ?? 0;
    notifyListeners();
  }

  /// Record a completed checkup. [threats] are the scan's raw threat maps
  /// (each carrying a `severity` string); [coveragePercent] is the real
  /// detection-capability figure for this run (0–100).
  Future<void> recordScan({
    required List<Map<String, dynamic>> threats,
    required int coveragePercent,
    required DateTime now,
  }) async {
    _coveragePercent = coveragePercent.clamp(0, 100);
    _threatCount = threats.length;
    _score = computeScore(threats: threats, coveragePercent: _coveragePercent);
    _lastScanAt = now;

    final prefs = await _resolvePrefs();
    await prefs.setInt(_kScore, _score);
    await prefs.setString(_kAt, now.toIso8601String());
    await prefs.setInt(_kThreats, _threatCount);
    await prefs.setInt(_kCoverage, _coveragePercent);
    notifyListeners();
  }

  /// The honest 0–100 rubric, pure and testable.
  ///
  /// Clean baseline by real coverage (bands align with
  /// `ProtectionVerdict.fromScore`: ≥90 excellent · ≥70 good · ≥50
  /// attention · else at-risk):
  ///   coverage ≥75 → 92 · 50–74 → 74 · <50 → 55
  /// Threat penalties (from the clean baseline, floored at 5):
  ///   critical −40 · high −25 · medium −12 · low/info −5
  /// Any critical or high finding additionally caps the score at 45
  /// (at-risk) — a device with live spyware is never "protected".
  @visibleForTesting
  static int computeScore({
    required List<Map<String, dynamic>> threats,
    required int coveragePercent,
  }) {
    final int base = coveragePercent >= 75
        ? 92
        : coveragePercent >= 50
            ? 74
            : 55;

    var score = base;
    var hasSevere = false;
    for (final t in threats) {
      final sev = (t['severity'] ?? '').toString().toUpperCase();
      switch (sev) {
        case 'CRITICAL':
          score -= 40;
          hasSevere = true;
        case 'HIGH':
          score -= 25;
          hasSevere = true;
        case 'MEDIUM':
          score -= 12;
        default:
          score -= 5;
      }
    }
    if (hasSevere) score = math.min(score, 45);
    return score.clamp(5, 100);
  }
}
