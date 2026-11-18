import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';

/// The list view of "For me": the ruler stood upright. One line through every
/// blessing, newest at the top; gaps follow the time between blessings, within
/// limits so near ones never collide and far ones never leave a long blank.
/// As the list scrolls, a lit stretch of the line runs down it, each blessing
/// lighting as it is reached, and the one nearest the head is marked current.
class Timeline extends StatefulWidget {
  const Timeline({super.key, required this.blessings, required this.palette, required this.now, required this.on, required this.onOpen});

  /// Oldest first, as everywhere else.
  final List<Blessing> blessings;
  final Palette palette;
  final DateTime now;

  /// Shown; each time it turns on the list starts at the top and the line draws in.
  final bool on;
  final void Function(int index) onOpen;

  // The prototype's measures, in points from the top of the screen.
  static const double perMonth = 24, minGap = 84, maxGap = 200, firstRow = 206, end = 480, tail = 64;
  static const double lineX = 88;

  @override
  State<Timeline> createState() => TimelineState();
}

/// Where everything sits, worked out once per list of blessings.
class TimelineLayout {
  TimelineLayout._(this.top, this.ys, this.yN, this.ticks, this.height, this.years);

  /// Where the line starts (above the newest), each blessing's y, the last y, and the whole height.
  final double top, yN, height;
  final List<double> ys;
  final List<({double y, bool year})> ticks;

  /// Whether a row shows its year under the day (the first, and wherever the year changes).
  final List<bool> years;

  static const _month = 30.4375 * 864e5;

  /// [rowHeights], when given, is each row's own height (oldest first): a gap never comes out
  /// shorter than the row above it, so rows never overlap however large the text (at the usual
  /// sizes every row is shorter than [Timeline.minGap], and the gaps are just the time's).
  static TimelineLayout of(List<Blessing> bs, DateTime now, double screenH, double dy, {List<double>? rowHeights}) {
    const t = Timeline.firstRow;
    final ticks = <({double y, bool year})>[];
    // the wall-clock time where each blessing was given, read as UTC so months line up
    double ms(DateTime d) => d.millisecondsSinceEpoch.toDouble();
    final nowMs = ms(now.toUtc().add(now.timeZoneOffset));
    void tick(double tNew, double tOld, double yNew, double yOld) {
      final d = DateTime.fromMillisecondsSinceEpoch(tNew.toInt(), isUtc: true);
      var m = DateTime.utc(d.year, d.month);
      while (ms(m) > tOld) {
        ticks.add((y: yNew + (tNew - ms(m)) / (tNew - tOld) * (yOld - yNew), year: m.month == 1));
        m = DateTime.utc(m.year, m.month - 1);
      }
    }

    final n = bs.length;
    final ys = List<double>.filled(n, 0);
    final years = List<bool>.filled(n, false);
    if (n == 0) return TimelineLayout._(t + dy, ys, t + dy, ticks, 0, years);
    final newest = ms(bs.last.local);
    final top = t + dy - ((nowMs - newest) / _month * Timeline.perMonth).clamp(20.0, 48.0);
    var y = t + dy;
    tick(nowMs, newest, top, y);
    int? lastYear;
    for (var i = n - 1; i >= 0; i--) {
      if (i < n - 1) {
        final a = ms(bs[i + 1].local), b = ms(bs[i].local);
        final gap = math.max(((a - b) / _month * Timeline.perMonth).clamp(Timeline.minGap, Timeline.maxGap), rowHeights?[i + 1] ?? 0);
        if (a > b) tick(a, b, y, y + gap);
        y += gap;
      }
      ys[i] = y;
      final yr = bs[i].local.year;
      years[i] = yr != lastYear;
      lastYear = yr;
    }
    final oldest = ms(bs.first.local);
    tick(oldest, oldest - Timeline.tail / Timeline.perMonth * _month, y, y + Timeline.tail);
    return TimelineLayout._(top, ys, y, ticks, y + screenH - Timeline.end - dy, years);
  }
}

