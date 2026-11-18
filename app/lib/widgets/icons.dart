import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The prototype's stroke icons, drawn on a 24-unit grid.
enum Glyph {
  list, sky, forward, older, newer, upDown, play, pause, back10, cross, more, lock, share,
  // the first run's permission rows
  microphone, writing, location, faceId,
  // Android's notifications row (docs/android-plan.md 9)
  bell,
  // sending a blessing (design/share/src/app.js): the blessing (hands over a head), the words as
  // text, a page (PDF), the blessing file, a link, copy, and no internet
  blessing, text, pdf, file, link, copy, offline,
  // entering a past blessing (design/entry-and-rings): a written page, a page being written on, a
  // calendar, and the clipboard
  page, enter, calendar, clipboard,
}

/// Vertical corrections, in grid units, so glyphs shown together sit on one line.
const _optical = {Glyph.microphone: .5, Glyph.writing: -1.0};

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);
  final Glyph icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    // each glyph's own optical centre on the grid's middle line (the permission rows sit them side
    // by side): the microphone's capsule is heavy at the top of a box it fills from 3 to 20.5, so it
    // comes down; the writing's lines run 6 to 20 with the pencil low, so it goes up
    final nudge = _optical[icon];
    if (nudge != null) canvas.translate(0, nudge);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void poly(List<double> xy) {
      final path = Path()..moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        path.lineTo(xy[i], xy[i + 1]);
      }
      canvas.drawPath(path, paint);
    }

    void svg(String d) => canvas.drawPath(svgPath(d), paint);
    final dot = Paint()..color = color;
    switch (icon) {
      case Glyph.blessing:
        // hands as four arcs over the head, with three dots for the fingertips' light
        const r = 11.5;
        for (final (a, b) in [(-68.0, -50.3), (-29.7, -13.0), (13.0, 29.7), (50.3, 68.0)]) {
          // angles from straight up, clockwise
          final s0 = (a - 90) * math.pi / 180, sweep = (b - a) * math.pi / 180;
          canvas.drawArc(Rect.fromCircle(center: const Offset(12, 17), radius: r), s0, sweep, false, paint);
        }
        canvas.drawCircle(const Offset(12, 5.5), 2, dot);
        canvas.drawCircle(const Offset(4.61, 8.19), 1.4, dot);
        canvas.drawCircle(const Offset(19.39, 8.19), 1.4, dot);
        canvas.drawCircle(const Offset(12, 16), 4.75, paint);
      case Glyph.text:
        svg('M5 6.5h14M5 10.5h14M5 14.5h14M5 18.5h8.5');
      case Glyph.pdf:
        svg('M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z');
        svg('M13.5 3.5v5h5');
      case Glyph.file:
        svg('M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z');
        svg('M13.5 3.5v5h5');
        svg('M7.75 16.5Q12 11.5 16.25 16.5');
        canvas.drawCircle(const Offset(12, 14), 1.35, dot);
        canvas.drawCircle(const Offset(9.45, 14.9), .95, dot);
        canvas.drawCircle(const Offset(14.55, 14.9), .95, dot);
      case Glyph.page:
        svg('M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z');
        svg('M13.5 3.5v5h5');
        svg('M8.5 12.5h7M8.5 16h7');
      case Glyph.enter:
        svg('M15.5 20.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5h6.5l5 5v2.5');
        svg('M13.5 3.5v5h5');
        svg('M8.5 12.5h5M8.5 16h3');
        svg('M14.5 20.5l.5-2.5 4.75-4.75a1.4 1.4 0 0 1 2 2L17 20z');
      case Glyph.calendar:
        canvas.drawRRect(RRect.fromLTRBR(4, 5.5, 20, 20, const Radius.circular(2.5)), paint);
        svg('M4 10h16M8.5 3.5v4M15.5 3.5v4');
      case Glyph.clipboard:
        svg('M9 5H7.5A1.5 1.5 0 0 0 6 6.5v13A1.5 1.5 0 0 0 7.5 21h9a1.5 1.5 0 0 0 1.5-1.5v-13A1.5 1.5 0 0 0 16.5 5H15');
        canvas.drawRRect(RRect.fromLTRBR(9, 3.5, 15, 6.5, const Radius.circular(1)), paint);
        svg('M9.5 11h5M9.5 14.5h5M9.5 18h3');
      case Glyph.link:
        svg('M10.25 13.75a3.75 3.75 0 0 0 5.3 0l3-3a3.75 3.75 0 0 0-5.3-5.3l-.85.85');
        svg('M13.75 10.25a3.75 3.75 0 0 0-5.3 0l-3 3a3.75 3.75 0 0 0 5.3 5.3l.85-.85');
      case Glyph.copy:
        canvas.drawRRect(RRect.fromLTRBR(9, 9, 19.5, 20.5, const Radius.circular(2)), paint);
        svg('M15 9V5.75A1.75 1.75 0 0 0 13.25 4h-7A1.75 1.75 0 0 0 4.5 5.75v7.5A1.75 1.75 0 0 0 6.25 15H9');
      case Glyph.offline:
        svg('M7.25 18h9.5a3.75 3.75 0 0 0 .9-7.4A5.75 5.75 0 0 0 6.6 9.3 4.35 4.35 0 0 0 7.25 18z');
        svg('M4 4.5l16 15');
      case Glyph.list:
        for (final y in [7.0, 12.0, 17.0]) {
          poly([9, y, 20, y]);
          canvas.drawCircle(Offset(4.5, y), 1.1, Paint()..color = color);
        }
      case Glyph.sky:
        canvas.drawCircle(const Offset(12, 12), 1.6, dot);
        for (final (x, y) in [(5.5, 7.0), (18.0, 6.0), (17.5, 17.5), (6.5, 16.5)]) {
          canvas.drawCircle(Offset(x, y), 1, dot);
        }
      case Glyph.forward:
        poly([10, 6, 16, 12, 10, 18]);
      case Glyph.older:
        poly([14.5, 6, 8.5, 12, 14.5, 18]);
      case Glyph.newer:
        poly([9.5, 6, 15.5, 12, 9.5, 18]);
      case Glyph.upDown:
        // a choice that opens a menu, as iOS marks a pop-up button
        poly([7.5, 9.5, 12, 5, 16.5, 9.5]);
        poly([7.5, 14.5, 12, 19, 16.5, 14.5]);
      case Glyph.play:
        final fill = Paint()..color = color;
        canvas.drawPath(
          Path()
            ..moveTo(8, 5.5)
            ..lineTo(18.5, 12)
            ..lineTo(8, 18.5)
            ..close(),
          fill..strokeJoin = StrokeJoin.round,
        );
      case Glyph.pause:
        final fill = Paint()..color = color;
        canvas.drawRRect(RRect.fromLTRBR(7, 5.5, 10.2, 18.5, const Radius.circular(1)), fill);
        canvas.drawRRect(RRect.fromLTRBR(13.8, 5.5, 17, 18.5, const Radius.circular(1)), fill);
      case Glyph.back10:
        // a turn backwards, with 10 inside
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 12.5), radius: 8), -1.9, -4.9 + 0.5, false, paint);
        poly([5.6, 3.6, 8.8, 5.2, 7.2, 8.3]);
        final tp = TextPainter(
          text: TextSpan(text: '10', style: TextStyle(fontFamily: 'CupertinoSystemText', fontSize: 7.5, fontWeight: FontWeight.w600, color: color)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(12 - tp.width / 2, 12.6 - tp.height / 2));
      case Glyph.cross:
        poly([7, 7, 17, 17]);
        poly([17, 7, 7, 17]);
      case Glyph.more:
        // three dots, drawn with the list's dot size so the two read as a pair
        final dot = Paint()..color = color;
        for (final x in [5.5, 12.0, 18.5]) {
          canvas.drawCircle(Offset(x, 12), 1.5, dot);
        }
      case Glyph.share:
        // iOS's square with an arrow, in the app's own stroke: an open-topped box, the arrow rising out of it
        poly([12, 3.75, 12, 14.25]);
        poly([8.5, 7.25, 12, 3.75, 15.5, 7.25]);
        canvas.drawPath(
          Path()
            ..moveTo(9.25, 9.75)
            ..lineTo(7.75, 9.75)
            ..arcToPoint(const Offset(6, 11.5), radius: const Radius.circular(1.75), clockwise: false)
            ..lineTo(6, 18.5)
            ..arcToPoint(const Offset(7.75, 20.25), radius: const Radius.circular(1.75), clockwise: false)
            ..lineTo(16.25, 20.25)
            ..arcToPoint(const Offset(18, 18.5), radius: const Radius.circular(1.75), clockwise: false)
            ..lineTo(18, 11.5)
            ..arcToPoint(const Offset(16.25, 9.75), radius: const Radius.circular(1.75), clockwise: false)
            ..lineTo(14.75, 9.75),
          paint,
        );
      case Glyph.lock:
        canvas.drawRRect(RRect.fromLTRBR(6, 11, 18, 19.5, const Radius.circular(2.5)), paint);
        canvas.drawPath(
          Path()
            ..moveTo(8.75, 11)
            ..lineTo(8.75, 8.25)
            ..arcToPoint(const Offset(15.25, 8.25), radius: const Radius.circular(3.25))
            ..lineTo(15.25, 11),
          paint,
        );
      case Glyph.microphone:
        // the capsule in its cradle, on a short stand
        canvas.drawRRect(RRect.fromLTRBR(9, 3, 15, 14, const Radius.circular(3)), paint);
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 11), radius: 6), 0, 3.14159, false, paint);
        poly([12, 17, 12, 20.5]);
        poly([9, 20.5, 15, 20.5]);
      case Glyph.writing:
        // speech recognition: lines of writing, and the pencil writing the last of them
        poly([4, 6, 20, 6]);
        poly([4, 11, 16.5, 11]);
        poly([4, 16, 10, 16]);
        canvas.drawPath(
          Path()
            ..moveTo(13, 20)
            ..lineTo(15.83, 19.29)
            ..lineTo(21.13, 13.99)
            ..lineTo(19.01, 11.87)
            ..lineTo(13.71, 17.17)
            ..close(),
          paint,
        );
        poly([13.71, 17.17, 15.83, 19.29]);
      case Glyph.bell:
        // a bell: its dome and flared rim, and the clapper below
        canvas.drawPath(
          Path()
            ..moveTo(5, 17)
            ..lineTo(19, 17)
            ..lineTo(17.5, 15)
            ..lineTo(17.5, 10)
            ..arcToPoint(const Offset(6.5, 10), radius: const Radius.circular(5.5), clockwise: false)
            ..lineTo(6.5, 15)
            ..close(),
          paint,
        );
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 18.5), radius: 2), 0, 3.14159, false, paint);
        poly([12, 3, 12, 4.5]);
      case Glyph.location:
        // the location arrow, as iOS draws "here", in outline
        canvas.drawPath(
          Path()
            ..moveTo(19.5, 4.5)
            ..lineTo(4.5, 11)
            ..lineTo(11.5, 12.5)
            ..lineTo(13, 19.5)
            ..close(),
          paint,
        );
      case Glyph.faceId:
        // the four corners, and a face inside them
        for (final (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
          Offset q(double x, double y) => Offset(12 + sx * (x - 12), 12 + sy * (y - 12));
          final a = q(3.5, 8), b = q(3.5, 6.5), c = q(6.5, 3.5), d = q(8, 3.5);
          canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..lineTo(b.dx, b.dy)
              ..arcToPoint(c, radius: const Radius.circular(3), clockwise: sx * sy > 0)
              ..lineTo(d.dx, d.dy),
            paint,
          );
        }
        poly([9, 8.75, 9, 10.25]);
        poly([15, 8.75, 15, 10.25]);
        poly([12.25, 8.75, 12.25, 13, 11.25, 13]);
        canvas.drawPath(
          Path()
            ..moveTo(9, 15.5)
            ..quadraticBezierTo(12, 17.75, 15, 15.5),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color;
}

