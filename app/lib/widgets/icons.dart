import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The prototype's stroke icons, drawn on a 24-unit grid.
enum Glyph { list, sky, forward, older, newer, upDown, play, pause, back10, cross, more, lock, share }

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);
  final Glyph icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
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
