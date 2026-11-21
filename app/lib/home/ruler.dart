import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
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
    this.begins,
  });

  /// When the ring begins (a family member's birth), if before the first blessing: the months
  /// start there.
  final DateTime? begins;

  final List<Blessing> blessings;
  final int focus;
  final Palette palette;
  final DateTime now;

  /// Called with the index of the blessing nearest the touch; [fresh] is true on first contact.
  final void Function(int index, {required bool fresh}) onPick;

  DateTime get _start {
    final first = blessings.isEmpty ? now : blessings.first.local;
    final b = begins;
    return DateTime.utc((b != null && b.isBefore(first) ? b : first).year);
  }
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
      // VoiceOver and TalkBack: a slider over the blessings, its value the one in focus; a swipe up
      // or down turns to the next or the one before (the drag along it is for a finger)
      String said(int i) => '${blessings[i].longDate}. ${blessings[i].shownTitle}';
      final has = blessings.isNotEmpty && focus >= 0 && focus < blessings.length;
      final later = has && focus < blessings.length - 1, earlier = has && focus > 0;
      return Semantics(
        slider: true,
        label: Strings.rulerLabel,
        value: has ? said(focus) : null,
        increasedValue: later ? said(focus + 1) : null,
        decreasedValue: earlier ? said(focus - 1) : null,
        onIncrease: later ? () => onPick(focus + 1, fresh: true) : null,
        onDecrease: earlier ? () => onPick(focus - 1, fresh: true) : null,
        excludeSemantics: true,
        child: GestureDetector(
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

/// The least clear space between two years' labels on the bar.
const double rulerLabelGap = 8;

/// Which years the bar names, and where: the centre of each labelled year's span across a bar
/// [width] wide covering [years] years from [startYear], for labels [labelWidth] wide. Every year
/// when they fit; otherwise every 2nd, 5th, 10th, 20th, 50th year (on the round years from the 5th
/// up), the first of those steps that keeps [rulerLabelGap] clear between neighbours, so a ring of
/// thirty years reads "2000 2005 2010…" rather than running its labels together. A ring of more
/// than four years names every second year at the least, as it always has. No label runs past
/// either end of the bar.
@visibleForTesting
List<({int year, double centre})> rulerYearLabels({
  required int startYear,
  required int years,
  required double width,
  required double labelWidth,
}) {
  if (years <= 0 || width <= 0) return const [];
  final span = width / years;
  final need = labelWidth + rulerLabelGap;
  var step = years > 4 ? 2 : 1;
  for (final s in const [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]) {
    if (s < step) continue;
    step = s;
    if (s * span >= need) break;
  }
  final out = <({int year, double centre})>[];
  for (var i = 0; i < years; i++) {
    final year = startYear + i;
    // every second: the second year of each pair from the start, as before; wider steps: round years
    final named = step == 1 || (step == 2 ? i % 2 == 1 : year % step == 0);
    if (!named) continue;
    // kept inside the bar: a year at either end is drawn a little off its middle rather than left out
    if (labelWidth > width) break;
    final centre = (span * (i + .5)).clamp(labelWidth / 2, width - labelWidth / 2);
    if (out.isNotEmpty && centre - out.last.centre < need) continue;
    out.add((year: year, centre: centre));
  }
  return out;
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
    }
    // the years' names, under the middle of each year named; never touching (see [rulerYearLabels])
    final style = sans(11, 14, r.palette.ink3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    TextPainter label(int year) => TextPainter(text: TextSpan(text: '$year', style: style), textDirection: TextDirection.ltr)..layout();
    // the widest of the years shown (all four figures wide, the figures of one width)
    final first = label(r._start.year), last = label(r._end.year - 1);
    final widest = first.width > last.width ? first.width : last.width;
    first.dispose();
    last.dispose();
    for (final l in rulerYearLabels(startYear: r._start.year, years: years, width: size.width, labelWidth: widest)) {
      final tp = label(l.year);
      tp.paint(canvas, Offset(l.centre - tp.width / 2, 22));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) =>
      old.r.blessings != r.blessings || old.r.palette != r.palette || old.r.now.year != r.now.year;
}
