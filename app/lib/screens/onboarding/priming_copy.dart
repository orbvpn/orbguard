// lib/screens/onboarding/priming_copy.dart
//
// Copy + step definitions for the first-run permission priming flow
// (PermissionPrimingScreen). One place to read every value line, so the
// honest-copy rules are easy to audit:
//   • one calm sentence per permission — the WHY, never fear
//   • no Android-isms on iOS (no SMS/storage/usage/accessibility asks there)
//   • steps that only deep-link to system Settings say so.

import 'package:flutter/foundation.dart' show TargetPlatform;

import '../../presentation/widgets/duotone_icon.dart';

/// Stable step identifiers — the screen dispatches requests on these and keys
/// each card as `priming_step_<id>` for tests.
class PrimingStepIds {
  PrimingStepIds._();

  static const String notifications = 'notifications';
  static const String storage = 'storage';
  static const String sms = 'sms';
  static const String location = 'location';
  static const String usageAccess = 'usage_access';
  static const String accessibility = 'accessibility';
}

/// One permission step: what it is, why it helps (one plain-English
/// sentence), and how its action button reads.
class PrimingStep {
  final String id;

  /// Icon name — must exist as `assets/icons/<icon>.svg`.
  final String icon;
  final String title;

  /// The value line: the WHY in one calm sentence.
  final String value;
  final String buttonLabel;

  /// True for the advanced steps that can only deep-link into system
  /// Settings (usage access, accessibility). The screen labels these
  /// "Opens system Settings" and never claims they are on afterwards.
  final bool opensSystemSettings;

  const PrimingStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.value,
    this.buttonLabel = 'Allow',
    this.opensSystemSettings = false,
  });
}

const PrimingStep _notifications = PrimingStep(
  id: PrimingStepIds.notifications,
  icon: AppIcons.bell,
  title: 'Notifications',
  value: 'Get alerted the moment we spot a threat.',
);

const PrimingStep _storage = PrimingStep(
  id: PrimingStepIds.storage,
  icon: AppIcons.folder,
  title: 'Storage',
  value: 'Let OrbGuard check files and apps for spyware.',
);

const PrimingStep _sms = PrimingStep(
  id: PrimingStepIds.sms,
  icon: AppIcons.chatDots,
  title: 'SMS',
  value: 'Catch scam texts before you tap them.',
);

const PrimingStep _locationAndroid = PrimingStep(
  id: PrimingStepIds.location,
  icon: AppIcons.mapPoint,
  title: 'Location',
  value: 'Spot apps secretly tracking where you go, and test Wi-Fi safety.',
);

/// iOS-honest location copy: iOS never lets one app see another app's
/// tracking, so the true value here is Wi-Fi network safety (reading the
/// network you're on requires location permission on iOS).
const PrimingStep _locationIos = PrimingStep(
  id: PrimingStepIds.location,
  icon: AppIcons.mapPoint,
  title: 'Location',
  value: "Check that the Wi-Fi network you're on is safe.",
);

const PrimingStep _usageAccess = PrimingStep(
  id: PrimingStepIds.usageAccess,
  icon: AppIcons.chartSquare,
  title: 'Usage access',
  value: 'See which apps watch you in the background.',
  buttonLabel: 'Turn on',
  opensSystemSettings: true,
);

const PrimingStep _accessibility = PrimingStep(
  id: PrimingStepIds.accessibility,
  icon: 'accessibility',
  title: 'Accessibility',
  value: 'Detect stalkerware screen-readers.',
  buttonLabel: 'Turn on',
  opensSystemSettings: true,
);

/// The ordered steps for a platform. Android gets the full set (four
/// one-tap permissions + two advanced Settings deep-links); iOS — and any
/// other platform — gets only the asks that actually exist there:
/// notifications and location.
List<PrimingStep> primingStepsFor(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return const [
      _notifications,
      _storage,
      _sms,
      _locationAndroid,
      _usageAccess,
      _accessibility,
    ];
  }
  return const [_notifications, _locationIos];
}