/// The few SVG path commands the drawn icons use (M L H V A Q Z, absolute and relative), on the
/// same 24-unit grid.
Path svgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvAaQqZz]|-?(?:\d+\.?\d*|\.\d+)').allMatches(d).map((m) => m[0]!).toList();
  var i = 0, x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  var cmd = 'M';
  double n() => double.parse(tokens[i++]);
  bool isNum() => i < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[i]);
  while (i < tokens.length) {
    if (!isNum()) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'H':
        x = (rel ? x : 0) + n();
        path.lineTo(x, y);
      case 'V':
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'A':
        final rx = n(), ry = n(), rot = n(), large = n() != 0, sweep = n() != 0;
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.arcToPoint(Offset(x, y), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
      case 'Q':
        final cx = (rel ? x : 0) + n(), cy = (rel ? y : 0) + n();
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.quadraticBezierTo(cx, cy, x, y);
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        if (isNum()) cmd = 'L';
    }
  }
  return path;
}

/// A round 44-point button with one icon. Dims to .28 when [onTap] is null.
class IconBtn extends StatefulWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.color,
    required this.palette,
    required this.semantics,
    required this.onTap,
    this.filled = false,
    this.size = 44,
    this.iconSize = 24,
  });

  /// The round target and the icon in it (the changes sheet's steps are 36 and 20).
  final double size, iconSize;

  final Glyph icon;
  final Color color;
  final Palette palette;
  final String semantics;
  final VoidCallback? onTap;

  /// The caption's arrow sits on a faint disc.
  final bool filled;

  @override
  State<IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<IconBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ink = widget.palette.ink;
    final enabled = widget.onTap != null;
    final bg = widget.filled
        ? ink.withValues(alpha: _down ? .16 : .09)
        : ink.withValues(alpha: _down && enabled ? .14 : 0);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .28,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: CustomPaint(size: Size(widget.iconSize, widget.iconSize), painter: _IconPainter(widget.icon, widget.color)),
          ),
        ),
      ),
    );
  }
}


/// One icon on its own, drawn to fill its box.
class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.icon, {super.key, required this.color});
  final Glyph icon;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _IconPainter(icon, color));
}
