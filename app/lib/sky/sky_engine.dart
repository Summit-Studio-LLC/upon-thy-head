import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/blessing.dart';
import 'astro.dart';
import 'figures.dart';

/// How the sky is framed on each screen. The camera eases toward whichever is set.
class SkyView {
  const SkyView({
    required this.fov,
    required this.cy,
    required this.exp,
    required this.st,
    required this.orb,
    required this.lights,
    required this.solo,
    required this.names,
  });

  /// Field of view in degrees, top to bottom.
  final double fov;

  /// Where the look point sits vertically, in clip units (0 centre, 1 top).
  final double cy;

  /// Milky Way exposure, star brightness, recording glow.
  final double exp, st, orb;

  /// Strength of the blessings' lights; 1 shows only the one in focus; star names and the overhead circle.
  final double lights, solo, names;

  static const home = SkyView(fov: 90, cy: .2, exp: 1, st: 1, orb: 0, lights: 1, solo: 0, names: 1);
  /// The recording screen before Begin, and while it listens (the prototype's recGoal).
  static const ready = SkyView(fov: 74, cy: .14, exp: .018, st: .2, orb: .2, lights: 0, solo: 1, names: 0);
  static const record = SkyView(fov: 74, cy: .14, exp: .03, st: .5, orb: 1, lights: 0, solo: 1, names: 0);
  static const after = SkyView(fov: 74, cy: .3, exp: .72, st: .8, orb: 0, lights: 1, solo: 1, names: 0);
  static const read = SkyView(fov: 58, cy: .7, exp: 1, st: 1, orb: 0, lights: 1, solo: 1, names: 0);
  static const review = SkyView(fov: 58, cy: .7, exp: .5, st: .5, orb: 0, lights: 1, solo: 1, names: 0);
  /// Settings: the home sky where it is, dimmed, with no lights, ring or names.
  static const settings = SkyView(fov: 90, cy: .2, exp: .45, st: .55, orb: 0, lights: 0, solo: 0, names: 0);
}

class _Glide {
  _Glide(this.ra0, this.dec0, this.d, this.dec1, this.t0, this.dur, this.ang);
  final double ra0, dec0, d, dec1, t0, dur, ang;
}

/// A point of the sky as it lands on the screen.
class Projected {
  double x = 0, y = 0, z = 0;
}

