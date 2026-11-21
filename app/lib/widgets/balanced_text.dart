import 'package:flutter/widgets.dart';

import 'whole_words.dart';

/// Text that wraps into lines of similar length, as CSS `text-wrap: balance`
/// does: the fewest lines the full width needs, then the narrowest width that
/// still fits in that many lines. Keeps a title from leaving one word alone on
/// its last line ("Healing, the night / of the fever").
class BalancedText extends StatelessWidget {
  const BalancedText(this.data, {super.key, required this.style, this.textKey, this.textAlign = TextAlign.start, this.maxHeight, this.maxScale});

  final String data;
  final TextStyle style;
  final TextAlign textAlign;

  /// Key for the inner [Text], so tests can find it as they would a plain one.
  final Key? textKey;

  /// The most room it may take: at large text sizes it is drawn smaller until it fits (never larger
  /// than the person's own size).
  final double? maxHeight;

  /// The most it grows with the phone's text size, as a multiple of its size (titles:
  /// [titleMaxScale]). Whatever the size, no word is broken across lines.
  final double? maxScale;

  @override
  Widget build(BuildContext context) {
    var base = MediaQuery.textScalerOf(context);
    if (maxScale != null) base = base.clamp(maxScaleFactor: maxScale!);
    return LayoutBuilder(builder: (context, box) {
      var scaler = base;
      final max = box.maxWidth;
      var width = max;
      if (max.isFinite && maxHeight != null) {
        final fs = style.fontSize ?? 14;
        final full = scaler.scale(fs) / fs;
        double tall(double f) {
          final tp = TextPainter(text: TextSpan(text: data, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.linear(f))..layout(maxWidth: max);
          final h = tp.height;
          tp.dispose();
          return h;
        }

        if (tall(full) > maxHeight!) {
          var lo = .5, hi = full;
          for (var i = 0; i < 12 && hi - lo > .01; i++) {
            final mid = (lo + hi) / 2;
            tall(mid) > maxHeight! ? hi = mid : lo = mid;
          }
          scaler = TextScaler.linear(lo);
        }
      }
      if (max.isFinite) {
        scaler = wholeWordScaler(data, style, scaler, max, TextDirection.ltr);
        final tp = TextPainter(text: TextSpan(text: data, style: style), textDirection: TextDirection.ltr, textScaler: scaler);
        int lines(double w) {
          tp.layout(maxWidth: w);
          return tp.computeLineMetrics().length;
        }

        final n = lines(max);
        if (n > 1) {
          // binary search for the narrowest width that keeps n lines
          var lo = max / n * .8, hi = max;
          for (var i = 0; i < 14 && hi - lo > .5; i++) {
            final mid = (lo + hi) / 2;
            if (lines(mid) > n) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          width = hi.ceilToDouble();
        }
        tp.dispose();
      }
      final text = Text(data, key: textKey, style: style, textAlign: textAlign, textScaler: scaler);
      if (width >= max) return text;
      final align = switch (textAlign) {
        TextAlign.center => Alignment.topCenter,
        TextAlign.right || TextAlign.end => Alignment.topRight,
        _ => Alignment.topLeft,
      };
      return Align(alignment: align, widthFactor: textAlign == TextAlign.center ? null : 1, child: SizedBox(width: width, child: text));
    });
  }
}
