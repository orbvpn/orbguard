import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/home/home_signals.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';

/// How what Home knows becomes the score engine's signals. One finding is
/// counted once: under spyware, or under apps to review, never under both.
void main() {
  final DateTime now = DateTime(2026, 11, 25, 12);

  PrivacySignals gather({
    DateTime? lastScanAt,
    int threatCount = 0,
    List<Map<String, dynamic>> findings = const [],
    List<String>? stagesRan,
    bool appAuditPossible = true,
    int? breachedAccounts,
    bool? unknownVpnActive,
    bool alertsOn = false,
    bool alertsPossible = true,
  }) =>
      HomeSignals.gather(
        verdictScore: lastScanAt == null ? -1 : 92,
        lastScanAt: lastScanAt,
        threatCount: threatCount,
        findings: findings,
        stagesRan: stagesRan,
        guardsActive: 3,
        guardsAvailable: 5,
        alertsOn: alertsOn,
        alertsPossible: alertsPossible,
        appAuditPossible: appAuditPossible,
        breachedAccounts: breachedAccounts,
        unknownVpnActive: unknownVpnActive,
        now: now,
      );

  const List<String> allEleven = [
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
  ];

  Map<String, dynamic> finding(String stage,
          {String? app, String id = 'x', String? severity}) =>
      {
        'id': id,
        'stage': stage,
        if (app != null) 'path': app,
        if (severity != null) 'severity': severity,
      };

  test('before any check nothing is known about the device or its apps', () {
    final PrivacySignals s = gather();

    expect(s.daysSinceScan, isNull);
    expect(s.openThreats, 0);
    expect(s.riskyPermissionApps, isNull);
    expect(s.guardsActive, 3);
    expect(s.guardsAvailable, 5);
  });

  test('a clean check that ran the app audit found no apps to review', () {
    final PrivacySignals s = gather(
      lastScanAt: now.subtract(const Duration(days: 2, hours: 3)),
      stagesRan: allEleven,
    );

    expect(s.daysSinceScan, 2);
    expect(s.openThreats, 0);
    expect(s.riskyPermissionApps, 0);
  });

  test('a check that could not run the app audit leaves the apps unknown', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      stagesRan: allEleven.take(5).toList(),
    );

    expect(s.riskyPermissionApps, isNull);
  });

  test('a finding of the device itself is spyware to resolve', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 1,
      findings: [finding('File system')],
      stagesRan: allEleven,
    );

    expect(s.openThreats, 1);
    expect(s.riskyPermissionApps, 0);
  });

  test('a device finding that is low severity is minor', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 1,
      findings: [finding('File system', severity: 'LOW')],
      stagesRan: allEleven,
    );

    expect(s.openThreats, 1);
    expect(s.minorThreatsOnly, isTrue);
  });

  test('one finding above low makes none of them minor', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 2,
      findings: [
        finding('File system', id: 'a', severity: 'LOW'),
        finding('File system', id: 'b', severity: 'MEDIUM'),
      ],
      stagesRan: allEleven,
    );

    expect(s.openThreats, 2);
    expect(s.minorThreatsOnly, isFalse);
  });

  test('a finding with no severity is not minor', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 1,
      findings: [finding('File system')],
      stagesRan: allEleven,
    );

    expect(s.minorThreatsOnly, isFalse);
  });

  test('a finding about another app is an app to review, and not spyware', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 1,
      findings: [finding('Keylogger detection', app: 'com.example.fastkeys')],
      stagesRan: allEleven,
    );

    expect(s.openThreats, 0);
    expect(s.riskyPermissionApps, 1);
  });

  test('one app found by two checks is one app to review', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 3,
      findings: [
        finding('Permission abuse', app: 'com.example.watcher', id: 'a'),
        finding('Accessibility abuse', app: 'com.example.watcher', id: 'b'),
        finding('Location stalkers', app: 'com.example.other', id: 'c'),
      ],
      stagesRan: allEleven,
    );

    expect(s.openThreats, 0);
    expect(s.riskyPermissionApps, 2);
  });

  test('findings kept from before they named their check count as spyware', () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 2,
      findings: [
        {'id': 'old1', 'name': 'Something'},
        {'id': 'old2', 'name': 'Something else'},
      ],
    );

    expect(s.openThreats, 2);
    expect(s.riskyPermissionApps, isNull);
  });

  test('when the list could not be kept, the count still stands as spyware',
      () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      threatCount: 2,
      stagesRan: allEleven,
    );

    expect(s.openThreats, 2);
    expect(s.riskyPermissionApps, isNull,
        reason: 'which of the two were apps is no longer known');
  });

  test('a device that cannot audit apps is told so, and has none to review',
      () {
    final PrivacySignals s = gather(
      lastScanAt: now,
      stagesRan: allEleven.take(5).toList(),
      appAuditPossible: false,
    );

    expect(s.appAuditPossible, isFalse);
    expect(s.riskyPermissionApps, isNull);
  });

  test('breach, VPN and alert answers pass through as they are', () {
    final PrivacySignals s = gather(
      breachedAccounts: 2,
      unknownVpnActive: true,
      alertsOn: true,
      alertsPossible: false,
    );

    expect(s.breachedAccounts, 2);
    expect(s.unknownVpnActive, isTrue);
    expect(s.notificationsGranted, isTrue);
    expect(s.alertsPossible, isFalse);
  });
}
