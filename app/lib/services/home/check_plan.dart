// The checks a full privacy check is made of.
//
// The scan engine (`DeviceScanService`) runs eleven stages and names them the
// way an engineer would. This table gives each one the name a person reads,
// the line shown while it runs, and the shield it belongs to. It also says
// which of them a device can run at all, so Home can draw one ring segment
// per check before the first one starts.
//
// The table promises nothing. What ran, what found something and what could
// not run is decided by the engine's own events, in `CheckRun`.
library;

import 'home_brief.dart';

/// One check of the full privacy check.
class CheckStep {
  const CheckStep({
    required this.stage,
    required this.name,
    required this.doing,
    required this.shield,
    this.androidOnly = false,
  });

  /// The engine's name for the stage. Findings carry it as `stage`.
  final String stage;

  /// What the check looks for, as a person would say it.
  final String name;

  /// The line under Home's headline while this check runs.
  final String doing;

  /// The shield this check reports to.
  final Shield shield;

  /// Only Android lets an app do this. Elsewhere the engine reports it as
  /// not supported, and it is listed as not possible, never as passed.
  final bool androidOnly;
}

abstract final class CheckPlan {
  /// Every check, in the order the engine runs them.
  static const List<CheckStep> all = [
    CheckStep(
      stage: 'Network connections',
      name: 'Connection interception',
      doing: 'Looking for interception',
      shield: Shield.spyware,
    ),
    CheckStep(
      stage: 'Running processes',
      name: 'Injected code',
      doing: 'Checking for injected code',
      shield: Shield.spyware,
    ),
    CheckStep(
      stage: 'File system',
      name: 'Spyware traces in files',
      doing: 'Looking for spyware traces',
      shield: Shield.spyware,
    ),
    CheckStep(
      stage: 'App databases',
      name: 'App data tampering',
      doing: 'Checking app data for tampering',
      shield: Shield.spyware,
    ),
    CheckStep(
      stage: 'Memory',
      name: 'Memory tampering',
      doing: 'Checking memory for tampering',
      shield: Shield.spyware,
    ),
    CheckStep(
      stage: 'Certificate analysis',
      name: 'Untrusted certificates',
      doing: 'Looking for untrusted certificates',
      shield: Shield.spyware,
      androidOnly: true,
    ),
    CheckStep(
      stage: 'Permission abuse',
      name: 'Risky app permissions',
      doing: 'Auditing app permissions',
      shield: Shield.watching,
      androidOnly: true,
    ),
    CheckStep(
      stage: 'Accessibility abuse',
      name: 'Stalkerware services',
      doing: 'Looking for stalkerware services',
      shield: Shield.watching,
      androidOnly: true,
    ),
    CheckStep(
      stage: 'Keylogger detection',
      name: 'Keyloggers',
      doing: 'Checking keyboards for keyloggers',
      shield: Shield.watching,
      androidOnly: true,
    ),
    CheckStep(
      stage: 'Location stalkers',
      name: 'Location tracking',
      doing: 'Checking who follows your location',
      shield: Shield.watching,
      androidOnly: true,
    ),
    CheckStep(
      stage: 'App malware scan',
      name: 'App malware',
      doing: 'Scanning your apps for malware',
      shield: Shield.spyware,
      androidOnly: true,
    ),
  ];

  /// The check that looks at the connection itself. A VPN or proxy it sees
  /// is not one of its findings: that state belongs to the Hidden VPN shield.
  /// So while one waits to be confirmed, this check is not called clean.
  static const String rerouteStage = 'Network connections';

  /// The checks expected to run on this device, in order.
  static List<CheckStep> forDevice({required bool android}) => [
        for (final CheckStep step in all)
          if (android || !step.androidOnly) step,
      ];

  /// The step for an engine stage. A stage this table does not know (one
  /// added to the engine later) still gets a readable name, and reports to
  /// the Spyware shield like every other check of the device itself.
  static CheckStep byStage(String stage) {
    for (final CheckStep step in all) {
      if (step.stage == stage) return step;
    }
    final String words = stage.trim().isEmpty ? 'device check' : stage.trim();
    return CheckStep(
      stage: stage,
      name: words[0].toUpperCase() + words.substring(1),
      doing: 'Checking ${words[0].toLowerCase()}${words.substring(1)}',
      shield: Shield.spyware,
    );
  }

  /// The shield a finding belongs to: the shield of the check that found it.
  /// A finding kept from before findings named their check counts as Spyware,
  /// which is where every finding was shown then.
  static Shield shieldOf(Map<String, dynamic> finding) {
    final Object? stage = finding['stage'];
    return stage is String ? byStage(stage).shield : Shield.spyware;
  }
}
