import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// A small pull-down menu drawn in Flutter, as close to iPhone's own (ios/Runner/LanguageMenu.swift)
/// as Flutter allows: it grows from the control that opened it, each choice a row, the chosen one
/// ticked; a tap outside or Back closes it unchanged. Used where iPhone has its native menu
/// (Android, and anywhere without the native side).
///
/// Returns the chosen code, or null when closed without a choice.
Future<String?> showPullDown(
  BuildContext context, {
  required Palette palette,
  required List<(String, String)> choices,
  required String selected,
  String? barrierLabel,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final anchor = box == null || overlay == null
      ? Rect.zero
      : Rect.fromPoints(box.localToGlobal(Offset.zero, ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
  return Navigator.of(context).push(_PullDownRoute(
    palette: palette,
    choices: choices,
    selected: selected,
    anchor: anchor,
    label: barrierLabel ?? '',
  ));
}

class _PullDownRoute extends PopupRoute<String> {
  _PullDownRoute({required this.palette, required this.choices, required this.selected, required this.anchor, required this.label});

  final Palette palette;
  final List<(String, String)> choices;
  final String selected;
  final Rect anchor;
  final String label;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const width = 230.0, row = 46.0;
    final height = choices.length * row;
    // below the control if it fits, else above; kept on screen
    final below = anchor.bottom + 6 + height <= size.height - pad.bottom - 8;
    final top = below ? anchor.bottom + 6 : math.max(pad.top + 8, anchor.top - 6 - height);
    // centred under the control, as iPhone's menu is
    final left = (anchor.center.dx - width / 2).clamp(16.0, math.max(16.0, size.width - width - 16)).toDouble();
    final p = palette;
    final curve = CurvedAnimation(parent: animation, curve: easeOut, reverseCurve: Curves.easeIn);
    return Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: width,
        child: FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: .85, end: 1.0).animate(curve),
            alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
            child: Container(
              key: const Key('pull-down'),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: p.ink.withValues(alpha: .08)),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < choices.length; i++) ...[
                  if (i > 0) Container(height: .5, color: p.ink.withValues(alpha: .10)),
                  _Row(
                    key: Key('pull-down-${choices[i].$1}'),
                    palette: p,
                    label: choices[i].$2,
                    ticked: choices[i].$1 == selected,
                    height: row - (i > 0 ? .5 : 0),
                    onTap: () => Navigator.of(context).pop(choices[i].$1),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.palette, required this.label, required this.ticked, required this.height, required this.onTap});
  final Palette palette;
  final String label;
  final bool ticked;
  final double height;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      selected: widget.ticked,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.height),
          color: p.ink.withValues(alpha: _down ? .08 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            SizedBox(width: 26, child: widget.ticked ? Align(alignment: Alignment.centerLeft, child: SizedBox(width: 14, height: 14, child: CustomPaint(painter: _Tick(p.ink)))) : null),
            Expanded(child: Text(widget.label, style: sans(16, 21, p.ink))),
          ]),
        ),
      ),
    );
  }
}

class _Tick extends CustomPainter {
  _Tick(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * .08, h * .55)
        ..lineTo(w * .38, h * .85)
        ..lineTo(w * .92, h * .15),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Tick old) => old.color != color;
}
