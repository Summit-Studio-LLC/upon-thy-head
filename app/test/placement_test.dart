// The ring rule (lib/sky/placement.dart).
//
//   flutter test test/placement_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/placement.dart';

void main() {
  const ring = RingPlacement();
  final t0 = DateTime.utc(2020, 1, 1, 12);
  const year = Duration(microseconds: 365242500 * 86400); // 365.2425 days

  Blessing at(String id, DateTime utc) =>
      Blessing(id: id, title: id, from: '', utc: utc, utcOffset: Duration.zero, place: samplePlace);

  /// Degrees along the ring from the start, later positive (right ascension decreases).
  double along(Blessing first, Blessing b) {
    final start = zenith(first.utc, first.place).ra;
    final d = ((start - b.ra) % tau + tau) % tau;
    return d / deg;
  }

  test('none: nothing happens, and the line is empty', () {
    ring.apply([], now: t0);
    expect(ring.line([]), isEmpty);
    expect(RingPlacement.angles([], t0).at, isEmpty);
  });

  test('one: at the start of the ring, on the circle of its latitude', () {
    final b = at('a', t0);
    ring.apply([b], now: t0.add(const Duration(days: 30)));
    expect(b.ra, closeTo(zenith(t0, samplePlace).ra, 1e-9));
    expect(b.dec, closeTo(samplePlace.lat * deg, 1e-12));
    expect(b.v.z, closeTo(Vec3.radec(b.ra, b.dec).z, 1e-12));
  });

  test('order follows time, whatever order they are passed in', () {
    final list = [for (var i = 0; i < 12; i++) at('b$i', t0.add(Duration(days: 37 * i + (i * i) % 5)))];
    final shuffled = [...list.reversed.skip(3), ...list.reversed.take(3)];
    ring.apply(shuffled, now: t0.add(const Duration(days: 600)));
    for (var i = 1; i < list.length; i++) {
      expect(along(list.first, list[i]), greaterThan(along(list.first, list[i - 1])), reason: 'b$i');
    }
  });

  test('before the ring is full: a fixed number of degrees a year, and nothing moves as one is added', () {
    final a = at('a', t0), b = at('b', t0.add(year)), c = at('c', t0.add(year * 2.5));
    final now = t0.add(year * 3);
    ring.apply([a, b, c], now: now);
    expect(along(a, b), closeTo(RingPlacement.perYear, 1e-6));
    expect(along(a, c), closeTo(RingPlacement.perYear * 2.5, 1e-6));
    final raB = b.ra;
    final d = at('d', now);
    ring.apply([a, b, c, d], now: now.add(const Duration(days: 2)));
    expect(b.ra, closeTo(raB, 1e-12), reason: 'a light moved while the ring was not full');
    expect(along(a, d), closeTo(RingPlacement.perYear * 3, 1e-6), reason: 'the newest sits at the end of the line');
    expect(RingPlacement.angles([a, b, c, d], now).end, closeTo(RingPlacement.perYear * 3, 1e-6));
  });

  test('after the ring is full: the span from the first to now fitted into the full span', () {
    const fy = RingPlacement.full / RingPlacement.perYear; // years until the ring is full
    final a = at('a', t0), b = at('b', t0.add(year * (fy * .5))), c = at('c', t0.add(year * (fy * .9)));
    final now = t0.add(year * (fy * 1.25));
    ring.apply([a, b, c], now: now);
    expect(along(a, b), closeTo(RingPlacement.full * .5 / 1.25, 1e-6));
    expect(along(a, c), closeTo(RingPlacement.full * .9 / 1.25, 1e-6));
    expect(RingPlacement.angles([a, b, c], now).end, closeTo(RingPlacement.full, 1e-6));
    // a year on, everything has slid a little closer to the start
    ring.apply([a, b, c], now: now.add(year));
    expect(along(a, b), closeTo(RingPlacement.full * (fy * .5) / (fy * 1.25 + 1), 1e-6));
    // the point of change: exactly full/perYear years
    final edge = t0.add(year * (RingPlacement.full / RingPlacement.perYear));
    expect(RingPlacement.angles([a], edge).end, closeTo(RingPlacement.full, 1e-6));
  });

  test('never on top of each other: at least half a degree, later ones pushed along', () {
    final list = [for (var i = 0; i < 6; i++) at('s$i', t0.add(Duration(minutes: i)))];
    final late = at('late', t0.add(const Duration(days: 90)));
    ring.apply([...list, late], now: t0.add(const Duration(days: 100)));
    for (var i = 1; i < list.length; i++) {
      expect(along(list.first, list[i]) - along(list.first, list[i - 1]), closeTo(RingPlacement.gap, 1e-6));
    }
    expect(along(list.first, late), closeTo(90 / 365.2425 * RingPlacement.perYear, 1e-6), reason: 'one given well after was not pushed');
    // the same minute twice still gets two places
    final x = at('x', t0), y = at('y', t0);
    ring.apply([x, y], now: t0.add(year));
    expect((x.ra - y.ra).abs() / deg, closeTo(RingPlacement.gap, 1e-6));
  });

  test('hundreds within days never wrap past the ring', () {
    final list = [for (var i = 0; i < 900; i++) at('m$i', t0.add(Duration(minutes: i)))];
    final r = RingPlacement.angles(list, t0.add(const Duration(days: 1)));
    expect(r.at.last, lessThanOrEqualTo(RingPlacement.full + 1e-9));
    expect(r.end, lessThanOrEqualTo(RingPlacement.full + 1e-9));
  });

  test('the note', () {
    expect(ring.note(at('a', t0)), 'Its light keeps its place in time on the ring of sky overhead.');
  });

  test('the dense test seed: 120 over fourteen years ending now, uneven, a full ring', () {
    final now = DateTime.utc(2026, 11, 15);
    final list = denseBlessings(now: now);
    expect(list.length, 120);
    expect(list.first.utc.year, 2013);
    expect(list.last.utc.isBefore(now), isTrue);
    final r = RingPlacement.angles(list, now);
    final gaps = [for (var i = 1; i < r.at.length; i++) r.at[i] - r.at[i - 1]]..sort();
    expect(r.end, closeTo(RingPlacement.full, 1e-6));
    expect(gaps.first, greaterThanOrEqualTo(RingPlacement.gap - 1e-9));
    // uneven: some neighbours at the minimum gap, some far apart
    expect(gaps.last, greaterThan(10 * gaps[gaps.length ~/ 2]));
    // ignore: avoid_print
    print('dense: gaps min ${gaps.first.toStringAsFixed(2)}, median ${gaps[gaps.length ~/ 2].toStringAsFixed(2)}, '
        'max ${gaps.last.toStringAsFixed(1)} deg; at the minimum ${gaps.where((g) => g < RingPlacement.gap + 1e-6).length}');
  });
}
