import 'package:flutter/widgets.dart';

/// Text that wraps into lines of similar length, as CSS `text-wrap: balance`
/// does: the fewest lines the full width needs, then the narrowest width that
/// still fits in that many lines. Keeps a title from leaving one word alone on
/// its last line ("Healing, the night / of the fever").
class BalancedText extends StatelessWidget {
  const BalancedText(this.data, {super.key, required this.style, this.textKey, this.textAlign = TextAlign.start});

  final String data;
  final TextStyle style;
  final TextAlign textAlign;

  /// Key for the inner [Text], so tests can find it as they would a plain one.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final max = box.maxWidth;
      var width = max;
      if (max.isFinite) {
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
