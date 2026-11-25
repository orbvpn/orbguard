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

import 'dart:convert';
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
  static const String _kChecksRun = 'verdict_checks_run';
  static const String _kFindings = 'verdict_findings_json';
  static const String _kStagesRan = 'verdict_stages_ran';
  static const String _kStagesNotPossible = 'verdict_stages_not_possible';
  static const String _kStagesFailed = 'verdict_stages_failed';

  int _score = -1;
  DateTime? _lastScanAt;
  int _threatCount = 0;
  int _coveragePercent = 0;
  int? _checksRun;
  List<Map<String, dynamic>> _findings = const [];
  List<String>? _stagesRan;
  List<String> _stagesNotPossible = const [];
  List<String> _stagesFailed = const [];

  /// 0–100 verdict score, or -1 when no scan has ever run
  /// (feed straight into `ProtectionVerdict.fromScore`).
  int get score => _score;
  DateTime? get lastScanAt => _lastScanAt;
  int get threatCount => _threatCount;

  /// How much of the device the scan could genuinely check (0–100), from
  /// granted permissions / supported stages — NOT a fabricated number.
  int get coveragePercent => _coveragePercent;

  /// How many checks the latest run completed, or null when that run did not
  /// report a count (never the count of an earlier run).
  int? get checksRun => _checksRun;
  bool get hasScanned => _lastScanAt != null;

  /// The checks the latest run was made of, by the engine's stage names
  /// (`CheckPlan.byStage` has the words). Null when that run did not say,
  /// which is "not known" and never "none".
  List<String>? get stagesRan =>
      _stagesRan == null ? null : List.unmodifiable(_stagesRan!);

  /// Checks the device did not let that run make. Never counted as passed.
  List<String> get stagesNotPossible => List.unmodifiable(_stagesNotPossible);

  /// Checks that should have run in that run and broke.
  List<String> get stagesFailed => List.unmodifiable(_stagesFailed);

  /// What the latest check found, as the scanner reported it, kept so Home
  /// can show it again after the app was closed. Empty when that check found
  /// nothing, and also after a restart when the list could not be kept or
  /// read back: then [threatCount] still says how many there were, and a new
  /// check is the only honest way to see them.
  List<Map<String, dynamic>> get findings => List.unmodifiable(_findings);

  Future<SharedPreferences> _resolvePrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Hydrate from storage. Safe to call more than once. Reads the store
  /// afresh, so a verdict another isolate wrote (the scheduled check runs in
  /// WorkManager's) is seen too.
  Future<void> load() async {
    final prefs = await _resolvePrefs();
    await prefs.reload();
    _score = prefs.getInt(_kScore) ?? -1;
    final iso = prefs.getString(_kAt);
    _lastScanAt = iso == null ? null : DateTime.tryParse(iso);
    _threatCount = prefs.getInt(_kThreats) ?? 0;
    _coveragePercent = prefs.getInt(_kCoverage) ?? 0;
    _checksRun = prefs.getInt(_kChecksRun);
    _findings = _readFindings(prefs.getString(_kFindings));
    _stagesRan = prefs.getStringList(_kStagesRan);
    _stagesNotPossible = prefs.getStringList(_kStagesNotPossible) ?? const [];
    _stagesFailed = prefs.getStringList(_kStagesFailed) ?? const [];
    notifyListeners();
  }

  /// The stored list, or nothing when it is missing, unreadable, or not the
  /// list the stored count describes.
  List<Map<String, dynamic>> _readFindings(String? stored) {
    if (stored == null) return const [];
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List || decoded.length != _threatCount) return const [];
      return [
        for (final Object? item in decoded)
          Map<String, dynamic>.from(item! as Map),
      ];
    } on Object {
      return const [];
    }
  }

  /// Record a completed checkup. [threats] are the scan's raw threat maps
  /// (each carrying a `severity` string); [coveragePercent] is the real
  /// detection-capability figure for this run (0–100); [checksRun] is how
  /// many checks this run completed, when the caller knows. [stagesRan],
  /// [stagesNotPossible] and [stagesFailed] name the checks this run was
  /// made of, when the caller knows; left out, an earlier run's lists are
  /// dropped rather than passed off as this run's.
  Future<void> recordScan({
    required List<Map<String, dynamic>> threats,
    required int coveragePercent,
    required DateTime now,
    int? checksRun,
    List<String>? stagesRan,
    List<String> stagesNotPossible = const [],
    List<String> stagesFailed = const [],
  }) async {
    _coveragePercent = coveragePercent.clamp(0, 100);
    _threatCount = threats.length;
    _checksRun = checksRun;
    _score = computeScore(threats: threats, coveragePercent: _coveragePercent);
    _lastScanAt = now;

    _findings = [for (final t in threats) Map<String, dynamic>.of(t)];
    _stagesRan = stagesRan == null ? null : List.of(stagesRan);
    _stagesNotPossible = List.of(stagesNotPossible);
    _stagesFailed = List.of(stagesFailed);

    // The scanner passes on whatever the platform sent. A finding that will
    // not go into storage costs the list kept across restarts, never the
    // verdict, and never the list for as long as the app stays open.
    String? written;
    try {
      written = jsonEncode(threats);
    } on JsonUnsupportedObjectError {
      written = null;
    }

    final prefs = await _resolvePrefs();
    await prefs.setInt(_kScore, _score);
    await prefs.setString(_kAt, now.toIso8601String());
    await prefs.setInt(_kThreats, _threatCount);
    await prefs.setInt(_kCoverage, _coveragePercent);
    if (checksRun == null) {
      await prefs.remove(_kChecksRun);
    } else {
      await prefs.setInt(_kChecksRun, checksRun);
    }
    if (written == null) {
      await prefs.remove(_kFindings);
    } else {
      await prefs.setString(_kFindings, written);
    }
    if (stagesRan == null) {
      await prefs.remove(_kStagesRan);
    } else {
      await prefs.setStringList(_kStagesRan, stagesRan);
    }
    await prefs.setStringList(_kStagesNotPossible, stagesNotPossible);
    await prefs.setStringList(_kStagesFailed, stagesFailed);
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
