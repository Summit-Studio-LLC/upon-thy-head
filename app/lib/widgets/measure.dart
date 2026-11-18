import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Widths that keep the app's columns comfortable on an iPad. On a phone none of them is reached,
/// so nothing there moves.
abstract final class Widths {
  /// A reading page's words, review's fields, the first run.
  static const reading = 620.0;

  /// The Settings family of pages, the family pages, Your links.
  static const form = 600.0;

  /// A sheet or a confirmation, once the screen is wide enough to show it as a card.
  static const card = 560.0;

  /// Wider than this, a sheet is a card; narrower (every phone, a Split View third), it spans the screen.
  static const cardFrom = 700.0;

  /// Home's foot: the caption, the ruler and New blessing.
  static const foot = 600.0;

  /// The pills that span their column on a phone stop here.
  static const pill = 420.0;

  /// The side margin that keeps a column of [max] centred on a screen [width] wide, and never less
  /// than a phone's [phone] margin.
  static double side(double width, double phone, double max) => math.max(phone, (width - max) / 2);
}

/// Its child at most [max] wide, centred in the room it is given. The tree is the same at every
/// width (a narrow window widened, an iPad turned), so nothing inside it is rebuilt or loses what
/// was typed into it.
class Measure extends StatelessWidget {
  const Measure({super.key, this.max = Widths.reading, this.alignment = Alignment.topCenter, required this.child});
  final double max;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Align(
          alignment: alignment,
          heightFactor: box.hasBoundedHeight ? null : 1,
          // given a height (a page's layer), it fills it, as before; in a scrolled column, its own
          child: SizedBox(width: box.hasBoundedWidth ? math.min(box.maxWidth, max) : null, height: box.hasBoundedHeight ? box.maxHeight : null, child: child),
        ),
      );
}
