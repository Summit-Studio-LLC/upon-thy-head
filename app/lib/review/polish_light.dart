import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../sky/sky_engine.dart';
import '../theme.dart';

/// The light over the words while polish works ("Polish the words"), drawn on the review page's own
/// text, not beside it:
///
/// - the piece of the words with the phone's model carries a slow, soft band of gold light passing
///   over it, like light over a page; pieces not yet reached sit a little dimmed; finished pieces
///   are as they always are.
/// - when polish ends, the words it changed glint gold once and settle.
///
/// With Reduce Motion the piece being worked on has a steady soft tint instead of the band, and
/// the glint is a fade in and out.
///
/// It only paints: the text field below keeps its layout, selection, editing and screen-reader
/// node exactly as before. Where the words sit is read from the field's own laid-out text (its
/// [RenderEditable]) as it is painted, so the light stays on the right words as the page scrolls,
/// the text size changes, or the words are corrected while the model works. A frame of the band
/// repaints this layer alone; nothing is laid out again.
class PolishLight extends StatefulWidget {
  const PolishLight({
    super.key,
    required this.palette,
    required this.text,
    required this.child,
    this.basis = '',
    this.pieces = const [],
    this.at = -1,
    this.glints = const [],
    this.glint = 0,
  });

  final Palette palette;

  /// The words now in the field, and the words [pieces] and [glints] were measured in. They differ
  /// only when the words were corrected by hand while the model worked; the ranges then move with
  /// the words around the edit.
  final String text, basis;

  /// The words cut as the model takes them ([ModelSource.pieces]), and which is with it now: -1
  /// before the first and when polish is not running; pieces.length once all are done.
  final List<TextRange> pieces;
  final int at;

  /// The words changed by the polish just finished, which glint once; each new [glint] (a count)
  /// starts the glint again.
  final List<TextRange> glints;
  final int glint;

  /// The field: a [CupertinoTextField] (or anything holding one [RenderEditable]).
  final Widget child;

  /// One pass of the band over a piece, and the rest before the next.
  static const pass = Duration(milliseconds: 4200), rest = Duration(milliseconds: 1400);

  /// From one piece to the next: the band leaving one and the dimming lifting off the next.
  static const shift = Duration(milliseconds: 1100), shiftStill = Duration(milliseconds: 500);

  /// The glint at the finish: rising, then settling.
  static const glintRise = Duration(milliseconds: 380), glintFall = Duration(milliseconds: 1100);

  /// How much the pieces not yet reached are dimmed toward the page (0 none, 1 gone).
  static const dim = .36;

  @override
  State<PolishLight> createState() => PolishLightState();
}

class PolishLightState extends State<PolishLight> with TickerProviderStateMixin {
  /// The band's phase, 0 to 1 over [PolishLight.pass] + [PolishLight.rest], repeating.
  late final AnimationController _band = AnimationController(vsync: this, duration: PolishLight.pass + PolishLight.rest);

  // These two are fades, kept at their length with Reduce Motion (which otherwise cuts an
  // animation to a twentieth): there the glint is the fade in that marks the changes.

  /// From the last piece to this one, 0 to 1.
  late final AnimationController _shift =
      AnimationController(vsync: this, duration: PolishLight.shift, value: 1, animationBehavior: AnimationBehavior.preserve);

  /// The glint, 0 to 1.
  late final AnimationController _glint =
      AnimationController(vsync: this, duration: PolishLight.glintRise + PolishLight.glintFall, animationBehavior: AnimationBehavior.preserve);

  int _from = -1;
  bool _still = false;

  /// Whether any of its animations is running (for tests: every ticker stops when polish ends).
  bool get animating => _band.isAnimating || _shift.isAnimating || _glint.isAnimating;

  /// Whether the band is moving over a piece (for tests: never with Reduce Motion).
  bool get bandMoving => _band.isAnimating;