class TimelineState extends State<Timeline> with SingleTickerProviderStateMixin {
  final ScrollController scroll = ScrollController();
  // made in initState, not lazily: a lazy one would first be made in dispose
  // when the list was never opened, and that throws
  late final AnimationController _draw;
  TimelineLayout? _layout;
  ({List<Blessing> bs, double h, double dy, double w, TextScaler scaler})? _for;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    scroll.addListener(() => setState(() {}));
    if (widget.on) _draw.forward(from: 0);
  }

  @override
  void didUpdateWidget(Timeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !oldWidget.on) {
      if (scroll.hasClients) scroll.jumpTo(0);
      _draw.forward(from: 0);
    }
    if (!widget.on && oldWidget.on) _draw.value = 0;
  }

  @override
  void dispose() {
    scroll.dispose();
    _draw.dispose();
    super.dispose();
  }

  /// How far down the line the lit head has run, and which row is current.
  ({double head, int current}) headAt(TimelineLayout l, double offset, double maxOffset) {
    final p = (offset / math.max(1, maxOffset)).clamp(0.0, 1.0);
    final head = Timeline.firstRow + _dy + (l.yN - Timeline.firstRow - _dy) * p;
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < l.ys.length; i++) {
      final d = (l.ys[i] - head).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return (head: head, current: best);
  }

  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final mq = MediaQuery.of(context);
    _dy = math.max(62.0, mq.viewPadding.top) - 62;
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final scaler = mq.textScaler;
      final key = (bs: widget.blessings, h: h, dy: _dy, w: box.maxWidth, scaler: scaler);
      if (_layout == null || _for != key) {
        final rows = [for (final b in widget.blessings) _Row.height(b, box.maxWidth, scaler)];
        _layout = TimelineLayout.of(widget.blessings, widget.now, h, _dy, rowHeights: rows);
        _for = key;
      }
      final l = _layout!;
      final bs = widget.blessings;
      final offset = scroll.hasClients ? scroll.offset : 0.0;
      final maxOffset = math.max(0.0, l.height - h);
      final at = headAt(l, offset, maxOffset);
      return ColoredBox(
        color: p.ground,
        child: SingleChildScrollView(
          key: const Key('list-scroll'),
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          child: SizedBox(
            height: math.max(l.height, h),
            child: bs.isEmpty
                ? null
                : Stack(children: [
                    // the line, drawn in from the top when the list opens
                    Positioned(
                      left: Timeline.lineX,
                      top: l.top,
                      width: 1,
                      height: l.yN + Timeline.tail - l.top,
                      child: AnimatedBuilder(
                        animation: _draw,
                        builder: (context, _) => Transform(
                          alignment: Alignment.topCenter,
                          transform: Matrix4.diagonal3Values(1, easeOut.transform(((_draw.value * 1200 - 100) / 1100).clamp(0.0, 1.0)), 1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [p.ink.withValues(alpha: .24), p.ink.withValues(alpha: .24), p.ink.withValues(alpha: 0)],
                                stops: const [0, .88, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final t in l.ticks)
                      Positioned(
                        left: t.year ? 77 : 83,
                        top: t.y,
                        width: t.year ? 11 : 5,
                        height: 1,
                        child: ColoredBox(color: p.ink.withValues(alpha: t.year ? .5 : .22)),
                      ),
                    // the lit stretch and its head
                    Positioned(
                      left: Timeline.lineX - .5,
                      top: l.top,
                      width: 2,
                      height: math.max(0, at.head - l.top),
                      child: DecoratedBox(decoration: BoxDecoration(color: p.light, borderRadius: BorderRadius.circular(1))),
                    ),
                    Positioned(
                      key: const Key('list-head'),
                      left: Timeline.lineX + .5 - 3,
                      top: at.head - 3,
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.light,
                          boxShadow: [BoxShadow(color: p.light.withValues(alpha: .5), blurRadius: 10, spreadRadius: 2)],
                        ),
                      ),
                    ),
                    for (var i = bs.length - 1; i >= 0; i--)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: l.ys[i] - 20,
                        child: _Row(
                          key: Key('row-${bs[i].id}'),
                          blessing: bs[i],
                          palette: p,
                          showYear: l.years[i],
                          lit: l.ys[i] <= at.head + 1,
                          current: i == at.current,
                          onTap: () => widget.onOpen(i),
                        ),
                      ),
                  ]),
          ),
        ),
      );
    });
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.blessing,
    required this.palette,
    required this.showYear,
    required this.lit,
    required this.current,
    required this.onTap,
  });

  final Blessing blessing;
  final Palette palette;
  final bool showYear, lit, current;
  final VoidCallback onTap;

  static const _pad = EdgeInsets.fromLTRB(112, 8, 24, 8);

  /// The row's height at this width and text size: its title, giver and draft line, as built below.
  static double height(Blessing b, double width, TextScaler scaler) {
    final w = math.max(1.0, width - _pad.horizontal);
    double h(String text, TextStyle style) {
      final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: w);
      final r = tp.height;
      tp.dispose();
      return r;
    }

    const ink = Color(0xFFFFFFFF);
    return _pad.vertical +
        h(b.shownTitle, serif(20, 24, ink)) +
        (b.from.isEmpty ? 0 : h(Strings.from(b.from), serif(15, 22, ink, italic: true))) +
        (b.draft ? h(Strings.notReviewedNote, sans(13, 18, ink)) : 0);
  }

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = widget.blessing;
    final cur = widget.current;
    const fade = Duration(milliseconds: 300);
    final dim = Color.lerp(p.ground, p.light, .36)!;
    final num = sans(13, 24, cur ? p.ink2 : p.ink3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      button: true,
      label: '${b.longDate}. ${b.shownTitle}${b.from.isEmpty ? '' : '. ${Strings.from(b.from)}'}${b.draft ? '. ${Strings.notReviewedNote}' : ''}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: p.ink.withValues(alpha: _down ? .05 : 0),
          padding: _Row._pad,
          child: Stack(clipBehavior: Clip.none, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedDefaultTextStyle(duration: fade, style: serif(20, 24, cur ? p.ink : p.ink2), child: Text(b.shownTitle)),
              if (b.from.isNotEmpty)
                AnimatedDefaultTextStyle(
                  duration: fade,
                  style: serif(15, 22, cur ? p.light : p.ink3, italic: true),
                  child: Text(Strings.from(b.from)),
                ),
              if (b.draft) Text(Strings.notReviewedNote, key: Key('row-draft-${b.id}'), style: sans(13, 18, p.light.withValues(alpha: .8))),
            ]),
            Positioned(
              left: 16 - 112,
              top: 0,
              width: 54,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // the day and month stay on one line in the narrow date column, shrinking at large text sizes
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AnimatedDefaultTextStyle(duration: fade, style: num, child: Text(Strings.dayMonth(b.local), textAlign: TextAlign.right)),
                ),
                if (widget.showYear)
                  Transform.translate(
                    offset: const Offset(0, -4),
                    child: Text('${b.local.year}', style: sans(11, 14, p.ink3).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
              ]),
            ),
            Positioned(
              left: 84.5 - 112,
              top: 16.5 - 8,
              width: 7,
              height: 7,
              child: AnimatedScale(
                scale: cur ? 1.5 : 1,
                duration: const Duration(milliseconds: 350),
                curve: easeOut,
                child: AnimatedContainer(
                  duration: fade,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.lit ? p.light : dim,
                    boxShadow: cur
                        ? [BoxShadow(color: p.light.withValues(alpha: .18), spreadRadius: 5), BoxShadow(color: p.ground, spreadRadius: 2)]
                        : [BoxShadow(color: p.ground, spreadRadius: 3)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