/// The camera and everything that moves in the sky. No drawing happens here.
class SkyEngine extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  SkyEngine(this._blessings, {int focus = 0}) : _focus = focus {
    weights = List<double>.filled(_blessings.length, 0);
    points = List.generate(_blessings.length, (_) => Projected());
    _resetShown();
    snap();
  }

  /// Zoomed in this far, neighbours 1.1 degrees apart on the ring (300
  /// blessings on a full ring) stand about 50 points apart.
  static const double minFov = 15, maxFov = 104;

  /// Seconds a light takes to glide to a new place on the ring.
  static const double slideTime = .8;

  List<Blessing> get blessings => _blessings;
  List<Blessing> _blessings;
  late List<double> weights;
  late List<Projected> points;

  /// Where each light is drawn: its place by the rule, or on its way there
  /// after the places changed (a blessing saved, deleted, or redated).
  late List<Vec3> shown;
  List<double> _fromRa = const [], _fromDec = const [], _shownRa = const [], _shownDec = const [];
  double _slideT0 = -1;

  /// True while lights are gliding to new places.
  bool get sliding => _slideT0 >= 0;

  /// The constellations drawn while a recording listens; set once the sky has loaded.
  FigureShow? show;

  /// Engine clock when the glow's breath began; the breath restarts with each recording.
  double breathT0 = 0;

  /// Seconds since the sky started.
  double clock = 0;

  // Camera, eased every frame toward the goal.
  double ra = 0, dec = 0;
  double fov = 90, cy = .2, exp = 1, st = 1, orb = 0, lights = 1, solo = 0, names = 1;
  SkyView _goal = SkyView.home;
  double _goalFov = 90;
  double _bump = 0;

  _Glide? _glide;
  double _velRa = 0, _velDec = 0;
  bool _dragging = false;
  bool reduceMotion = false;

  /// True once the person has dragged away from the blessing in focus.
  bool get free => _free;
  bool _free = false;

  int get focus => _focus;
  int _focus;

  // Camera basis and tangent scale, refreshed by [basis].
  double fx = 1, fy = 0, fz = 0, rx = 0, ry = 1, rz = 0, ux = 0, uy = 0, uz = 1;
  double tx = 1, ty = 1;
  Size _size = const Size(390, 844);

  void setView(SkyView v) {
    _goal = v;
    _goalFov = v.fov;
  }

  /// Put the camera exactly where it is heading, with the blessing in focus centred.
  void snap() {
    fov = _goalFov;
    cy = _goal.cy;
    exp = _goal.exp;
    st = _goal.st;
    orb = _goal.orb;
    lights = _goal.lights;
    solo = _goal.solo;
    names = _goal.names;
    if (blessings.isNotEmpty) {
      final b = blessings[_focus];
      ra = b.ra;
      dec = b.dec;
    }
    _resetShown();
    _glide = null;
    _velRa = _velDec = 0;
    _free = false;
    _bump = 0;
    for (var i = 0; i < weights.length; i++) {
      weights[i] = i == _focus ? 1 : 0;
    }
  }

  /// Replace the blessings (a new one added, or a draft taken away), focusing
  /// [focus] without moving the camera. Lights already shown keep their weight.
  ///
  /// Lights whose place changed glide there over [slideTime]; a light new to
  /// the sky appears at its place. While they glide, a camera resting on the
  /// blessing in focus goes with it.
  void setBlessings(List<Blessing> list, {required int focus}) {
    final old = {for (var i = 0; i < _blessings.length; i++) _blessings[i]: i};
    final oldW = weights, oldRa = _shownRa, oldDec = _shownDec;
    _blessings = List.of(list);
    final n = _blessings.length;
    weights = [for (final b in _blessings) old[b] == null ? 0 : oldW[old[b]!]];
    points = List.generate(n, (_) => Projected());
    _fromRa = [for (final b in _blessings) old[b] == null ? b.ra : oldRa[old[b]!]];
    _fromDec = [for (final b in _blessings) old[b] == null ? b.dec : oldDec[old[b]!]];
    _shownRa = List.of(_fromRa);
    _shownDec = List.of(_fromDec);
    shown = [for (var i = 0; i < n; i++) Vec3.radec(_shownRa[i], _shownDec[i])];
    var moved = false;
    for (var i = 0; i < n && !moved; i++) {
      moved = _angle(_fromRa[i], _fromDec[i], _blessings[i]) > 1e-7;
    }
    _slideT0 = moved && !reduceMotion ? clock : -1;
    if (!moved || reduceMotion) _resetShown();
    _focus = focus.clamp(0, math.max(0, n - 1));
    notifyListeners();
  }

  static double _wrap(double d) => ((d + math.pi) % tau + tau) % tau - math.pi;

  static double _angle(double ra, double dec, Blessing b) => _wrap(b.ra - ra).abs() * math.cos(b.dec) + (b.dec - dec).abs();

  /// Every light at its place by the rule.
  void _resetShown() {
    _shownRa = [for (final b in _blessings) b.ra];
    _shownDec = [for (final b in _blessings) b.dec];
    _fromRa = List.of(_shownRa);
    _fromDec = List.of(_shownDec);
    shown = [for (final b in _blessings) b.v];
    _slideT0 = -1;
  }

  /// Run [body] with the camera put somewhere else for a moment.
  void withCamera(double ra, double dec, double fov, double cy, Size size, void Function() body) {
    final keep = (ra: this.ra, dec: this.dec, fov: this.fov, cy: this.cy, bump: _bump, size: _size);
    this.ra = ra;
    this.dec = dec;
    this.fov = fov;
    this.cy = cy;
    _bump = 0;
    basis(size);
    body();
    this.ra = keep.ra;
    this.dec = keep.dec;
    this.fov = keep.fov;
    this.cy = keep.cy;
    _bump = keep.bump;
    basis(keep.size);
  }

  Size get size => _size;

  void setFocus(int i, {bool instant = false}) {
    if (blessings.isEmpty) return;
    i = i.clamp(0, blessings.length - 1);
    final changed = i != _focus;
    _focus = i;
    lookAt(i, instant: instant);
    if (changed) notifyListeners();
  }

  /// Turn toward a blessing: an eased glide that pulls back a little on the way.
  void lookAt(int i, {bool instant = false}) {
    if (i < 0 || i >= blessings.length) return;
    final b = blessings[i];
    lookToward(b.ra, b.dec, instant: instant);
  }

  /// Turn toward a point of the sky, as [lookAt].
  void lookToward(double toRa, double toDec, {bool instant = false}) {
    final wasFree = _free;
    _free = false;
    _velRa = _velDec = 0;
    final d = _wrap(toRa - ra);
    final ang = d.abs() * math.cos(toDec) + (toDec - dec).abs();
    if (instant || ang < 1e-4) {
      ra = toRa;
      dec = toDec;
      _glide = null;
    } else {
      _glide = _Glide(ra, dec, d, toDec, clock, reduceMotion ? .01 : 1.1 + 1.5 * math.min(1, ang / 2.4), ang);
    }
    if (wasFree) notifyListeners();
  }

  // ---- looking around ----

  void dragStart() {
    _dragging = true;
    _velRa = _velDec = 0;
  }

  /// [delta] in logical pixels, [dt] seconds since the last move.
  void dragBy(Offset delta, double dt) {
    if (!_free) {
      _free = true;
      _glide = null;
      _bump = 0;
      notifyListeners();
    }
    final s = ty / (_size.height / 2);
    final dra = delta.dx * s / math.max(.2, math.cos(dec)), dde = delta.dy * s;
    ra += dra;
    dec = (dec + dde).clamp(-86 * deg, 86 * deg);
    dt = math.max(.008, dt);
    _velRa = (.6 * _velRa + .4 * dra / dt).clamp(-1.6, 1.6);
    _velDec = (.6 * _velDec + .4 * dde / dt).clamp(-1.6, 1.6);
  }

  void dragEnd({required bool still}) {
    _dragging = false;
    if (still) _velRa = _velDec = 0;
  }

  /// Pinch: set the field of view directly so it tracks the fingers.
  void zoomTo(double newFov) {
    _goalFov = newFov.clamp(minFov, maxFov);
    fov = _goalFov;
  }

  double get goalFov => _goalFov;

  /// The field of view as drawn, with the pull-back while turning.
  double get shownFov => fov + _bump;

  /// Pinch: set the field of view and turn the camera so the sky under
  /// [focal] stays under the fingers.
  void pinch(double newFov, Offset focal) {
    if (!_free) {
      _free = true;
      _glide = null;
      _bump = 0;
      notifyListeners();
    }
    basis(_size);
    final v = unproject(focal);
    zoomTo(newFov);
    final ra0 = math.atan2(v.y, v.x), dec0 = math.asin(v.z.clamp(-1.0, 1.0));
    for (var k = 0; k < 3; k++) {
      basis(_size);
      final w = unproject(focal);
      var d = ra0 - math.atan2(w.y, w.x);
      d = ((d + math.pi) % tau + tau) % tau - math.pi;
      ra += d;
      dec = (dec + dec0 - math.asin(w.z.clamp(-1.0, 1.0))).clamp(-86 * deg, 86 * deg);
    }
  }

  /// The direction on the sky under a point of the canvas (inverse of [project]).
  Vec3 unproject(Offset p) {
    final nx = p.dx / _size.width * 2 - 1, ny = 1 - p.dy / _size.height * 2;
    final qx = nx * tx, qy = (ny - cy) * ty, r2 = qx * qx + qy * qy;
    final a = 4 - r2;
    final x = fx * a + (rx * qx + ux * qy) * 4;
    final y = fy * a + (ry * qx + uy * qy) * 4;
    final z = fz * a + (rz * qx + uz * qy) * 4;
    final l = math.sqrt(x * x + y * y + z * z);
    return Vec3(x / l, y / l, z / l);
  }

  /// The blessing whose light is nearest a touch, or -1.
  int hit(Offset p, {double reach = 34}) {
    var best = -1;
    var bd = reach;
    for (var i = 0; i < points.length; i++) {
      final q = points[i];
      if (q.z < 0) continue;
      final d = (Offset(q.x, q.y) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  // ---- frame ----

  void step(double dt) {
    clock += dt;
    final k = 1 - math.exp(-dt * 3.2);
    fov += (_goalFov - fov) * k;
    cy += (_goal.cy - cy) * k;
    exp += (_goal.exp - exp) * k;
    st += (_goal.st - st) * k;
    orb += (_goal.orb - orb) * k;
    lights += (_goal.lights - lights) * k;
    solo += (_goal.solo - solo) * k;
    names += (_goal.names - names) * k;

    final g = _glide;
    if (g != null) {
      final u = ((clock - g.t0) / g.dur).clamp(0.0, 1.0), e = easeInOutCubic(u);
      ra = g.ra0 + g.d * e;
      dec = g.dec0 + (g.dec1 - g.dec0) * e;
      _bump = math.sin(math.pi * u) * math.min(1, g.ang / 1.2) * 10 * (identical(_goal, SkyView.home) ? 1 : 0);
      if (u >= 1) {
        _glide = null;
        _bump = 0;
      }
    } else if (_free && !_dragging) {
      ra += _velRa * dt;
      dec = (dec + _velDec * dt).clamp(-86 * deg, 86 * deg);
      final f = math.exp(-dt * 4.2);
      _velRa *= f;
      _velDec *= f;
    }
    if (_slideT0 >= 0) {
      final u = ((clock - _slideT0) / slideTime).clamp(0.0, 1.0), k = easeInOutCubic(u);
      for (var i = 0; i < _blessings.length; i++) {
        final b = _blessings[i];
        _shownRa[i] = _fromRa[i] + _wrap(b.ra - _fromRa[i]) * k;
        _shownDec[i] = _fromDec[i] + (b.dec - _fromDec[i]) * k;
        shown[i] = Vec3.radec(_shownRa[i], _shownDec[i]);
      }
      // the camera stays with the blessing in focus unless it is turning or set free
      if (!_free && _glide == null && _focus < _blessings.length) {
        ra = _shownRa[_focus];
        dec = _shownDec[_focus];
      }
      if (u >= 1) _resetShown();
    }
    show?.step(dt);
    final wk = 1 - math.exp(-dt * 5);
    for (var i = 0; i < weights.length; i++) {
      weights[i] += ((i == _focus ? 1 : 0) - weights[i]) * wk;
    }
  }

  /// Refresh the camera basis for a canvas of [size].
  void basis(Size size) {
    _size = size;
    final cd = math.cos(dec), sd = math.sin(dec), ca = math.cos(ra), sa = math.sin(ra);
    fx = cd * ca;
    fy = cd * sa;
    fz = sd;
    rx = sa;
    ry = -ca;
    rz = 0;
    ux = -sd * ca;
    uy = -sd * sa;
    uz = cd;
    ty = 2 * math.tan((fov + _bump) * deg / 4);
    tx = ty * size.width / size.height;
  }

  /// Stereographic projection of a direction onto the canvas.
  void project(Vec3 v, Projected out) {
    final z = v.x * fx + v.y * fy + v.z * fz;
    final x = v.x * rx + v.y * ry;
    final y = v.x * ux + v.y * uy + v.z * uz;
    final k = 2 / (1.0001 + z);
    final nx = x * k / tx, ny = y * k / ty + cy;
    out.x = (nx * .5 + .5) * _size.width;
    out.y = (1 - (ny * .5 + .5)) * _size.height;
    out.z = z;
  }

  /// A slow breath, four seconds in and six out, as on the recording screen.
  static double breath(double t) {
    final p = t % 10;
    return p < 4 ? (.5 - .5 * math.cos(math.pi * p / 4)) : (.5 + .5 * math.cos(math.pi * (p - 4) / 6));
  }
}
