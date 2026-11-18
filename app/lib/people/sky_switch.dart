import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';

/// The switch at the top left of home: whose sky is showing ("For me", "For Emma") and a small
/// chevron, in a capsule of glass drawn by the app itself, so it sits over the live sky the same way
/// on iPhone and Android: the sky behind it blurred, a soft edge, a faint light along its top. Its
/// fill and its pressed state are the "New blessing" pill's. A tap opens the menu ([onTap]).
class SkySwitch extends StatefulWidget {
  const SkySwitch({super.key, required this.palette, required this.label, required this.onTap});

  final Palette palette;

  /// "For me", "For Emma".
  final String label;
  final VoidCallback onTap;

  @override
  State<SkySwitch> createState() => _SkySwitchState();
}

class _SkySwitchState extends State<SkySwitch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      label: Strings.skySwitchLabel(widget.label),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: const Duration(milliseconds: 200),
          curve: easeOut,
          child: DecoratedBox(
            // a shadow so faint it reads only as the glass standing off the sky
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AnimatedContainer(
                  key: const Key('sky-switch-glass'),
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: p.ink.withValues(alpha: _down ? .15 : .09),
                    border: Border.all(color: p.ink.withValues(alpha: .16), width: .75),
                  ),
                  // the faint highlight: light caught along the top edge, gone by the middle
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [p.ink.withValues(alpha: .12), p.ink.withValues(alpha: .02), p.ink.withValues(alpha: 0)],
                        stops: const [0, .5, 1],
                      ),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.fromLTRB(17, 6, 14, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.label,
                              key: const Key('sky-switch-label'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: serif(23, 28, p.ink, tracking: -.008),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: SizedBox(width: 11, height: 7, child: CustomPaint(painter: _Chevron(p.ink2))),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chevron extends CustomPainter {
  _Chevron(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * .06, h * .1)
        ..lineTo(w * .5, h * .9)
        ..lineTo(w * .94, h * .1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Chevron old) => old.color != color;
}