  bool get _working => widget.at >= 0 && widget.at < widget.pieces.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    _shift.duration = _still ? PolishLight.shiftStill : PolishLight.shift;
    _runBand();
  }

  @override
  void didUpdateWidget(PolishLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.at != widget.at || !identical(old.pieces, widget.pieces)) {
      // where the light was comes from the last frame's pieces; a new run starts from nothing
      _from = identical(old.pieces, widget.pieces) ? old.at : -1;
      // each piece's light begins at its own start
      // each piece's band starts from its beginning (setting the value stops it; _runBand goes on)
      if (_working) _band.value = 0;
      if (widget.pieces.isEmpty) {
        // stopped, or left: nothing to light, at once
        _shift.stop();
        _shift.value = 1;
      } else {
        _shift.forward(from: 0);
      }
    }
    if (widget.glints.isEmpty) {
      _glint.stop();
      _glint.value = 0;
    } else if (old.glint != widget.glint) {
      _glint.forward(from: 0);
    }
    _runBand();
  }

  void _runBand() {
    if (_working && !_still) {
      if (!_band.isAnimating) _band.repeat();
    } else if (_band.isAnimating) {
      _band.stop();
    }
  }

  @override
  void dispose() {
    _band.dispose();
    _shift.dispose();
    _glint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Light(
      palette: widget.palette,
      text: widget.text,
      basis: widget.basis,
      pieces: widget.pieces,
      at: widget.at,
      from: _from,
      glints: widget.glints,
      still: _still,
      band: _band,
      shift: _shift,
      glint: _glint,
      // the field's own pictures are kept as they are while the light repaints over them
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _Light extends SingleChildRenderObjectWidget {
  const _Light({
    required this.palette,
    required this.text,
    required this.basis,
    required this.pieces,
    required this.at,
    required this.from,
    required this.glints,
    required this.still,
    required this.band,
    required this.shift,
    required this.glint,
    required super.child,
  });

  final Palette palette;
  final String text, basis;
  final List<TextRange> pieces, glints;
  final int at, from;
  final bool still;
  final Animation<double> band, shift, glint;

  @override
  _RenderLight createRenderObject(BuildContext context) => _RenderLight(band, shift, glint)..set(this);

  @override
  void updateRenderObject(BuildContext context, _RenderLight r) => r.set(this);
}

class _RenderLight extends RenderProxyBox {
  _RenderLight(this._band, this._shift, this._glint);
  final Animation<double> _band, _shift, _glint;

  late Palette _p;
  String _text = '', _basis = '';
  List<TextRange> _pieces = const [], _glints = const [];
  int _at = -1, _from = -1;
  bool _still = false;

  void set(_Light w) {
    _p = w.palette;
    _text = w.text;
    _basis = w.basis;
    _pieces = w.pieces;
    _glints = w.glints;
    _at = w.at;
    _from = w.from;
    _still = w.still;
    markNeedsPaint();
  }

  // its own layer: a frame of the band repaints only this, over the field's kept pictures
  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final a in [_band, _shift, _glint]) {
      a.addListener(markNeedsPaint);
    }
  }

  @override
  void detach() {
    for (final a in [_band, _shift, _glint]) {
      a.removeListener(markNeedsPaint);
    }
    super.detach();
  }

  RenderEditable? _editable;

  RenderEditable? _findEditable() {
    if (_editable != null && _editable!.attached && _isBelow(_editable!)) return _editable;
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    if (child != null) visit(child!);
    return _editable = found;
  }

  bool _isBelow(RenderObject o) {
    for (RenderObject? r = o.parent; r != null; r = r.parent) {
      if (r == this) return true;
    }
    return false;
  }

  /// The rows of the words in [r] as the field lays them out, in the field's own coordinates; kept
  /// until the words or the field's size change.
  final Map<TextRange, List<Rect>> _rows = {};
  String? _rowsFor;
  Size? _rowsSize;

  List<Rect> _rowsOf(RenderEditable e, TextRange r) {
    if (_rowsFor != _text || _rowsSize != e.size) {
      _rows.clear();
      _rowsFor = _text;
      _rowsSize = e.size;
    }
    return _rows.putIfAbsent(r, () {
      final len = e.text?.toPlainText().length ?? 0;
      final a = r.start.clamp(0, len), b = r.end.clamp(0, len);
      if (b <= a) return const [];
      final boxes = e.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b));
      // one rect per line, so the light reads as lit lines rather than a box per run
      final lines = <Rect>[];
      for (final x in boxes) {
        final r = x.toRect();
        final i = lines.indexWhere((l) => (l.center.dy - r.center.dy).abs() < r.height / 2);
        if (i < 0) {
          lines.add(r);
        } else {
          lines[i] = lines[i].expandToInclude(r);
        }
      }
      lines.sort((x, y) => x.top.compareTo(y.top));
      return lines;
    });
  }

  /// [r], measured in [_basis], in the words now in the field: the words before a correction keep
  /// their offsets, those after it move with it, and those inside it close up to it.
  TextRange _moved(TextRange r) {
    if (_basis == _text || _basis.isEmpty) return r;
    final a = _basis, b = _text;
    var pre = 0;
    final most = math.min(a.length, b.length);
    while (pre < most && a.codeUnitAt(pre) == b.codeUnitAt(pre)) {
      pre++;
    }
    var suf = 0;
    while (suf < most - pre && a.codeUnitAt(a.length - 1 - suf) == b.codeUnitAt(b.length - 1 - suf)) {
      suf++;
    }
    int at(int o) {
      if (o <= pre) return o;
      if (o >= a.length - suf) return o + b.length - a.length;
      return pre;
    }

    return TextRange(start: at(r.start), end: at(r.end));
  }

  /// How a piece stands with polish at [at]: (dimmed, lit), each 0 or 1.
  (double, double) _state(int i, int at) {
    if (at < 0 || at >= _pieces.length) return (0, 0); // not running, or done
    if (i < at) return (0, 0);
    if (i == at) return (0, 1);
    return (1, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final e = child == null ? null : _findEditable();
    final glintV = _glintValue();
    final active = e != null && (_pieces.isNotEmpty || (glintV > 0 && _glints.isNotEmpty));
    if (!active) {
      super.paint(context, offset);
      return;
    }
    final toHere = e.getTransformTo(this);
    Rect place(Rect r) => MatrixUtils.transformRect(toHere, r).shift(offset);

    final s = Curves.easeInOut.transform(_shift.value);
    final lit = <(List<Rect>, double)>[], dimmed = <(List<Rect>, double)>[];
    for (var i = 0; i < _pieces.length; i++) {
      final (d0, l0) = _state(i, _from);
      final (d1, l1) = _state(i, _at);
      final d = d0 + (d1 - d0) * s, l = l0 + (l1 - l0) * s;
      if (d < .004 && l < .004) continue;
      final rows = [for (final r in _rowsOf(e, _moved(_pieces[i]))) place(r)];
      if (rows.isEmpty) continue;
      if (l >= .004) lit.add((rows, l));
      if (d >= .004) dimmed.add((rows, d));
    }
    // each change on its own, so the light never bridges the words between two changes
    final glintRows = glintV <= 0
        ? const <List<Rect>>[]
        : [
            for (final g in _glints)
              if (_rowsOf(e, _moved(g)) case final rows when rows.isNotEmpty) [for (final r in rows) place(r)],
          ];

    final canvas = context.canvas;
    // behind the words: the soft light itself
    for (final (rows, l) in lit) {
      _behind(canvas, rows, l);
    }
    for (final rows in glintRows) {
      _glow(canvas, rows, .20 * glintV, 5);
    }

    context.paintChild(child!, offset);

    // over the words: their ink warmed toward gold where the light is (multiplying the page's
    // near-black leaves it near-black, so only the letters take the colour), and the pieces not
    // yet reached drawn toward the page
    final over = context.canvas;
    for (final (rows, l) in lit) {
      _warm(over, rows, l);
    }
    for (final rows in glintRows) {
      _warmFlat(over, rows, .75 * glintV);
    }
    for (final (rows, d) in dimmed) {
      final paint = Paint()..color = _p.ground.withValues(alpha: PolishLight.dim * d);
      for (final r in rows) {
        over.drawRect(r.inflate(1), paint);
      }
    }
  }

  double _glintValue() {
    if (_glint.value <= 0 || _glint.value >= 1) return 0;
    final t = _glint.value * (PolishLight.glintRise + PolishLight.glintFall).inMilliseconds;
    final rise = PolishLight.glintRise.inMilliseconds.toDouble();
    if (t < rise) return Curves.easeOut.transform(t / rise);
    return 1 - Curves.easeInOut.transform((t - rise) / PolishLight.glintFall.inMilliseconds);
  }

  /// Where the band is: a point along [dir] across [bounds], or null while it rests between passes.
  Offset? _bandAt(Rect bounds, Offset dir, double half) {
    final cycle = (PolishLight.pass + PolishLight.rest).inMilliseconds;
    final t = _band.value * cycle / PolishLight.pass.inMilliseconds;
    if (t >= 1) return null;
    // from just before the piece's first corner to just past its last, along the band's direction
    final corners = [bounds.topLeft, bounds.topRight, bounds.bottomLeft, bounds.bottomRight];
    final proj = [for (final c in corners) c.dx * dir.dx + c.dy * dir.dy];
    final lo = proj.reduce(math.min) - half, hi = proj.reduce(math.max) + half;
    final along = lo + (hi - lo) * Curves.easeInOut.transform(t);
    final c = bounds.center;
    final cAlong = c.dx * dir.dx + c.dy * dir.dy;
    return c + dir * (along - cAlong);
  }

  // the band runs a little downhill, as light from a window falls across a page
  static final _dir = Offset(math.cos(.32), math.sin(.32));
  static const _half = 90.0;

  Rect _bounds(List<Rect> rows) => rows.reduce((a, b) => a.expandToInclude(b));

  /// The rows filled to meet the lines next to them, so the light has no stripes between lines.
  List<Rect> _joined(List<Rect> rows) {
    final out = <Rect>[];
    bool next(Rect a, Rect b) => b.top - a.bottom < a.height; // the very next line
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final top = i > 0 && next(rows[i - 1], r) ? (rows[i - 1].bottom + r.top) / 2 : r.top - 3;
      final bottom = i < rows.length - 1 && next(r, rows[i + 1]) ? (r.bottom + rows[i + 1].top) / 2 : r.bottom + 3;
      out.add(Rect.fromLTRB(r.left - 6, top, r.right + 6, bottom));
    }
    return out;
  }

  void _behind(Canvas canvas, List<Rect> rows, double l) {
    final gold = _p.light;
    // a steady faint light on the whole piece, so it is plain which piece it is between passes
    _glow(canvas, rows, (_still ? .085 : .06) * l, 8);
    if (_still) return;
    final at = _bandAt(_bounds(rows), _dir, _half);
    if (at == null) return;
    final paint = Paint()
      ..shader = ui.Gradient.linear(at - _dir * _half, at + _dir * _half, [gold.withValues(alpha: 0), gold.withValues(alpha: .17 * l), gold.withValues(alpha: 0)], const [0, .5, 1])
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final path = Path();
    for (final r in _joined(rows)) {
      path.addRect(r);
    }
    canvas.drawPath(path, paint);
  }

  void _glow(Canvas canvas, List<Rect> rows, double alpha, double blur) {
    if (alpha <= .002) return;
    final path = Path();
    for (final r in _joined(rows)) {
      path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _p.light.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  /// [k] as a colour to multiply by: white leaves the letters as they are, gold makes them gold.
  Color _tint(double k) => Color.lerp(const Color(0xFFFFFFFF), _p.light, k.clamp(0, 1))!;

  void _warm(Canvas canvas, List<Rect> rows, double l) {
    final base = (_still ? .42 : .16) * l;
    if (_still) {
      _warmFlat(canvas, rows, base);
      return;
    }
    final at = _bandAt(_bounds(rows), _dir, _half);
    final paint = Paint()..blendMode = BlendMode.modulate;
    if (at == null) {
      paint.color = _tint(base);
    } else {
      paint.shader = ui.Gradient.linear(at - _dir * _half, at + _dir * _half, [_tint(base), _tint(base + .62 * l), _tint(base)], const [0, .5, 1]);
    }
    for (final r in _joined(rows)) {
      canvas.drawRect(r, paint);
    }
  }

  void _warmFlat(Canvas canvas, List<Rect> rows, double k) {
    if (k <= .002) return;
    final paint = Paint()
      ..blendMode = BlendMode.modulate
      ..color = _tint(k);
    for (final r in _joined(rows)) {
      canvas.drawRect(r, paint);
    }
  }
}

/// A small gold light in the manner of the lights on the home sky, breathing slowly (four seconds
/// in, six out, as the sky's glow does). Still with Reduce Motion. Nothing for a screen reader.
class BreathingLight extends StatefulWidget {
  const BreathingLight({super.key, required this.palette, this.size = 14});
  final Palette palette;
  final double size;

  @override
  State<BreathingLight> createState() => BreathingLightState();
}

class BreathingLightState extends State<BreathingLight> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  /// Whether it is breathing now (for tests).
  bool get breathing => _t.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    // it grows with the words beside it, to twice its size at most
    final size = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2).scale(widget.size);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _DotPainter(widget.palette.light, _t, still),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.t, this.still) : super(repaint: t);
  final Color color;
  final Animation<double> t;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final br = still ? .6 : SkyEngine.breath(t.value * 10);
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // a soft halo that swells with the breath, and a small bright core, as a blessing's light
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .30 + .30 * br), color.withValues(alpha: .10 + .12 * br), color.withValues(alpha: 0)],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, 1.6 + .5 * br, Paint()..color = Color.lerp(color, const Color(0xFFFFF6E4), .35 + .25 * br)!.withValues(alpha: .75 + .25 * br));
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color || old.still != still;
}
