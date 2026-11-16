import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import 'session.dart';

/// The round button at the foot of the recording screen. In the first ten
/// seconds it reads Discard, with a thin arc counting the seconds down; after
/// that it reads Amen. Either way it acts only when held for [RecordSession.hold],
/// with a ring of light filling as it is held. A shorter press nudges the hint.
class HoldRing extends StatefulWidget {
  const HoldRing({
    super.key,
    required this.palette,
    required this.amen,
    required this.countdown,
    required this.onHeld,
    required this.onShortPress,
  });

  final Palette palette;

  /// False: Discard. True: Amen.
  final bool amen;

  /// Fraction of the discard window gone, 0 to 1.
  final ValueListenable<double> countdown;

  /// Held all the way: discard, or finish.
  final VoidCallback onHeld;

  /// Let go too soon.
  final VoidCallback onShortPress;

  static const double size = 88, reach = 16;

  @override
  State<HoldRing> createState() => HoldRingState();
}

class HoldRingState extends State<HoldRing> with TickerProviderStateMixin {
  late final AnimationController _prog = AnimationController(vsync: this);
  Timer? _timer;
  int? _pointer;

  /// A hold was cut short by the change from Discard to Amen; nothing more
  /// happens until the finger lifts.
  bool _spent = false;

  bool get holding => _timer != null;

  @override
  void didUpdateWidget(HoldRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amen != widget.amen && _pointer != null) {
      // the ten seconds ran out under the finger: drop the hold and do nothing
      _drop();
      _spent = true;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prog.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _spent = false;
    _prog.animateTo(1, duration: RecordSession.hold * (1 - _prog.value), curve: Curves.linear);
    _timer = Timer(RecordSession.hold, () {
      _timer = null;
      _pointer = null;
      _prog.value = 0;
      setState(() {});
      widget.onHeld();
    });
    setState(() {});
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_spent) {
      _spent = false;
      return;
    }
    if (_timer != null) {
      _drop();
      widget.onShortPress();
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _timer == null) return;
    const c = Offset(HoldRing.size / 2 + HoldRing.reach, HoldRing.size / 2 + HoldRing.reach);
    if ((e.localPosition - c).distance > HoldRing.size / 2 + 24) {
      // slid off the ring: the same as letting go
      _pointer = null;
      _drop();
      widget.onShortPress();
    }
  }

  void _drop() {
    _timer?.cancel();
    _timer = null;
    _prog.animateBack(0, duration: const Duration(milliseconds: 250), curve: easeOut);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final color = holding ? p.light : p.ink;
    const box = HoldRing.size + HoldRing.reach * 2;
    return Semantics(
      button: true,
      label: widget.amen ? Strings.amenLabel : Strings.discardLabel,
      onLongPress: widget.onHeld,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        onPointerMove: _move,
        child: SizedBox(
          width: box,
          height: box,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.amen ? 0 : 1),
                duration: const Duration(milliseconds: 800),
                curve: easeOut,
                builder: (context, countAlpha, _) => CustomPaint(
                  painter: _RingPainter(p, widget.countdown, _prog, countAlpha),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: widget.amen ? 0 : 1,
              duration: const Duration(milliseconds: 800),
              curve: easeOut,
              child: Text(Strings.discard, key: const Key('lb-discard'), style: serif(19, 19, color)),
            ),
            AnimatedOpacity(
              opacity: widget.amen ? 1 : 0,
              duration: const Duration(milliseconds: 800),
              curve: easeOut,
              child: Text(Strings.amen, key: const Key('lb-amen'), style: serif(21, 21, color)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.countdown, this.prog, this.countAlpha) : super(repaint: Listenable.merge([countdown, prog]));
  final Palette p;
  final ValueListenable<double> countdown;
  final Animation<double> prog;
  final double countAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 42.5;
    // a disc of night behind the ring so stars and figures never run through it
    canvas.drawCircle(
      c,
      size.width / 2,
      Paint()
        ..shader = RadialGradient(
          colors: [p.ground, p.ground, p.ground.withValues(alpha: 0)],
          stops: const [0, .72, 1],
        ).createShader(Rect.fromCircle(center: c, radius: size.width / 2)),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r, stroke..color = p.ink.withValues(alpha: .28));
    final rect = Rect.fromCircle(center: c, radius: r);
    final left = 1 - countdown.value.clamp(0.0, 1.0);
    if (countAlpha > .004 && left > 0) {
      canvas.drawArc(rect, -math.pi / 2, left * 2 * math.pi, false, stroke..color = p.ink.withValues(alpha: .62 * countAlpha));
    }
    if (prog.value > 0) {
      canvas.drawArc(rect, -math.pi / 2, prog.value * 2 * math.pi, false, stroke..color = p.light);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.countAlpha != countAlpha || old.p != p;
}
