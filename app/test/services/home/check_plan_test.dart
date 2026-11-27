import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/home_brief.dart';

/// The checks a full privacy check is made of: what each is called, what it
/// says while it runs, which shield it belongs to, and where it can run.
void main() {
  test('an Android phone runs all eleven checks, in the order the engine does',
      () {
    final List<CheckStep> steps = CheckPlan.forDevice(android: true);

    expect(steps.map((s) => s.stage), [
      'Network connections',
      'Running processes',
      'File system',
      'App databases',
      'Memory',
      'Certificate analysis',
      'Permission abuse',
      'Accessibility abuse',
      'Keylogger detection',
      'Location stalkers',
      'App malware scan',
    ]);
  });

  test('an iPhone runs the five checks iOS allows', () {
    final List<CheckStep> steps = CheckPlan.forDevice(android: false);

    expect(steps.map((s) => s.name), [
      'Connection interception',
      'Injected code',
      'Spyware traces in files',
      'App data tampering',
      'Memory tampering',
    ]);
  });

  test('every check has a name and a line for while it runs, with no dash', () {
    for (final CheckStep step in CheckPlan.all) {
      expect(step.name, isNotEmpty);
      expect(step.doing, isNotEmpty);
      expect('${step.name} ${step.doing}', isNot(matches(RegExp('[—–·]'))));
    }
  });

  test('the four checks that look at other apps belong to Who is watching', () {
    expect(
      CheckPlan.all
          .where((s) => s.shield == Shield.watching)
          .map((s) => s.stage),
      [
        'Permission abuse',
        'Accessibility abuse',
        'Keylogger detection',
        'Location stalkers',
      ],
    );
    expect(
      CheckPlan.all
          .where((s) => s.shield != Shield.watching)
          .every((s) => s.shield == Shield.spyware),
      isTrue,
    );
  });

  test('a finding belongs to the shield of the check that found it', () {
    expect(
        CheckPlan.shieldOf({'stage': 'Keylogger detection'}), Shield.watching);
    expect(CheckPlan.shieldOf({'stage': 'App malware scan'}), Shield.spyware);
  });

  test('a finding with no check named, or an unknown one, belongs to Spyware',
      () {
    expect(CheckPlan.shieldOf({'name': 'Old finding'}), Shield.spyware);
    expect(CheckPlan.shieldOf({'stage': 'Something new'}), Shield.spyware);
  });

  test('a check the plan does not know gets a readable name from its stage',
      () {
    final CheckStep step = CheckPlan.byStage('thermal sensors');

    expect(step.name, 'Thermal sensors');
    expect(step.doing, 'Checking thermal sensors');
    expect(step.shield, Shield.spyware);
  });

  group('a computer', () {
    test('is checked in six areas, the tabs of its Desktop Security page',
        () {
      for (final TargetPlatform platform in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          CheckPlan.forPlatform(platform).map((s) => s.name),
          [
            'Startup items',
            'Code signing',
            'Firewall',
            'Network',
            'Browser',
            'Quarantine',
          ],
          reason: '$platform',
        );
      }
    });

    test('says what each area does while it runs, with no dash', () {
      expect(CheckPlan.computer.map((s) => s.doing), [
        'Looking at what starts at login',
        'Checking who signed your apps',
        'Checking the system firewall',
        'Checking your network connections',
        'Checking your browsers',
        'Reviewing quarantined files',
      ]);
      for (final CheckStep step in CheckPlan.computer) {
        expect('${step.name} ${step.doing}', isNot(matches(RegExp('[—–·]'))));
        // The Spyware shield covers every area on a computer.
        expect(step.shield, Shield.spyware);
        expect(step.androidOnly, isFalse);
      }
    });

    test('names its areas apart from the phone checks', () {
      final Set<String> phone = {for (final s in CheckPlan.all) s.stage};
      for (final CheckStep step in CheckPlan.computer) {
        expect(phone.contains(step.stage), isFalse, reason: step.stage);
        expect(CheckPlan.byStage(step.stage).name, step.name);
      }
    });

    test('a phone keeps its own checks', () {
      expect(CheckPlan.forPlatform(TargetPlatform.android),
          CheckPlan.forDevice(android: true));
      expect(CheckPlan.forPlatform(TargetPlatform.iOS),
          CheckPlan.forDevice(android: false));
    });
  });
}
