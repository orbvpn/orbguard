// The ring's arithmetic: where the body runs, where it opens, how a check is
// cut into segments. Angles are degrees clockwise from twelve o'clock.
//
// Expected values are worked by hand from the ring's proportions on a 200 unit
// box (outer 96, inner 52): the centre line sits at 74, the band is 44 thick,
// so a round end reaches 22 / 74 rad = 17.0339 degrees past its arc, and a gap
// that shows 15 degrees of daylight is cut 7.5 + 17.0339 = 24.5339 degrees
// either side of its centre.

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/widgets/home/orb_ring.dart';

const _half = 24.5339;

void main() {
  group('ring body', () {
    test('with no gap it is one whole turn', () {
      final arcs = OrbGeometry.body(const []);

      expect(arcs, hasLength(1));
      expect(arcs.single.sweep, 360);
    });

    test('one gap leaves one arc that starts and ends either side of it', () {
      final arcs = OrbGeometry.body(const [150]);

      expect(arcs, hasLength(1));
      expect(arcs.single.start, closeTo(150 + _half, 1e-3));
      expect(arcs.single.sweep, closeTo(360 - 2 * _half, 1e-3));
    });

    test('two gaps leave two arcs between them', () {
      final arcs = OrbGeometry.body(const [150, 330]);

      expect(arcs, hasLength(2));
      expect(arcs[0].start, closeTo(150 + _half, 1e-3));
      expect(arcs[0].sweep, closeTo(180 - 2 * _half, 1e-3));
      expect(arcs[1].start, closeTo(330 + _half, 1e-3));
      expect(arcs[1].sweep, closeTo(180 - 2 * _half, 1e-3));
    });

    test('the order the gaps arrive in does not change the drawing', () {
      final sorted = OrbGeometry.body(const [30, 150, 330]);
      final shuffled = OrbGeometry.body(const [330, 30, 150]);

      expect(shuffled, sorted);
    });

    test('angles off the dial are read back onto it, and repeats count once',
        () {
      expect(OrbGeometry.body(const [-30]), OrbGeometry.body(const [330]));
      expect(OrbGeometry.body(const [510]), OrbGeometry.body(const [150]));
      expect(OrbGeometry.body(const [150, 150]), OrbGeometry.body(const [150]));
    });

    test('a gap that is half closed is cut half as wide', () {
      final arcs = OrbGeometry.body(const [150], openness: 0.5);

      expect(arcs.single.start, closeTo(150 + _half / 2, 1e-3));
      expect(arcs.single.sweep, closeTo(360 - _half, 1e-3));
    });

    test('a gap that stays open keeps its full width while another closes', () {
      final arcs =
          OrbGeometry.body(const [330], openness: 0.5, held: const [150]);

      expect(arcs, hasLength(2));
      expect(arcs[0].start, closeTo(150 + _half, 1e-3));
      expect(arcs[0].sweep, closeTo(180 - _half - _half / 2, 1e-3));
      expect(arcs[1].start, closeTo(330 + _half / 2, 1e-3));
    });

    test('a held gap is still there once the closing one has gone', () {
      expect(OrbGeometry.body(const [330], openness: 0, held: const [150]),
          OrbGeometry.body(const [150]));
    });

    test('a gap that has finished closing leaves the ring whole', () {
      final arcs = OrbGeometry.body(const [150, 330], openness: 0);

      expect(arcs, hasLength(1));
      expect(arcs.single.sweep, 360);
    });
  });

  group('check segments', () {
    test('five checks cut the ring into five equal arcs with 6 degrees between',
        () {
      final arcs = OrbGeometry.segments(5);

      expect(arcs, hasLength(5));
      expect([for (final a in arcs) a.start], [3, 75, 147, 219, 291]);
      expect(arcs, everyElement(predicate<OrbArc>((a) => a.sweep == 66)));
    });

    test('more than seven checks sit closer, 4.4 degrees apart', () {
      final arcs = OrbGeometry.segments(11);

      expect(arcs, hasLength(11));
      expect(arcs.first.start, closeTo(2.2, 1e-9));
      expect(arcs.first.sweep, closeTo(360 / 11 - 4.4, 1e-9));
    });

    test('no checks, no segments', () {
      expect(OrbGeometry.segments(0), isEmpty);
    });
  });
}
