// What a home-screen widget, the lock screen and the menu bar show of Home.
//
// A glance is worked out from the HomeBrief that Home draws, so it can never
// say more than Home does. The native side draws it as it is and adds only
// the time of the check, in the reader's own clock format.
//
// A widget stays on screen for days without the app being opened, so a
// glance also says when it stops speaking for today: from [Glance.staleAt]
// the score is no longer shown, and an all clear gives way to
// [Glance.staleTitle]. That is the moment Home itself would stop saying it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'home_brief.dart';
import 'home_today.dart';

/// Two wire forms say the same thing. Compared as their JSON text, so lists
/// and the rows inside them are compared by what they hold.
bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
    jsonEncode(a) == jsonEncode(b);

/// How the glance draws the ring, the way Home's hero does.
enum GlanceRing {
  /// Never checked: a ring of dots.
  fresh,

  /// Checked: the band, open toward each gap.
  open,

  /// Checked, and nothing is on watch: the band without its colour.
  still,
}

@immutable
class Glance {
  const Glance._({
    required this.moment,
    required this.title,
    required this.line,
    required this.score,
    required this.gaps,
    required this.ring,
    required this.checkedAt,
    required this.staleAt,
    required this.staleTitle,
    required this.staleLine,
    required this.headline,
    required this.proof,
    required this.events,
  });

  /// [lastScanAt] is when the check [brief] speaks for ran, if one has.
  /// [today] is the Today card's record, for a glance with room for rows.
  factory Glance.from({
    required HomeBrief brief,
    required DateTime? lastScanAt,
    HomeToday? today,
  }) {
    final DateTime? at = brief.checked ? lastScanAt : null;
    final String title = switch (brief.moment) {
      HomeMoment.fresh => 'Not checked yet',
      HomeMoment.clear => brief.allClear ? 'All clear' : _words(brief.headline),
      HomeMoment.gap => _words(brief.headline),
    };
    final String? line = switch (brief.moment) {
      HomeMoment.fresh => brief.proof,
      HomeMoment.clear => null,
      HomeMoment.gap => brief.gaps.first.title,
    };
    final bool clear = brief.moment == HomeMoment.clear;
    return Glance._(
      moment: brief.moment,
      title: title,
      line: line,
      score: brief.score,
      gaps: [for (final HomeGap gap in brief.gaps) gap.shield.angle],
      ring: !brief.checked
          ? GlanceRing.fresh
          : brief.still
              ? GlanceRing.still
              : GlanceRing.open,
      checkedAt: at,
      staleAt: at?.add(_speaksFor),
      staleTitle: clear && at != null ? 'Nothing found last time' : null,
      staleLine: clear && at != null ? 'Time for a fresh check' : null,
      headline: brief.headline,
      proof: brief.proof,
      events: [
        for (final HomeEvent e
            in (today?.events ?? const <HomeEvent>[]).take(3))
          GlanceEvent(kind: e.kind, text: e.text, at: e.at),
      ],
    );
  }

  /// A check stops earning its recency points, and Home stops calling it
  /// all clear, once more than seven whole days have passed.
  static const Duration _speaksFor = Duration(days: 8);

  final HomeMoment moment;

  /// The few words a small widget has room for.
  final String title;

  /// One line under them, or null.
  final String? line;

  /// 0 to 1000, or null before the first check.
  final int? score;

  /// Where the ring is open, in degrees clockwise from twelve o'clock.
  final List<double> gaps;
  final GlanceRing ring;

  /// When the check this speaks for ran.
  final DateTime? checkedAt;

  /// From this moment the score is not shown, and [staleTitle] and
  /// [staleLine], when set, take the place of [title] and [line].
  final DateTime? staleAt;
  final String? staleTitle;
  final String? staleLine;

  /// Home's own headline and line of proof, for a glance with room for them:
  /// the menu bar's popover. Asked for afresh each time it opens.
  final String headline;
  final String? proof;

  /// What the Today card records, newest first, three at most.
  final List<GlanceEvent> events;

  /// What the native side reads.
  Map<String, Object?> toMap() => {
        'v': 1,
        'moment': moment.name,
        'title': title,
        'line': line,
        'score': score,
        'gaps': gaps,
        'ring': ring.name,
        'checkedAt': checkedAt?.millisecondsSinceEpoch,
        'staleAt': staleAt?.millisecondsSinceEpoch,
        'staleTitle': staleTitle,
        'staleLine': staleLine,
        'headline': headline,
        'proof': proof,
        'events': [for (final GlanceEvent e in events) e.toMap()],
      };

  /// A headline as a widget title: the same words, without the full stop.
  static String _words(String headline) => headline.endsWith('.')
      ? headline.substring(0, headline.length - 1)
      : headline;

  @override
  bool operator ==(Object other) =>
      other is Glance && _same(other.toMap(), toMap());

  @override
  int get hashCode => Object.hashAll(
      toMap().values.map((v) => v is List ? Object.hashAll(v) : v));
}

/// One row of the Today card.
@immutable
class GlanceEvent {
  const GlanceEvent({required this.kind, required this.text, this.at});

  final HomeEventKind kind;
  final String text;

  /// When it happened, or null for a count that has no single moment. The
  /// native side shows a time from today as a clock time, and an older one
  /// as a date.
  final DateTime? at;

  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'text': text,
        'at': at?.millisecondsSinceEpoch,
      };
}

/// Tells the native side what to show, and hears what it asks for.
///
/// On a device with nothing to tell (no widget, no menu bar item, or a test)
/// it is quiet.
class GlanceSync {
  GlanceSync({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(name) {
    _channel.setMethodCallHandler(_heard);
  }

  static const String name = 'com.orb.guard/glance';

  final MethodChannel _channel;
  Map<String, Object?>? _sent;

  /// Someone asked for a check from outside the app: the menu bar item's
  /// "Check now".
  VoidCallback? onCheckNow;

  /// The glance as it is now. The menu bar asks for it each time its
  /// popover opens, so the times in it are never old.
  Glance? Function()? current;

  Future<void> push(Glance glance) async {
    final Map<String, Object?> map = glance.toMap();
    final Map<String, Object?>? sent = _sent;
    if (sent != null && _same(sent, map)) return;
    _sent = map;
    try {
      await _channel.invokeMethod<void>('update', map);
    } on MissingPluginException {
      // Nothing on this device shows a glance.
    } on PlatformException catch (e) {
      debugPrint('[OrbGuard] The glance was not taken: ${e.message}');
      _sent = null;
    }
  }

  Future<Object?> _heard(MethodCall call) async {
    switch (call.method) {
      case 'checkNow':
        onCheckNow?.call();
      case 'refresh':
        final Map<String, Object?>? map = current?.call()?.toMap();
        if (map != null) _sent = map;
        return map;
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    onCheckNow = null;
    current = null;
  }
}
