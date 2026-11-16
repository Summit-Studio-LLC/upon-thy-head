import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import 'astro.dart';
import 'sky_engine.dart';

/// One stretch of a constellation's figure, from star [a] to star [b], lying
/// between [s0] and [s1] along the whole figure (radians of arc).
class Segment {
  Segment(this.a, this.b, this.s0, this.s1);
  final Vec3 a, b;
  final double s0, s1;
}

/// A constellation's stick figure, as one path walked star to star.
class Figure {
  Figure._(this.id, this.segs, this.pts, this.len);
  final String id;
  final List<Segment> segs;
  final List<Vec3> pts;
  final double len;
}

/// The constellation figures. Source: assets/sky/constellations.json,
/// `[[id, [[ra, dec, ra, dec, ...], ...]], ...]`, degrees J2000.
class Figures {
  Figures._(this.all);
  final List<Figure> all;

  static Future<Figures> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/sky/constellations.json')) as List;
    final out = <Figure>[];
    for (final c in raw) {
      final segs = <Segment>[], pts = <Vec3>[];
      var len = 0.0;
      for (final l in (c[1] as List)) {
        final line = (l as List).cast<num>();
        Vec3? prev;
        for (var i = 0; i + 1 < line.length; i += 2) {
          final v = Vec3.radec(line[i] * deg, line[i + 1] * deg);
          pts.add(v);
          if (prev != null) {
            final a = math.acos((prev.x * v.x + prev.y * v.y + prev.z * v.z).clamp(-1.0, 1.0));
            if (a > 1e-6) {
              segs.add(Segment(prev, v, len, len + a));
              len += a;
            }
          }
          prev = v;
        }
      }
      out.add(Figure._(c[0] as String, segs, pts, len));
    }
    return Figures._(out);
  }
}

/// A figure's turn in the round: it starts drawing at [t], takes [d] seconds to
/// draw, rests [h] seconds, and takes [d] seconds to be taken up again.
class FigurePlan {
  FigurePlan(this.f, this.t, this.d, this.h);
  final Figure f;
  final double t, d, h;
}

/// What is drawn while a recording listens: the constellations around the
/// look point, drawn slowly star to star, resting, and taken up again the way
/// they came. A port of the prototype's pickFigs and drawFigs.
class FigureShow {
  FigureShow(this.figures);
  final Figures figures;

  List<FigurePlan> plans = const [];

  /// Seconds in one round, and the engine clock when the show began.
  double period = 60, t0 = 0;

  /// Eased strength of the whole show, 0 to 1.
  double a = 0;
  bool on = false;

  /// Choose the figures that will be on screen with the camera at [ra], [dec]
  /// in [view], nearest the look point first, and start the round now.
  void start(SkyEngine e, double ra, double dec, SkyView view, Size size) {
    final p = Projected();
    final w = size.width, h = size.height;
    final oy = (1 - (view.cy * .5 + .5)) * h;
    final picked = <({Figure f, double d})>[];
    e.withCamera(ra, dec, view.fov, view.cy, size, () {
      for (final f in figures.all) {
        if (f.len == 0) continue;
        var n = 0;
        var sx = 0.0, sy = 0.0;
        for (final v in f.pts) {
          e.project(v, p);
          // the prototype's band, 70 to 690 of 844, kept clear of the words above and the ring below
          if (p.z > .1 && p.x > -10 && p.x < w + 10 && p.y > 70 && p.y < h - 154) {
            n++;
            sx += p.x;
            sy += p.y;
          }
        }
        if (n >= 2 && n >= f.pts.length * .4) {
          picked.add((f: f, d: math.sqrt(math.pow(sx / n - w / 2, 2) + math.pow(sy / n - oy, 2))));
        }
      }
    });
    picked.sort((a, b) => a.d.compareTo(b.d));
    // one after another, a few seconds apart; each rests for most of the round,
    // so the sky is never empty and never all moving at once
    period = math.max(48, picked.length * 3.4 + 14);
    plans = [
      for (var k = 0; k < picked.length; k++)
        () {
          final d = (picked[k].f.len / (5 * deg)).clamp(6.0, 15.0);
          return FigurePlan(picked[k].f, k * 3.4, d, math.max(8, period - 2 * d - 4));
        }(),
    ];
    t0 = e.clock;
    on = true;
  }

  void stop() => on = false;

  /// Ease the strength toward on or off: in slowly, out quickly.
  void step(double dt) {
    final goal = on ? 1.0 : 0.0;
    a += (goal - a) * (1 - math.exp(-dt * (on ? .9 : 3.5)));
  }

  final Projected _a = Projected(), _b = Projected();

  /// Draw with the camera as it is now. [color] is the palette's light.
  void paint(Canvas canvas, SkyEngine e, Color color, {required bool still}) {
    if (a < .004) return;
    final t = e.clock - t0;
    const gap = 5.0;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..isAntiAlias = true
      ..color = color.withValues(alpha: .4 * a);
    final dot = Paint()
      ..blendMode = BlendMode.plus
      ..color = color.withValues(alpha: .75 * a);
    for (final g in plans) {
      if (t < g.t && !still) continue;
      final f = g.f;
      final tau = still ? g.d + 1 : ((t - g.t) % period + period) % period;
      final head = (tau / g.d).clamp(0.0, 1.0) * f.len, tail = ((tau - g.d - g.h) / g.d).clamp(0.0, 1.0) * f.len;
      if (head <= tail) continue;
      Offset? hp;
      final dots = <int, Offset>{};
      final path = Path();
      for (final s in f.segs) {
        if (s.s1 <= tail || s.s0 >= head) continue;
        e.project(s.a, _a);
        e.project(s.b, _b);
        if (_a.z < .1 || _b.z < .1) continue;
        final dx = _b.x - _a.x, dy = _b.y - _a.y, l = math.sqrt(dx * dx + dy * dy);
        if (l < 1) continue;
        final u0 = (math.max(tail, s.s0) - s.s0) / (s.s1 - s.s0), u1 = (math.min(head, s.s1) - s.s0) / (s.s1 - s.s0);
        final p0 = math.max(u0 * l, gap), p1 = math.min(u1 * l, l - gap);
        if (p1 > p0) {
          path
            ..moveTo(_a.x + dx * p0 / l, _a.y + dy * p0 / l)
            ..lineTo(_a.x + dx * p1 / l, _a.y + dy * p1 / l);
        }
        if (u1 < 1) hp = Offset(_a.x + dx * u1, _a.y + dy * u1);
        if (u0 <= 0) dots[_a.x.round() * 100003 + _a.y.round()] = Offset(_a.x, _a.y);
        if (u1 >= 1) dots[_b.x.round() * 100003 + _b.y.round()] = Offset(_b.x, _b.y);
      }
      canvas.drawPath(path, line);
      for (final d in dots.values) {
        canvas.drawCircle(d, 1.5, dot);
      }
      if (hp != null && !still) {
        canvas.drawCircle(
          hp,
          9,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = Gradient.radial(hp, 9, [color.withValues(alpha: .55 * a), color.withValues(alpha: 0)]),
        );
      }
    }
  }
}
