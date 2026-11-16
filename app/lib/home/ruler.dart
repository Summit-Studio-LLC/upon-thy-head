import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../theme.dart';

/// The line of months along the bottom of the home screen, with a dot for each
/// blessing. Touch or drag along it to turn to the nearest one.
class Ruler extends StatelessWidget {
  const Ruler({
    super.key,
    required this.blessings,
    required this.focus,
    required this.palette,
    required this.now,
    required this.onPick,
  });

  final List<Blessing> blessings;
  final int focus;
  final Palette palette;
  final DateTime now;

  /// Called with the index of the blessing nearest the touch; [fresh] is true on first contact.
  final void Function(int index, {required bool fresh}) onPick;

  DateTime get _start => DateTime.utc((blessings.isEmpty ? now : blessings.first.local).year);
  DateTime get _end => DateTime.utc(now.year + 1);

  double _frac(DateTime t) =>
      (t.millisecondsSinceEpoch - _start.millisecondsSinceEpoch) / (_end.millisecondsSinceEpoch - _start.millisecondsSinceEpoch);

  void _pick(Offset local, double width, {required bool fresh}) {
    if (blessings.isEmpty) return;
    final x = local.dx / width;
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < blessings.length; i++) {
      final d = (_frac(blessings[i].local) - x).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    onPick(best, fresh: fresh);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _pick(d.localPosition, w, fresh: true),
        onPanUpdate: (d) => _pick(d.localPosition, w, fresh: false),
        child: SizedBox(
          height: 48,
          width: w,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _TicksPainter(this))),
            for (var i = 0; i < blessings.length; i++)
              Positioned(
                left: _frac(blessings[i].local) * w - 10,
                top: 0.5,
                width: 20,
                height: 20,
                child: Center(child: _Dot(on: i == focus, color: palette.light)),
              ),
          ]),
        ),
      );
    });
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.color});
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: on ? 1.5 : 1,
      duration: const Duration(milliseconds: 350),
      curve: easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: on ? 1 : .62),
          boxShadow: [BoxShadow(color: color.withValues(alpha: on ? .18 : 0), spreadRadius: 3)],
        ),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter(this.r);
  final Ruler r;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = r.palette.ink;
    final years = r._end.year - r._start.year;
    final sparse = years > 4;
    final paint = Paint()..strokeWidth = 1;
    for (var m = 0; m <= years * 12; m++) {
      if (sparse && m % 3 != 0) continue;
      final t = DateTime.utc(r._start.year, 1 + m);
      final x = (r._frac(t) * size.width).roundToDouble() + .5;
      final year = m % 12 == 0;
      paint.color = ink.withValues(alpha: t.isAfter(r.now) ? .09 : (year ? .5 : .22));
      canvas.drawLine(Offset(x, year ? 4 : 10), Offset(x, 15), paint);
      if (year && m < years * 12 && (!sparse || (m ~/ 12) % 2 == 1)) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${t.year}',
            style: sans(11, 14, r.palette.ink3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + size.width / years / 2 - tp.width / 2, 22));
      }
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) =>
      old.r.blessings != r.blessings || old.r.palette != r.palette || old.r.now.year != r.now.year;
}
