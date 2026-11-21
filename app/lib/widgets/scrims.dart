import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Darkens the top of the sky so words stay readable over its brightest parts.
class TopScrim extends StatelessWidget {
  const TopScrim({super.key, required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final g = palette.ground;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [g.withValues(alpha: .82), g.withValues(alpha: .5), g.withValues(alpha: 0)],
            stops: const [0, .5, 1],
          ),
        ),
      ),
    );
  }
}

/// The same at the bottom; its height is set by whoever places it.
class BottomScrim extends StatelessWidget {
  const BottomScrim({super.key, required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final g = palette.ground;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [g.withValues(alpha: .94), g.withValues(alpha: .86), g.withValues(alpha: .5), g.withValues(alpha: 0)],
            stops: const [0, .38, .72, 1],
          ),
        ),
      ),
    );
  }
}

/// Over a page that scrolls under the status bar and a back button: once its words have scrolled up
/// into that strip, the night closes over it, so nothing reads through behind the clock or the
/// arrow. At rest (nothing scrolled) it is not there, and the page looks as it always has.
class ScrolledUnderShade extends StatefulWidget {
  const ScrolledUnderShade({super.key, required this.palette, required this.solid, required this.child});
  final Palette palette;

  /// How far down the strip is fully shaded (the bottom of the back button); it fades out below.
  final double solid;

  /// The scrolling page.
  final Widget child;

  @override
  State<ScrolledUnderShade> createState() => _ScrolledUnderShadeState();
}

class _ScrolledUnderShadeState extends State<ScrolledUnderShade> {
  double _shown = 0;

  bool _scrolled(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final shown = (n.metrics.pixels / 24).clamp(0.0, 1.0);
    if (shown != _shown) setState(() => _shown = shown);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.palette.ground;
    const fade = 24.0;
    final height = widget.solid + fade;
    return NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: height,
          child: IgnorePointer(
            child: Opacity(
              opacity: _shown,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [g, g, g.withValues(alpha: 0)],
                    stops: [0, widget.solid / height, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
