// The breach signal Home reads: how many watched email addresses sit in a
// known breach the person has not dealt with. `null` is "nothing known",
// never "safe".

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/models/api/sms_analysis.dart';
import 'package:orbguard/models/api/threat_indicator.dart';
import 'package:orbguard/providers/darkweb_provider.dart';

MonitoredAsset _email(
  String id, {
  String value = 'alex@example.com',
  int breachCount = 0,
  DateTime? lastChecked,
}) =>
    MonitoredAsset(
      id: id,
      type: AssetType.email,
      value: value,
      addedAt: DateTime(2026, 1, 1),
      lastChecked: lastChecked,
      breachCount: breachCount,
    );

BreachAlert _alert(String id, String assetId, String breachName,
        {bool isRead = false}) =>
    BreachAlert(
      id: id,
      assetId: assetId,
      assetType: '',
      assetValue: '',
      breach: BreachInfo(
        name: breachName,
        domain: '',
        dataClasses: const [],
        isVerified: false,
        isSensitive: false,
      ),
      severity: SeverityLevel.high,
      alertedAt: DateTime(2026, 11, 1),
      isRead: isRead,
    );

final DateTime _checked = DateTime(2026, 11, 20, 9);

Future<DarkWebProvider> _provider({
  List<MonitoredAsset> assets = const [],
  List<BreachAlert> alerts = const [],
  Map<String, BreachCheckResult> checkResults = const {},
}) async {
  final p = DarkWebProvider(autoInit: false);
  await p.debugLoad(assets: assets, alerts: alerts, checkResults: checkResults);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('openBreachedAccounts', () {
    test('is null when no email address is watched', () async {
      final p = await _provider();
      expect(p.openBreachedAccounts, isNull);
      expect(p.openBreaches, isEmpty);
      expect(p.lastBreachCheckAt, isNull);
    });

    test('ignores watched assets that are not email addresses', () async {
      final p = await _provider(assets: [
        MonitoredAsset(
          id: 'p1',
          type: AssetType.phone,
          value: '+15550100',
          addedAt: DateTime(2026),
          lastChecked: _checked,
          breachCount: 3,
        ),
      ]);
      expect(p.openBreachedAccounts, isNull);
    });

    test('is null when watched addresses were never checked', () async {
      final p = await _provider(assets: [_email('a1'), _email('a2')]);
      expect(p.openBreachedAccounts, isNull);
      expect(p.lastBreachCheckAt, isNull);
    });

    test('is 0 when checked and clean', () async {
      final p = await _provider(assets: [_email('a1', lastChecked: _checked)]);
      expect(p.openBreachedAccounts, 0);
      expect(p.lastBreachCheckAt, _checked);
    });

    test('is 1 for one breached address', () async {
      final p = await _provider(assets: [
        _email('a1', breachCount: 2, lastChecked: _checked),
        _email('a2', value: 'sam@example.com', lastChecked: _checked),
      ]);
      expect(p.openBreachedAccounts, 1);
      expect(p.openBreaches.single.id, 'a1');
    });

    test('lastBreachCheckAt is the newest check among email addresses',
        () async {
      final later = _checked.add(const Duration(days: 2));
      final p = await _provider(assets: [
        _email('a1', lastChecked: _checked),
        _email('a2', value: 'sam@example.com', lastChecked: later),
      ]);
      expect(p.lastBreachCheckAt, later);
    });
  });

  group('alerts and breachCount', () {
    test('an alert for an address whose count is 0 still opens it', () async {
      // The backend keeps alerts per (asset, breach name) forever, but a
      // re-add whose check fails, or a provider that drops out of a refresh,
      // rewrites breach_count lower. The alert is still a real breach.
      final p = await _provider(
        assets: [_email('a1', lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      expect(p.openBreachedAccounts, 1);
      expect(p.breachCountFor('a1'), 1);
    });

    test('an alert makes an address known even with no lastChecked', () async {
      final p = await _provider(
        assets: [_email('a1')],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      expect(p.openBreachedAccounts, 1);
    });

    test('count is the larger of breachCount and the distinct alerts',
        () async {
      final p = await _provider(
        assets: [_email('a1', breachCount: 1, lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe'), _alert('al2', 'a1', 'Canva')],
      );
      expect(p.breachCountFor('a1'), 2);
    });

    test('alerts for another address do not open this one', () async {
      final p = await _provider(
        assets: [_email('a1', lastChecked: _checked)],
        alerts: [_alert('al1', 'zz', 'Adobe')],
      );
      expect(p.openBreachedAccounts, 0);
    });
  });

  group('markBreachHandled', () {
    test('handled gives 0', () async {
      final p = await _provider(
          assets: [_email('a1', breachCount: 2, lastChecked: _checked)]);
      var notified = 0;
      p.addListener(() => notified++);

      await p.markBreachHandled('a1');

      expect(p.openBreachedAccounts, 0);
      expect(p.openBreaches, isEmpty);
      expect(notified, greaterThan(0));
    });

    test(
        'a later check with MORE breaches reopens it; the same number does not',
        () async {
      final p = await _provider(
          assets: [_email('a1', breachCount: 2, lastChecked: _checked)]);
      await p.markBreachHandled('a1');

      await p.debugLoad(
          assets: [_email('a1', breachCount: 2, lastChecked: _checked)]);
      expect(p.openBreachedAccounts, 0);

      await p.debugLoad(
          assets: [_email('a1', breachCount: 3, lastChecked: _checked)]);
      expect(p.openBreachedAccounts, 1);
    });

    test('a NEW breach name reopens it even when the count is unchanged',
        () async {
      final p = await _provider(
        assets: [_email('a1', breachCount: 1, lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      await p.markBreachHandled('a1');
      expect(p.openBreachedAccounts, 0);

      await p.debugLoad(
        assets: [_email('a1', breachCount: 1, lastChecked: _checked)],
        alerts: [_alert('al2', 'a1', 'Canva')],
      );
      expect(p.openBreachedAccounts, 1);
    });

    test('handled state survives a new provider instance', () async {
      final assets = [_email('a1', breachCount: 2, lastChecked: _checked)];
      final first = await _provider(assets: assets);
      await first.markBreachHandled('a1');

      final second = await _provider(assets: assets);
      expect(second.openBreachedAccounts, 0);
    });

    test("marks that address's alerts read, and only that address's", () async {
      final p = await _provider(
        assets: [
          _email('a1', lastChecked: _checked),
          _email('a2', value: 'sam@example.com', lastChecked: _checked),
        ],
        alerts: [
          _alert('al1', 'a1', 'Adobe'),
          _alert('al2', 'a2', 'Canva'),
        ],
      );
      await p.markBreachHandled('a1');

      expect(p.unreadAlerts.map((a) => a.id), ['al2']);
      expect(p.alerts.firstWhere((a) => a.id == 'al1').isRead, isTrue);
      expect(p.openBreaches.map((a) => a.id), ['a2']);
    });

    test('reopenBreach undoes it, alerts included', () async {
      final p = await _provider(
        assets: [_email('a1', lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      await p.markBreachHandled('a1');
      await p.reopenBreach('a1');

      expect(p.openBreachedAccounts, 1);
      expect(p.unreadAlerts.map((a) => a.id), ['al1']);

      final again = await _provider(
        assets: [_email('a1', lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      expect(again.openBreachedAccounts, 1);
    });

    test('reopenBreach leaves alerts the person had read before', () async {
      final p = await _provider(
        assets: [_email('a1', lastChecked: _checked)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      await p.markAlertAsRead('al1');
      await p.markBreachHandled('a1');
      await p.reopenBreach('a1');

      expect(p.unreadAlerts, isEmpty);
      expect(p.openBreachedAccounts, 1);
    });

    test('an unknown id changes nothing', () async {
      final p = await _provider(
          assets: [_email('a1', breachCount: 1, lastChecked: _checked)]);
      await p.markBreachHandled('nope');
      expect(p.openBreachedAccounts, 1);
    });
  });

  group('newestNamedBreachFor', () {
    test('names the newest dated breach from a check result', () async {
      final p = await _provider(
        assets: [_email('a1', breachCount: 2, lastChecked: _checked)],
        checkResults: {
          'alex@example.com': BreachCheckResult(
            email: 'alex@example.com',
            isBreached: true,
            breachCount: 2,
            breaches: [
              BreachInfo(
                  name: 'Adobe',
                  title: 'Adobe',
                  domain: 'adobe.com',
                  breachDate: DateTime(2013, 10, 4),
                  dataClasses: const [],
                  isVerified: true,
                  isSensitive: false),
              BreachInfo(
                  name: 'Canva',
                  title: 'Canva',
                  domain: 'canva.com',
                  breachDate: DateTime(2019, 5, 24),
                  dataClasses: const [],
                  isVerified: true,
                  isSensitive: false),
            ],
            checkedAt: _checked,
          ),
        },
      );
      final b = p.newestNamedBreachFor('a1');
      expect(b?.name, 'Canva');
      expect(b?.breachDate?.year, 2019);
    });

    test('falls back to an alert name, and to nothing when none is known',
        () async {
      final p = await _provider(
        assets: [
          _email('a1', lastChecked: _checked),
          _email('a2',
              value: 'sam@example.com', breachCount: 2, lastChecked: _checked),
        ],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      expect(p.newestNamedBreachFor('a1')?.name, 'Adobe');
      expect(p.newestNamedBreachFor('a2'), isNull);
    });
  });

  group('isBreachHandled', () {
    test('true only after it was handled and while nothing new appeared',
        () async {
      final p = await _provider(
          assets: [_email('a1', breachCount: 1, lastChecked: _checked)]);
      expect(p.isBreachHandled('a1'), isFalse);

      await p.markBreachHandled('a1');
      expect(p.isBreachHandled('a1'), isTrue);

      await p.debugLoad(
          assets: [_email('a1', breachCount: 2, lastChecked: _checked)]);
      expect(p.isBreachHandled('a1'), isFalse);
      expect(p.openBreaches.single.id, 'a1');
    });

    test('a clean address is neither open nor handled', () async {
      final p = await _provider(assets: [_email('a1', lastChecked: _checked)]);
      await p.markBreachHandled('a1');
      expect(p.isBreachHandled('a1'), isFalse);
      expect(p.openBreaches, isEmpty);
    });
  });

  group('leak details for one address', () {
    test('a check result already in memory is shown without a new check',
        () async {
      final r = BreachCheckResult(
        email: 'alex@example.com',
        isBreached: true,
        breachCount: 1,
        breaches: [
          BreachInfo(
              name: 'Canva',
              domain: 'canva.com',
              dataClasses: const ['Email addresses', 'Passwords'],
              isVerified: true,
              isSensitive: false),
        ],
        checkedAt: _checked,
      );
      final p = await _provider(
        assets: [_email('a1', breachCount: 1, lastChecked: _checked)],
        checkResults: {'alex@example.com': r},
      );
      expect(p.canShowLeakDetailsFor('a1'), isTrue);
      await p.showLeakDetailsFor('a1');
      expect(p.lastCheckResult, same(r));
      expect(p.isCheckingEmail, isFalse);
    });

    test('a plain address can be checked to show its details', () async {
      final p = await _provider(
          assets: [_email('a1', breachCount: 1, lastChecked: _checked)]);
      expect(p.canShowLeakDetailsFor('a1'), isTrue);
    });

    test('an address known only in masked form cannot be', () async {
      final p = await _provider(assets: [
        _email('a1',
            value: 'al***@example.com', breachCount: 1, lastChecked: _checked),
      ]);
      expect(p.canShowLeakDetailsFor('a1'), isFalse);
      await p.showLeakDetailsFor('a1');
      expect(p.lastCheckResult, isNull);
      expect(p.isCheckingEmail, isFalse);
    });

    test('an unknown id cannot be', () async {
      final p = await _provider();
      expect(p.canShowLeakDetailsFor('nope'), isFalse);
    });
  });
}
