import 'package:flutter/widgets.dart';

import 'colors.dart';

/// Single source of truth for how a device **protection score** is described to
/// the user.
///
/// A score is 0–100, or any negative value as the "not assessed yet" sentinel.
/// Before this existed the app spoke two contradictory vocabularies for the same
/// device — the Security Center home said "Good Protection" / "At Risk" while
/// the Dashboard card said "Fully Protected" / "Partially Protected" / "Not
/// Protected" and showed a letter grade ("U"). Both now resolve their wording
/// and colors here, so the app never shows two verdicts for one device.
enum ProtectionLevel { notAssessed, excellent, good, attention, atRisk }

class ProtectionVerdict {
  final ProtectionLevel level;
  const ProtectionVerdict(this.level);

  /// Thresholds are the canonical scale (Security Center's): 90 / 70 / 50.
  factory ProtectionVerdict.fromScore(num score) {
    if (score < 0) return const ProtectionVerdict(ProtectionLevel.notAssessed);
    if (score >= 90) return const ProtectionVerdict(ProtectionLevel.excellent);
    if (score >= 70) return const ProtectionVerdict(ProtectionLevel.good);
    if (score >= 50) return const ProtectionVerdict(ProtectionLevel.attention);
    return const ProtectionVerdict(ProtectionLevel.atRisk);
  }

  /// The one canonical status wording. Calm, plain, no fear framing.
  String get label {
    switch (level) {
      case ProtectionLevel.notAssessed:
        return 'Not assessed yet';
      case ProtectionLevel.excellent:
        return 'Excellent protection';
      case ProtectionLevel.good:
        return 'Good protection';
      case ProtectionLevel.attention:
        return 'Needs attention';
      case ProtectionLevel.atRisk:
        return 'At risk';
    }
  }

  /// FILL color — ring / tint / glow (brand status fills; lime is fill-only).
  Color get fill {
    switch (level) {
      case ProtectionLevel.notAssessed:
        return AppColors.idle;
      case ProtectionLevel.excellent:
        return AppColors.success;
      case ProtectionLevel.good:
        return AppColors.successLight;
      case ProtectionLevel.attention:
        return AppColors.severityLow;
      case ProtectionLevel.atRisk:
        return AppColors.error;
    }
  }

  /// Contrast-safe INK — for status TEXT and icons (deep-lime on light, etc.).
  Color get ink {
    switch (level) {
      case ProtectionLevel.notAssessed:
        return AppColors.idle;
      case ProtectionLevel.excellent:
      case ProtectionLevel.good:
        return AppColors.accentInk;
      case ProtectionLevel.attention:
        return AppColors.amberInk;
      case ProtectionLevel.atRisk:
        return AppColors.errorInk;
    }
  }
}
