import 'dart:math' as math;

import '../data/blessing.dart';
import '../strings.dart';
import 'astro.dart';

/// Where each blessing's light sits, and the curve the lights are strung on.
///
/// This is the one place the placement rule lives. The rule in use is
/// [RingPlacement] (Noah, 2026-11-15); [OverheadPlacement] was the prototype's
/// and is kept to compare against. Swapping one in means adding a class here
/// and nothing else.
abstract class Placement {
  const Placement();

  /// Sets [Blessing.ra], [Blessing.dec] and [Blessing.v] on every blessing.
  /// Pass every blessing in the sky at once: a rule may place each one by the
  /// others. [now] is the end of the timeline (default: the clock). [begins]: when the ring itself
  /// begins (a family member's birth, people/person.dart), if before the first blessing.
  void apply(List<Blessing> blessings, {DateTime? now, DateTime? begins});

  /// The faint line drawn through the lights.
  List<Vec3> line(List<Blessing> blessings);

  /// The sentence at the end of a blessing's page saying where its light is.
  String note(Blessing b);
}

class OverheadPlacement extends Placement {
  const OverheadPlacement();

  @override
  void apply(List<Blessing> blessings, {DateTime? now, DateTime? begins}) {
    for (final b in blessings) {
      final z = zenith(b.utc, b.place);
      b.ra = z.ra;
      b.dec = z.dec;
      b.v = Vec3.radec(z.ra, z.dec);
    }
  }

  /// The circle of sky that passes overhead at the latitude of the first blessing.
  @override
  List<Vec3> line(List<Blessing> blessings) {
    if (blessings.isEmpty) return const [];
    final dec = blessings.first.place.lat * deg;
    const seg = 720;
    return [for (var i = 0; i <= seg; i++) Vec3.radec(i / seg * tau, dec)];
  }

  /// "... straight overhead at 9:40 in the morning, behind the daylight." The
  /// sun is taken to be up from 7 in the morning until 7 in the evening, local
  /// clock time; a simple test, as the prototype's.
  @override
  String note(Blessing b) {
    final h = b.local.hour;
    return Strings.overheadNote(b.local, daylight: h >= 7 && h < 19);
  }
}

/// The timeline bent round one ring of sky.
///
/// The ring is the circle at the declination equal to the latitude of the
/// first blessing's place. It starts at the right ascension that was straight
/// overhead at the first blessing's place and minute, and runs so that later
/// blessings sit to the right on screen (decreasing right ascension; the sky
/// is seen from inside). Angle along the ring is proportional to time since
/// the first blessing: [perYear] a year until the span from the first
/// blessing to now would pass [full], then that whole span is fitted into
/// [full], so the lights bunch as the years pass and slide a little with each
/// one added. Neighbours are kept at least [gap] apart, later ones pushed on.
class RingPlacement extends Placement {
  const RingPlacement();

  /// Degrees of right ascension.
  static const double perYear = 24, full = 300, gap = .5;

  static const double _year = 365.2425 * 864e5; // milliseconds

  /// Degrees along the ring for each blessing (oldest first, as [sorted]),
  /// and for [now]: the end of the line, where a new recording goes.
  /// A ring that [begins] before its first blessing (a birth) starts there instead.
  static ({List<double> at, double end}) angles(List<Blessing> sorted, DateTime now, {DateTime? begins}) {
    if (sorted.isEmpty) return (at: const [], end: 0);
    final t0 = _start(sorted.first, begins).millisecondsSinceEpoch;
    double years(DateTime t) => (t.millisecondsSinceEpoch - t0) / _year;
    final span = math.max(years(now), years(sorted.last.utc));
    final scale = span * perYear <= full ? perYear : full / span;
    final at = <double>[];
    for (final b in sorted) {
      var a = math.max(0.0, years(b.utc)) * scale;
      if (at.isNotEmpty) a = math.max(a, at.last + gap);
      at.add(a);
    }
    var end = math.max(span * scale, at.last);
    // only with hundreds given within days could the gaps push past the ring's end
    if (end > full) {
      final k = full / end;
      for (var i = 0; i < at.length; i++) {
        at[i] *= k;
      }
      end = full;
    }
    return (at: at, end: end);
  }

  @override
  void apply(List<Blessing> blessings, {DateTime? now, DateTime? begins}) {
    if (blessings.isEmpty) return;
    final sorted = [...blessings]..sort(_byTime);
    final first = sorted.first;
    final start = zenith(_start(first, begins), first.place).ra;
    final dec = first.place.lat * deg;
    final a = angles(sorted, now ?? DateTime.now(), begins: begins).at;
    for (var i = 0; i < sorted.length; i++) {
      final b = sorted[i];
      b.ra = ((start - a[i] * deg) % tau + tau) % tau;
      b.dec = dec;
      b.v = Vec3.radec(b.ra, b.dec);
    }
  }

  /// The ring's start: [begins] when it is earlier than the first blessing.
  static DateTime _start(Blessing first, DateTime? begins) =>
      begins != null && begins.toUtc().isBefore(first.utc) ? begins.toUtc() : first.utc;

  static int _byTime(Blessing a, Blessing b) {
    final c = a.utc.compareTo(b.utc);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// The whole circle of sky the ring lies on.
  @override
  List<Vec3> line(List<Blessing> blessings) => const OverheadPlacement().line(blessings);

  @override
  String note(Blessing b) => Strings.ringNote;
}
