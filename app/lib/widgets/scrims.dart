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
