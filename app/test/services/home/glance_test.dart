// What a widget, the lock screen and the menu bar show of Home.
//
// A glance is worked out from the same HomeBrief Home draws, so it can never
// say more than Home says. These tests hold its honesty rules:
//  - nothing reads as all clear before a check, or after a shallow or old one
//  - a gap is named by what was found
//  - the score and the all clear stop being shown once the check no longer
//    speaks for today, even if the app is not opened again
//  - the native side is told only when something it shows has changed

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/glance.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/home_today.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';

final _now = DateTime(2026, 11, 25, 9, 41);

GuardStatus _guard(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

List<GuardStatus> _guards({bool watching = true}) => [
      _guard('spyware_watch',
          watching ? GuardState.active : GuardState.actionNeeded),
      _guard('breach', GuardState.active),
      _guard('alerts', GuardState.active),
    ];

PrivacySignals _signals({
  int lastScanScore = 92,
  int daysSinceScan = 0,
  int openThreats = 0,
  int breachedAccounts = 0,
}) =>
    PrivacySignals(
      lastScanScore: lastScanScore,
      daysSinceScan: daysSinceScan,
      openThreats: openThreats,
      guardsActive: 3,
      guardsAvailable: 3,
      breachedAccounts: breachedAccounts,
      riskyPermissionApps: 0,
      unknownVpnActive: false,
      notificationsGranted: true,
    );

({HomeBrief brief, DateTime? at}) _read({
  bool checked = true,
  Duration since = const Duration(hours: 2),
  int verdictScore = 92,
  int openThreats = 0,
  int breachedAccounts = 0,
  bool watching = true,
  String noun = 'phone',
}) {
  final DateTime? at = checked ? _now.subtract(since) : null;
  final PrivacySignals signals = _signals(
    lastScanScore: verdictScore,
    daysSinceScan: since.inDays,
    openThreats: openThreats,
    breachedAccounts: breachedAccounts,
  );
  return (
    brief: HomeBrief.from(
      hasScanned: checked,
      verdictScore: checked ? verdictScore : -1,
      lastScanAt: at,
      checksRun: checked ? 11 : null,
      openThreats: openThreats,
      breachedAccounts: breachedAccounts,
      score: const PrivacyScoreEngine().compute(signals),
      guards: _guards(watching: watching),
      guardsResolved: true,
      now: _now,
      deviceNoun: noun,
    ),
    at: at,
  );
}

Glance _glance({
  bool checked = true,
  Duration since = const Duration(hours: 2),
  int verdictScore = 92,
  int openThreats = 0,
  int breachedAccounts = 0,
  bool watching = true,
  String noun = 'phone',
}) {
  final r = _read(
    checked: checked,
    since: since,
    verdictScore: verdictScore,
    openThreats: openThreats,
    breachedAccounts: breachedAccounts,
    watching: watching,
    noun: noun,
  );
  return Glance.from(brief: r.brief, lastScanAt: r.at);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('before the first check', () {
    test('it claims nothing and asks for the check', () {
      final Glance g = _glance(checked: false);
      expect(g.moment, HomeMoment.fresh);
      expect(g.title, 'Not checked yet');
      expect(g.line, 'One tap. The check runs on this phone.');
      expect(g.score, isNull);
      expect(g.ring, GlanceRing.fresh);
      expect(g.checkedAt, isNull);
      expect(g.staleAt, isNull);
    });
  });

  group('after a clean check', () {
    test('a recent deep check is all clear, with its score and time', () {
      final Glance g = _glance();
      expect(g.moment, HomeMoment.clear);
      expect(g.title, 'All clear');
      expect(g.line, isNull);
      expect(g.score, _read().brief.score);
      expect(g.gaps, isEmpty);
      expect(g.ring, GlanceRing.open);
      expect(g.checkedAt, _now.subtract(const Duration(hours: 2)));
    });

    test('a shallow check is never all clear', () {
      final Glance g = _glance(verdictScore: 60);
      expect(g.title, 'Nothing found so far');
    });

    test('an old check is never all clear', () {
      final Glance g = _glance(since: const Duration(days: 9));
      expect(g.title, 'Nothing found last time');
    });

    test('it stops speaking for today when the score would change', () {
      final Glance g = _glance();
      // The score's recency points go, and Home stops saying all clear, once
      // eight whole days have passed since the check.
      expect(
          g.staleAt,
          _now.subtract(const Duration(hours: 2)).add(
                const Duration(days: 8),
              ));
      expect(g.staleTitle, 'Nothing found last time');
      expect(g.staleLine, 'Time for a fresh check');
    });

    test('nothing on watch between checks greys the ring', () {
      final Glance g = _glance(watching: false);
      expect(g.ring, GlanceRing.still);
      expect(g.title, 'All clear');
    });
  });

  group('with a gap open', () {
    test('a breach is named by what happened, and opens toward its shield', () {
      final Glance g = _glance(breachedAccounts: 1);
      expect(g.moment, HomeMoment.gap);
      expect(g.title, 'One gap to close');
      expect(g.line, 'Your email was in a data breach');
      expect(g.gaps, [Shield.identity.angle]);
    });

    test('a severe finding is said plainly, for this device', () {
      final Glance g = _glance(verdictScore: 30, openThreats: 2, noun: 'Mac');
      expect(g.title, 'Your Mac needs attention');
    });

    test('a gap does not go away with time, only its score does', () {
      final Glance g = _glance(breachedAccounts: 1);
      expect(g.staleAt, isNotNull);
      expect(g.staleTitle, isNull);
      expect(g.staleLine, isNull);
    });
  });

  group('for a window with more room', () {
    test('it carries Home\'s own headline and proof line', () {
      final r = _read();
      final Glance g = Glance.from(brief: r.brief, lastScanAt: r.at);
      expect(g.headline, r.brief.headline);
      expect(g.proof, r.brief.proof);
    });

    test('it carries what Today records, newest first, three at most', () {
      final r = _read();
      final HomeToday today = HomeToday.from(
        lastScanAt: _now.subtract(const Duration(hours: 2)),
        threatCount: 0,
        blockedToday: 23,
        breachCheckedAt: _now.subtract(const Duration(hours: 5)),
        streakDays: 0,
        now: _now,
      );
      final Glance g =
          Glance.from(brief: r.brief, lastScanAt: r.at, today: today);
      expect([
        for (final e in g.events) e.kind
      ], [
        HomeEventKind.blocked,
        HomeEventKind.check,
        HomeEventKind.breach,
      ]);
      expect(g.events.first.at, isNull,
          reason: 'a count for the day has no single moment');
      expect(g.events[1].text, 'Privacy check ran, nothing found');
      expect(g.events[1].at, _now.subtract(const Duration(hours: 2)));
    });

    test('without a record it carries no rows', () {
      expect(_glance().events, isEmpty);
    });
  });

  group('the wire form', () {
    test('carries plain values the native side can read', () {
      final Map<String, Object?> m = _glance(breachedAccounts: 1).toMap();
      expect(m['v'], 1);
      expect(m['moment'], 'gap');
      expect(m['ring'], 'open');
      expect(m['gaps'], [150.0]);
      expect(m['checkedAt'], isA<int>());
      expect(m['staleAt'], isA<int>());
      expect(m['title'], 'One gap to close');
      expect(m['headline'], 'One gap to close.');
      expect(m['events'], isA<List>());
    });

    test('a row is a kind, its words and its moment', () {
      final r = _read();
      final Glance g = Glance.from(
        brief: r.brief,
        lastScanAt: r.at,
        today: HomeToday.from(
          lastScanAt: r.at,
          threatCount: 0,
          blockedToday: null,
          breachCheckedAt: null,
          streakDays: 0,
          now: _now,
        ),
      );
      expect(g.toMap()['events'], [
        {
          'kind': 'check',
          'text': 'Privacy check ran, nothing found',
          'at': r.at!.millisecondsSinceEpoch,
        },
      ]);
    });

    test('says nothing with a dash a person would not type', () {
      for (final Glance g in [
        _glance(checked: false),
        _glance(),
        _glance(verdictScore: 60),
        _glance(since: const Duration(days: 9)),
        _glance(breachedAccounts: 1),
        _glance(verdictScore: 30, openThreats: 2),
      ]) {
        final String words = [g.title, g.line, g.staleTitle, g.staleLine]
            .whereType<String>()
            .join(' ');
        expect(words, isNot(contains('—')));
        expect(words, isNot(contains('–')));
      }
    });
  });

  group('GlanceSync', () {
    const MethodChannel channel = MethodChannel('com.orb.guard/glance');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('tells the native side what to show', () async {
      final List<MethodCall> sent = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
      final GlanceSync sync = GlanceSync();
      await sync.push(_glance());
      expect(sent.single.method, 'update');
      expect((sent.single.arguments as Map)['title'], 'All clear');
    });

    test('says it once while nothing changes', () async {
      final List<MethodCall> sent = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
      final GlanceSync sync = GlanceSync();
      await sync.push(_glance());
      await sync.push(_glance());
      await sync.push(_glance(breachedAccounts: 1));
      expect(sent, hasLength(2));
    });

    test('a device with no widget to tell is quiet', () async {
      final GlanceSync sync = GlanceSync();
      await expectLater(sync.push(_glance()), completes);
    });

    test('the native side can ask for the glance as it is now', () async {
      final GlanceSync sync = GlanceSync()..current = () => _glance();
      ByteData? reply;
      await messenger.handlePlatformMessage(
        'com.orb.guard/glance',
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('refresh')),
        (data) => reply = data,
      );
      final Object? map = const StandardMethodCodec().decodeEnvelope(reply!);
      expect((map as Map)['title'], 'All clear');
      sync.dispose();
    });

    test('a check asked for from outside the app reaches the app', () async {
      int asked = 0;
      final GlanceSync sync = GlanceSync()..onCheckNow = () => asked++;
      await messenger.handlePlatformMessage(
        'com.orb.guard/glance',
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('checkNow')),
        (_) {},
      );
      expect(asked, 1);
      sync.dispose();
    });
  });
}
