import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How far a large serif title grows with the phone's text size. Titles start large, so at the
/// accessibility sizes they stop at twice their size; the words under them keep growing. Every
/// phone setting short of the accessibility sizes stays under this, so nothing there changes.
const double titleMaxScale = 2;

/// The text scale at which no word of [text] is wider than [maxWidth]: [scaler] itself when the
/// widest word already fits, a little smaller when it does not. Words are never broken mid-word.
TextScaler wholeWordScaler(String text, TextStyle style, TextScaler scaler, double maxWidth, TextDirection direction) {
  if (!maxWidth.isFinite || maxWidth <= 0) return scaler;
  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final tp = TextPainter(text: TextSpan(text: word, style: style), textScaler: scaler, textDirection: direction, maxLines: 1)..layout();
    widest = math.max(widest, tp.width);
    tp.dispose();
  }
  if (widest <= maxWidth) return scaler;
  final fs = style.fontSize ?? 14;
  return TextScaler.linear(scaler.scale(fs) / fs * maxWidth / widest * .98);
}

/// A [Text] that wraps only between words: where one word is wider than the room, the whole text
/// is drawn just small enough for it to fit. With [maxScale] (titles: [titleMaxScale]) it also
/// stops growing past that multiple of its size.
class WholeWords extends StatelessWidget {
  const WholeWords(
    this.data, {
    super.key,
    required this.style,
    this.textKey,
    this.textAlign,
    this.maxScale,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle style;

  /// Key for the inner [Text], so tests find it as they would a plain one.
  final Key? textKey;
  final TextAlign? textAlign;
  final double? maxScale;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    var scaler = MediaQuery.textScalerOf(context);
    if (maxScale != null) scaler = scaler.clamp(maxScaleFactor: maxScale!);
    return LayoutBuilder(builder: (context, box) {
      final s = wholeWordScaler(data, style, scaler, box.maxWidth, Directionality.of(context));
      return Text(data, key: textKey, style: style, textAlign: textAlign, textScaler: s, maxLines: maxLines, overflow: overflow);
    });
  }
}
