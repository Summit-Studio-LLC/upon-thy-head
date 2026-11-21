import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The highest home's foot (the caption, the ruler and New blessing) may reach on a screen [height]
/// tall: below the ring. Home's sky puts the light in focus, the ring's lowest point, at two fifths
/// of the way down (SkyView.home's cy of .2); under it hang the neighbours' dates and the light's own
/// glow, so a margin below that.
double ringFloor(double height) => height * .4 + 40;

/// The caption of the blessing in focus, kept to the room it is given: at large text it grows only
/// until its date, title and giver fill that room, then stops (found 2026-11-21: at the largest size
/// on iPhone the caption ran up over the ring and its lights). When it fits at the person's own
/// size, as it always does at the usual sizes, it is left exactly as it was. The words given here
/// are the caption's own, with the styles and gaps of home's caption, to measure it.
class CaptionRoom extends StatelessWidget {
  const CaptionRoom({super.key, required this.date, required this.title, required this.from, required this.child});

  final String date, title;
  final String? from;
  final Widget child;

  /// The caption's words beside the read button: the caption's 24 and 16 at the sides, the 8 and the
  /// button's 44 after them.
  static const double _beside = 24 + 16 + 8 + 44;

  /// How tall the caption is at text size [scale], [width] wide.
  double _tall(double scale, double width) {
    final w = math.max(1.0, width - _beside);
    double lines(String text, TextStyle style) {
      final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.linear(scale))
        ..layout(maxWidth: w);
      final h = tp.height;
      tp.dispose();
      return h;
    }

    const ink = Color(0xFF000000);
    return lines(date, sans(13, 18, ink, tracking: .005)) +
        6 +
        lines(title, serif(30, 34, ink, tracking: -.012)) +
        (from == null ? 0 : 4 + lines(from!, serif(18, 26, ink, italic: true)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (!box.maxHeight.isFinite || !box.maxWidth.isFinite) return child;
      final own = MediaQuery.textScalerOf(context).scale(16) / 16;
      // a point to spare, for rounding
      final room = box.maxHeight - 1;
      if (_tall(own, box.maxWidth) <= room) return child;
      // the largest size that fits, down to a little under the usual size on the smallest screens
      var lo = math.min(own, .7), hi = own;
      for (var i = 0; i < 12 && hi - lo > .01; i++) {
        final mid = (lo + hi) / 2;
        _tall(mid, box.maxWidth) <= room ? lo = mid : hi = mid;
      }
      return MediaQuery.withClampedTextScaling(maxScaleFactor: lo, child: child);
    });
  }
}
