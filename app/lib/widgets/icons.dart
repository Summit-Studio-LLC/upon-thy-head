import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The prototype's stroke icons, drawn on a 24-unit grid.
enum Glyph {
  list, sky, forward, older, newer, upDown, play, pause, back10, cross, more, lock, share,
  // the first run's permission rows
  microphone, writing, location, faceId,
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

    switch (icon) {
      case Glyph.list:
        for (final y in [7.0, 12.0, 17.0]) {
          poly([9, y, 20, y]);
          canvas.drawCircle(Offset(4.5, y), 1.1, Paint()..color = color);
        }
      case Glyph.sky:
        final dot = Paint()..color = color;
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
