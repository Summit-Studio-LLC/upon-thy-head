import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'astro.dart';
import 'catalogue.dart';
import 'figures.dart';
import 'sky_engine.dart';

/// Everything the sky needs that is loaded once.
class SkyAssets {
  SkyAssets({
    required this.stars,
    required this.atlas,
    required this.skyProgram,
    required this.lightProgram,
    required this.milkyWay,
    required this.milkyWaySoft,
    required this.figures,
  });

  final StarCatalogue stars;
  final StarAtlas atlas;
  final ui.FragmentProgram skyProgram, lightProgram;
  final ui.Image milkyWay;

  /// A quarter-size copy averaged in linear light, for zoomed-in views (see sky.frag).
  final ui.Image milkyWaySoft;
  final Figures figures;
}

/// Draws the night: Milky Way, stars, the line the lights are strung on, the lights, and their dates.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.engine,
    required this.assets,
    required this.palette,
    required this.dpr,
    required this.showLabels,
    required this.line,
    required super.repaint,
    this.onStats,
  }) : _sky = assets.skyProgram.fragmentShader();

  final SkyEngine engine;
  final SkyAssets assets;
  final Palette palette;
  final double dpr;
  final bool showLabels;

  /// The curve the lights are strung on, as directions on the sphere.
  List<Vec3> line;

  /// Reports stars drawn and microseconds spent filling the star buffers.
  final void Function(int stars, int micros)? onStats;

  /// Figures are hidden above this many points from the top (the title and
  /// Discard), and below this many from the bottom (the ring and its hint).
  static const double figureTop = 112, figureBottom = 150;

  /// Blend in the soft Milky Way when zoomed in. Off only to compare against the old look.
  static bool softMilkyWay = true;

  /// Points between neighbouring lights below which they are dimmed.
  static const double crowd = 22;

  /// Fade the figures under the words and the ring. Off only to show what the fade hides.
  static bool fadeFigures = true;

  /// For tests: each label drawn in the last frame (dates and star names), with its strength.
  static final List<({Rect box, double alpha, bool date})> debugLabels = [];

  final ui.FragmentShader _sky;
  final List<ui.FragmentShader> _lightShaders = [];

  // One sprite per star at most, plus a second core and a halo for the bright ones.
  static const _cap = 140000;
  final Float32List _xf = Float32List(_cap * 4);
  final Float32List _src = Float32List(_cap * 4);
  final Int32List _col = Int32List(_cap);
  final Float32List _linePts = Float32List(4096);
  final Projected _p = Projected();
  final Map<String, TextPainter> _text = {};

  final Paint _starPaint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final e = engine;
    e.basis(size);
    final w = size.width, h = size.height;

    // ---- the night itself ----
    final orbU = e.orbUniforms();
    var i = 0;
    void f(double v) => _sky.setFloat(i++, v);
    // the order of shaders/sky.frag's packed uniforms (uP0 to uP5, then the colours)
    // the soft copy fades in from just past the home framing (fov 90) to about fov 46
    final mag = math.tan(90 * deg / 4) / math.tan(e.fov * deg / 4);
    final u = ((mag - 1.15) / (2.2 - 1.15)).clamp(0.0, 1.0);
    for (final v in [
      w, h, dpr, e.cy, // uP0
      e.fx, e.fy, e.fz, e.exp, // uP1
      e.rx, e.ry, e.rz, 1.0, // uP2
      e.ux, e.uy, e.uz, softMilkyWay ? u * u * (3 - 2 * u) : 0.0, // uP3
      e.tx, e.ty, assets.milkyWay.width.toDouble(), assets.milkyWay.height.toDouble(), // uP4
      assets.milkyWaySoft.width.toDouble(), assets.milkyWaySoft.height.toDouble(), 0.0, 0.0, // uP5
      0.0, e.cy, orbU.radius, orbU.strength, // uOrb
    ]) {
      f(v);
    }
    for (final c in [palette.sky, palette.tint, ...palette.orb]) {
      f(c[0]);
      f(c[1]);
      f(c[2]);
    }
    _sky.setImageSampler(0, assets.milkyWay); // nearest; the shader filters (see sky.frag)
    _sky.setImageSampler(1, assets.milkyWaySoft);
    canvas.drawRect(Offset.zero & size, Paint()..shader = _sky);

    // ---- the line the lights are strung on ----
    if (math.max(e.names, e.ring) > .02 && line.isNotEmpty) _paintLine(canvas, size);

    // ---- stars ----
    final sw = Stopwatch()..start();
    final n = _fillStars(w, h);
    sw.stop();
    if (n > 0) {
      canvas.drawRawAtlas(
        assets.atlas.image,
        Float32List.sublistView(_xf, 0, n * 4),
        Float32List.sublistView(_src, 0, n * 4),
        Int32List.sublistView(_col, 0, n),
        BlendMode.modulate,
        null,
        _starPaint,
      );
    }
    onStats?.call(n, sw.elapsedMicroseconds);

    // ---- the blessings ----
    const rad = 110.0;
    final l = palette.lights;
    for (var b = 0; b < e.blessings.length; b++) {
      e.project(e.shown[b], e.points[b]);
    }
    for (var b = 0; b < e.blessings.length; b++) {
      final p = e.points[b];
      var a = e.lights * (1 - e.solo * (1 - e.weights[b]));
      // lights bunched closer than [crowd] points are dimmed (all but the one in
      // focus), so a crowded stretch reads as a string of points, not one smear
      if (e.blessings.length > 1) {
        var near = double.infinity;
        for (final o in [b - 1, b + 1]) {
          if (o < 0 || o >= e.blessings.length) continue;
          final q = e.points[o];
          if (q.z > 0) near = math.min(near, (Offset(q.x, q.y) - Offset(p.x, p.y)).distance);
        }
        final c = (near / crowd).clamp(0.0, 1.0), wgt = e.weights[b];
        a *= wgt + (1 - wgt) * (.4 + .6 * c);
      }
      if (p.z < -.3 || a < .01 || p.x < -rad || p.x > w + rad || p.y < -rad || p.y > h + rad) continue;
      while (_lightShaders.length <= b) {
        _lightShaders.add(assets.lightProgram.fragmentShader());
      }
      final s = _lightShaders[b];
      var j = 0;
      void g(double v) => s.setFloat(j++, v);
      g(p.x);
      g(p.y);
      g(rad);
      g(e.weights[b]);
      g(a);
      for (final c in l) {
        g(c[0]);
        g(c[1]);
        g(c[2]);
      }
      canvas.drawRect(
        Rect.fromCircle(center: Offset(p.x, p.y), radius: rad),
        Paint()
          ..shader = s
          ..blendMode = BlendMode.plus,
      );
    }

    // ---- while a recording listens: the constellations ----
    final show = e.show;
    if (show != null && show.a >= .004) {
      // Drawn into a layer and faded out under the words at the top and the
      // ring and its hint at the bottom, so no line or star of a figure shows
      // through the controls (as the prototype's scrims and the ring's disc did).
      final r = Offset.zero & size;
      canvas.saveLayer(r, Paint()..blendMode = BlendMode.plus);
      show.paint(canvas, e, palette.light, still: e.reduceMotion);
      if (fadeFigures) {
        canvas.drawRect(
          r,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, h),
              const [Color(0x00000000), Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000), Color(0x00000000)],
              [0, figureTop / h, (figureTop + 60) / h, (h - figureBottom - 50) / h, (h - figureBottom) / h, 1],
            ),
        );
      }
      canvas.restore();
    }

    if (showLabels) {
      _paintLabels(canvas, size);
    } else {
      _labelsFading = false;
    }
  }

  /// Projects every star that can be seen and writes one or more sprites for it.
  /// Returns the number of sprites.
  int _fillStars(double w, double h) {
    final e = engine, c = assets.stars;
    final xyz = c.xyz, radL = c.rad, alphaL = c.alpha, haloL = c.halo, twF = c.twFreq, twP = c.twPhase, rgb = c.rgb;
    final fx = e.fx, fy = e.fy, fz = e.fz, rx = e.rx, ry = e.ry, ux = e.ux, uy = e.uy, uz = e.uz;
    final kx = .5 * w / e.tx, ky = .5 * h / e.ty, cx = .5 * w, cyPx = (1 - (e.cy * .5 + .5)) * h;
    final zs = math.pow(80 / e.fov, .35) * dpr, st = e.st, clock = e.clock;
    final twinkle = e.reduceMotion ? 0.0 : .14;
    final xf = _xf, src = _src, col = _col;
    const minPx = .82; // no star is drawn smaller than this many device pixels; it dims instead
    var n = 0;
    final count = c.count;
    for (var i = 0; i < count; i++) {
      var a = alphaL[i] * st;
      var sd = radL[i] * zs;
      if (sd < minPx) {
        a *= sd * sd / (minPx * minPx);
        sd = minPx;
      }
      if (a * 1.14 < .006) break; // brightest first: everything after this is fainter still
      final o = i * 3;
      final vx = xyz[o], vy = xyz[o + 1], vz = xyz[o + 2];
      final z = vx * fx + vy * fy + vz * fz;
      if (z < -.6) continue;
      final k = 2 / (1.0001 + z);
      final x = cx + (vx * rx + vy * ry) * k * kx;
      final sigma = sd / dpr; // logical pixels
      final hk = haloL[i];
      final reach = sigma * (hk > 0 ? 13 : 3.4);
      if (x < -reach || x > w + reach) continue;
      final y = cyPx - (vx * ux + vy * uy + vz * uz) * k * ky;
      if (y < -reach || y > h + reach) continue;
      if (twinkle != 0) a *= 1 + twinkle * math.sin(clock * twF[i] + twP[i]);
      if (a < .006) continue;
      if (n + 4 > _cap) break;
      final color = rgb[i];
      // the faint majority use a small cell; the rest a wider one
      final small = sigma < 1.1;
      final cs = small ? StarAtlas.smallSigma : StarAtlas.bigSigma, cell = small ? StarAtlas.smallSize : StarAtlas.bigSize;
      final cl = small ? StarAtlas.smallL : StarAtlas.bigL, ct = small ? StarAtlas.smallT : StarAtlas.bigT;
      final s = sigma / cs, half = cell / 2 * s;
      // one sprite carries at most full strength; as in the prototype a star may
      // reach 2.4, so the brightest get a second and third sprite laid over the first
      var left = a > 2.4 ? 2.4 : a;
      while (left > .004) {
        final layer = left > 1 ? 1.0 : left;
        left -= layer;
        final q = n * 4;
        xf[q] = s;
        xf[q + 1] = 0;
        xf[q + 2] = x - half;
        xf[q + 3] = y - half;
        src[q] = cl;
        src[q + 1] = ct;
        src[q + 2] = cl + cell;
        src[q + 3] = ct + cell;
        col[n++] = ((layer * 255).round() << 24) | color;
      }
      if (hk > 0) {
        final ha = math.min(a, 2.4) * hk * .085;
        if (ha > .004) {
          final hs = sigma / StarAtlas.haloSigma, hh = StarAtlas.haloSize / 2 * hs;
          final q = n * 4;
          xf[q] = hs;
          xf[q + 1] = 0;
          xf[q + 2] = x - hh;
          xf[q + 3] = y - hh;
          src[q] = StarAtlas.haloL;
          src[q + 1] = StarAtlas.haloT;
          src[q + 2] = StarAtlas.haloL + StarAtlas.haloSize;
          src[q + 3] = StarAtlas.haloT + StarAtlas.haloSize;
          col[n++] = ((ha >= 1 ? 255 : (ha * 255).round()) << 24) | color;
        }
      }
    }
    return n;
  }

  void _paintLine(Canvas canvas, Size size) {
    final e = engine, l = palette.lights[1];
    final paint = Paint()
      ..blendMode = BlendMode.plus
      // 1.6 device pixels and .42 strong. It was one pixel at .2, then at .34: Noah found the first
      // "very, very faint and difficult to see" and the second still not noticeable enough (2026-11-18).
      ..strokeWidth = 1.6 / dpr
      ..color = Color.fromARGB((.42 * math.min(1.0, math.max(e.names, e.ring)) * 255).round(), (l[0] * 255).round(), (l[1] * 255).round(), (l[2] * 255).round());
    var n = 0;
    void flush() {
      if (n >= 4) canvas.drawRawPoints(ui.PointMode.polygon, Float32List.sublistView(_linePts, 0, n), paint);
      n = 0;
    }

    // the opening's sweep: drawn from the left edge as far across as it has reached
    final reveal = e.lineReveal;
    if (reveal < 1) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    }
    for (final v in line) {
      e.project(v, _p);
      final off = _p.z < .05 || _p.x < -200 || _p.x > size.width + 200 || _p.y < -200 || _p.y > size.height + 200;
      if (off || n + 2 > _linePts.length) {
        flush();
        if (off) continue;
      }
      _linePts[n++] = _p.x;
      _linePts[n++] = _p.y;
    }
    flush();
    if (reveal < 1) canvas.restore();
  }

  TextPainter _label(String s, TextStyle style) => _text.putIfAbsent(
    '$s|${style.fontSize}|${style.color}',
    () => TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  /// How strongly each date label shows, eased frame to frame so labels fade
  /// rather than pop. Keyed by blessing, as the list changes under it.
  final Map<Object, double> _labelA = {};
  bool _labelsFading = true;

  /// True once labels have been painted and none are still fading in or out.
  bool get labelsSettled => !showLabels || !_labelsFading;

  /// The side of its light each date showing sits on: below (false) or above (true).
  final Map<Object, bool> _labelUp = {};
  Duration? _lastLabels;
  double _lastFov = 0;
  final List<Rect> _placed = [], _fading = [];

  /// Clear space a date needs round it to appear, and to stay. The gap
  /// between the two keeps a label from flickering at the edge of room.
  static const double showMargin = 9, keepMargin = 5;

  /// For tests: dates that had to vanish at once because something reached
  /// them faster than they could fade.
  static int debugCut = 0;

  /// Dates by the lights, and the names of the brightest stars, never
  /// touching one another. Each frame the dates are placed in order outward
  /// from the blessing in focus (its neighbours first), under the light or,
  /// if there is no room there, over it; a date whose box would come near one
  /// already placed waits, and fades out if it was showing. As
  /// the view zooms in and the lights spread apart, more of them find room.
  /// A date only appears where nothing still fading is in the way, and one
  /// fading out that would be touched is taken away at once, so no two drawn
  /// labels ever touch. Star names come last and take only the room left.
  void _paintLabels(Canvas canvas, Size size) {
    final e = engine;
    final top = size.height * .18, bottom = size.height * .56;
    final shadow = [Shadow(color: palette.ground.withValues(alpha: .9), blurRadius: 6)];
    final style = sans(12, 16, palette.ink2).copyWith(shadows: shadow);
    final now = Duration(microseconds: (e.clock * 1e6).round());
    final dt = _lastLabels == null ? 0.0 : ((now - _lastLabels!).inMicroseconds / 1e6).clamp(0.0, .1);
    _lastLabels = now;
    const fadeOut = .12;
    final rise = e.reduceMotion ? 1.0 : dt / .3, fall = e.reduceMotion ? 1.0 : dt / fadeOut;
    // zooming out draws the lights together; a date showing gives way early
    // enough to finish fading before its neighbour reaches it
    final out = dt > 0 && _lastFov > 0 ? math.max(0.0, math.log(e.shownFov / _lastFov)) / dt : 0.0;
    _lastFov = e.shownFov;
    final keep = keepMargin + 90 * out * fadeOut * 2;
    _placed.clear();
    _fading.clear();
    debugLabels.clear();
    _labelsFading = false;
    final n = e.blessings.length, f = n == 0 ? 0 : math.min(e.focus, n - 1);
    final strength = .95 * e.lights * (1 - e.solo);
    // the light in focus keeps a narrow column clear above and below it, so
    // no neighbour's date sits over it and reads as its own (its date is in
    // the caption)
    // (a date already showing there when the focus moves fades out over it)
    Rect? reserve;
    if (n > 0) {
      final q = e.points[f];
      if (q.z > 0) reserve = Rect.fromCenter(center: Offset(q.x, q.y), width: 8, height: 70);
    }
    bool clear(Iterable<Rect> rs, Rect r) => !rs.any(r.overlaps);
    bool room(Rect r) => clear(_placed, r) && !(reserve?.overlaps(r) ?? false);
    final seen = <Object>{};
    final drawn = <({Object key, TextPainter tp, Rect box, double alpha})>[];
    // the candidates in order, f-1, f+1, f-2, f+2, ..., with where each
    // showing one is now; a date may not appear over a showing one of lower
    // rank, which is asked to fade first (so they hand over, never overlap)
    final order = <({int b, TextPainter tp, double left, bool on})>[];
    final shownAt = <int, Rect>{};
    for (var k = 1; k < 2 * n; k++) {
      final b = f + ((k + 1) ~/ 2) * (k.isOdd ? -1 : 1);
      if (b < 0 || b >= n || b == f) continue;
      final bl = e.blessings[b];
      seen.add(bl);
      final p = e.points[b], wgt = e.weights[b];
      final on = p.z > 0 && wgt < .5 && p.x > 0 && p.x < size.width && p.y > top && p.y < bottom && strength > .02;
      // one leaving the band (or the light coming into focus) fades out where it is
      final leaving = !on && p.z > 0 && (_labelA[bl] ?? 0) > 0 && p.x > -60 && p.x < size.width + 60;
      if (!on && !leaving) {
        _labelA.remove(bl);
        _labelUp.remove(bl);
        continue;
      }
      final tp = _label(bl.shortDate, style);
      // centred on its light, but kept wholly on the screen
      final left = (p.x - tp.width / 2).clamp(6.0, math.max(6.0, size.width - 6 - tp.width)).toDouble();
      final i = order.length;
      order.add((b: b, tp: tp, left: left, on: on));
      if ((_labelA[bl] ?? 0) > 0) {
        final up = _labelUp[bl] ?? false;
        shownAt[i] = Rect.fromLTWH(left, up ? p.y - 15 - tp.height : p.y + 15, tp.width, tp.height);
      }
    }
    final yielding = <int>{};
    for (var i = 0; i < order.length; i++) {
      final (:b, :tp, :left, :on) = order[i];
      final bl = e.blessings[b];
      final p = e.points[b], wgt = e.weights[b];
      var a = _labelA[bl] ?? 0;
      Rect at(bool up) => Rect.fromLTWH(left, up ? p.y - 15 - tp.height : p.y + 15, tp.width, tp.height);
      final showing = a > 0;
      var up = _labelUp[bl] ?? false;
      var box = at(up);
      var fits = false;
      if (!on) {
        fits = false;
      } else if (showing) {
        fits = !yielding.contains(i) && room(box.inflate(keep));
      } else {
        Iterable<int> lower(Rect r) => shownAt.entries.where((s) => s.key > i && s.value.overlaps(r)).map((s) => s.key);
        bool free(Rect r) => room(r) && clear(_fading, r);
        final sides = [up, !up];
        final open = sides.where((side) => free(at(side).inflate(showMargin))).toList();
        final clean = open.where((side) => lower(at(side).inflate(showMargin)).isEmpty);
        if (clean.isNotEmpty) {
          up = clean.first;
          box = at(up);
          fits = true;
        } else if (open.isNotEmpty) {
          // room here once the lower-ranked dates in the way have faded
          yielding.addAll(lower(at(open.first).inflate(showMargin)).toList());
        }
      }
      _labelUp[bl] = up;
      if (fits) {
        _placed.add(box);
        a = math.min(1, a + rise);
        if (a < 1) _labelsFading = true;
      } else {
        a = math.max(0, a - fall);
        if (a > 0 && !(clear(_placed, box) && clear(_fading, box))) {
          a = 0;
          debugCut++;
        }
        if (a > 0) {
          _fading.add(box);
          _labelsFading = true;
        }
      }
      if (a <= 0) {
        _labelA.remove(bl);
        _labelUp.remove(bl);
        continue;
      }
      _labelA[bl] = a;
      drawn.add((key: bl, tp: tp, box: box, alpha: (1 - wgt * 2) * strength * a));
    }
    // a label kept may have been placed after a fading one it now touches; the fading one goes
    for (final d in drawn) {
      if (d.alpha < .02) continue;
      if (_fading.contains(d.box) && _placed.any(d.box.overlaps)) {
        _labelA.remove(d.key);
        debugCut++;
        continue;
      }
      _paintFaded(canvas, d.tp, d.box.topLeft, d.alpha);
      debugLabels.add((box: d.box, alpha: d.alpha, date: true));
    }
    _labelA.removeWhere((k, _) => !seen.contains(k));
    _labelUp.removeWhere((k, _) => !seen.contains(k));
    // names of the brightest stars, in the room left
    if (e.names < .02) return;
    final nameStyle = sans(11, 16, palette.ink3, tracking: .01).copyWith(shadows: shadow);
    for (final s in assets.stars.named) {
      e.project(s.v, _p);
      if (_p.z <= 0 || _p.x < 8 || _p.x > size.width - 50 || _p.y < top || _p.y > bottom) continue;
      final tp = _label(s.name, nameStyle);
      final box = Rect.fromLTWH(_p.x + 9, _p.y - 8, tp.width, tp.height);
      final room = box.inflate(keepMargin);
      if (_placed.any(room.overlaps) || _fading.any(room.overlaps)) continue;
      var clear = true;
      for (var b = 0; b < n; b++) {
        final q = e.points[b];
        if (q.z > 0 && room.inflate(6).contains(Offset(q.x, q.y))) {
          clear = false;
          break;
        }
      }
      if (!clear) continue;
      _placed.add(box);
      _paintFaded(canvas, tp, box.topLeft, .85 * e.names);
      debugLabels.add((box: box, alpha: .85 * e.names, date: false));
    }
  }

  void _paintFaded(Canvas canvas, TextPainter tp, Offset at, double alpha) {
    if (alpha >= .99) {
      tp.paint(canvas, at);
      return;
    }
    canvas.saveLayer((at & tp.size).inflate(8), Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0, 1)));
    tp.paint(canvas, at);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPainter old) => old.engine != engine || old.palette != palette || old.dpr != dpr || old.showLabels != showLabels || old.line != line;
}
