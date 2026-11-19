import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// A small pull-down menu drawn in Flutter, as close to iPhone's own (ios/Runner/LanguageMenu.swift)
/// as Flutter allows: it grows from the control that opened it, each choice a row, the chosen one
/// ticked; a tap outside or Back closes it unchanged. Used where iPhone has its native menu
/// (Android, and anywhere without the native side), and for the home's switch between skies on
/// both (people/sky_switch.dart).
///
/// Returns the chosen code, or null when closed without a choice.
Future<String?> showPullDown(
  BuildContext context, {
  required Palette palette,
  required List<(String, String)> choices,
  required String selected,
  String? barrierLabel,
}) =>
    showPullDownItems(
      context,
      palette: palette,
      items: [for (final c in choices) PullDownItem(code: c.$1, label: c.$2, ticked: c.$1 == selected)],
      barrierLabel: barrierLabel,
    );

/// What a row of the menu shows on its left.
enum PullDownMark { none, plus }

/// One row of a pull-down: its words, an optional quieter line under them, and a tick when it is
/// the one chosen. [groupStart]: a wider gap above it, as iPhone's menus separate their sections.
class PullDownItem {
  const PullDownItem({
    required this.code,
    required this.label,
    this.sub,
    this.ticked = false,
    this.mark = PullDownMark.none,
    this.groupStart = false,
    this.semantics,
  });

  final String code, label;
  final String? sub;
  final bool ticked, groupStart;
  final PullDownMark mark;

  /// What VoiceOver reads, when it is more than the label and the line under it.
  final String? semantics;
}

/// Where the menu sits against the control: centred under it (as iPhone's own menu), or from its
/// leading edge (a control at the screen's left, as the home's capsule).
enum PullDownAlign { center, start }

/// [showPullDown] with rows of any kind. [width]: the menu's own width (kept on screen).
Future<String?> showPullDownItems(
  BuildContext context, {
  required Palette palette,
  required List<PullDownItem> items,
  String? barrierLabel,
  double width = 230,
  PullDownAlign align = PullDownAlign.center,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final anchor = box == null || overlay == null
      ? Rect.zero
      : Rect.fromPoints(box.localToGlobal(Offset.zero, ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
  return Navigator.of(context).push(_PullDownRoute(
    palette: palette,
    items: items,
    anchor: anchor,
    label: barrierLabel ?? '',
    width: width,
    align: align,
  ));
}

class _PullDownRoute extends PopupRoute<String> {
  _PullDownRoute({required this.palette, required this.items, required this.anchor, required this.label, required this.width, required this.align});

  final Palette palette;
  final List<PullDownItem> items;
  final Rect anchor;
  final String label;
  final double width;
  final PullDownAlign align;

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

  /// The height the rows will take, estimated before layout (to choose above or below).
  double _estimate(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    var h = 0.0;
    for (final i in items) {
      h += (i.sub == null ? 46 : 62) * math.max(1, scale) + (i.groupStart ? 8 : 0);
    }
    return h;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // large text: the whole width between the margins, so words are not stacked one to a line
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 > largeText;
    final w = large ? size.width - 32 : math.min(width, size.width - 32);
    final height = _estimate(context);
    // below the control if it fits, else above; kept on screen (and scrolled inside when it is
    // taller than the room there is)
    final roomBelow = size.height - pad.bottom - 8 - (anchor.bottom + 6);
    final below = height <= roomBelow || roomBelow >= anchor.top - pad.top - 14;
    final top = below ? anchor.bottom + 6 : math.max(pad.top + 8, anchor.top - 6 - height);
    final maxHeight = below ? roomBelow : anchor.top - 6 - top;
    final x = large ? 16.0 : align == PullDownAlign.start ? anchor.left : anchor.center.dx - w / 2;
    final left = x.clamp(16.0, math.max(16.0, size.width - w - 16)).toDouble();
    final p = palette;
    final curve = CurvedAnimation(parent: animation, curve: easeOut, reverseCurve: Curves.easeIn);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (i > 0) {
        rows.add(it.groupStart ? Container(height: 8, color: p.ground.withValues(alpha: .35)) : Container(height: .5, color: p.ink.withValues(alpha: .10)));
      }
      rows.add(_Row(
        key: Key('pull-down-${it.code}'),
        palette: p,
        item: it,
        height: 46,
        onTap: () => Navigator.of(context).pop(it.code),
      ));
    }
    final origin = switch ((below, align)) {
      (true, PullDownAlign.start) => Alignment.topLeft,
      (false, PullDownAlign.start) => Alignment.bottomLeft,
      (true, PullDownAlign.center) => Alignment.topCenter,
      (false, PullDownAlign.center) => Alignment.bottomCenter,
    };
    return Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: w,
        child: FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: .85, end: 1.0).animate(curve),
            alignment: origin,
            child: Container(
              key: const Key('pull-down'),
              constraints: BoxConstraints(maxHeight: math.max(46, maxHeight)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                // the sky shows through, softened, as through iPhone's own menus
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.raised.withValues(alpha: .86),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: p.ink.withValues(alpha: .08)),
                    ),
                    // taller than the room: it scrolls, and its bar shows that it does
                    child: _Scrolling(
                      palette: p,
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Text scaled past this (×1.3) is large: the menu takes the screen's width.
const largeText = 1.3;

class _Scrolling extends StatefulWidget {
  const _Scrolling({required this.palette, required this.child});
  final Palette palette;
  final Widget child;

  @override
  State<_Scrolling> createState() => _ScrollingState();
}

class _ScrollingState extends State<_Scrolling> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawScrollbar(
        controller: _scroll,
        thumbVisibility: true,
        thickness: 3,
        radius: const Radius.circular(1.5),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
        thumbColor: widget.palette.ink.withValues(alpha: .35),
        child: SingleChildScrollView(controller: _scroll, physics: const ClampingScrollPhysics(), child: widget.child),
      );
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.palette, required this.item, required this.height, required this.onTap});
  final Palette palette;
  final PullDownItem item;
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
    final it = widget.item;
    final mark = switch (it.mark) {
      PullDownMark.plus => SizedBox(width: 14, height: 14, child: CustomPaint(painter: _Plus(p.ink))),
      PullDownMark.none => it.ticked ? SizedBox(width: 14, height: 14, child: CustomPaint(painter: _Tick(p.ink))) : null,
    };
    return Semantics(
      button: true,
      selected: it.ticked,
      label: it.semantics ?? [it.label, ?it.sub].join('. '),
      excludeSemantics: true,
      onTap: widget.onTap,
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
          // the tick or plus beside the first line of the words; at most two lines each, so no row
          // grows past the screen at the largest text
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              key: const Key('pull-down-mark'),
              width: 26,
              height: MediaQuery.textScalerOf(context).scale(16) * 21 / 16,
              child: mark == null ? null : Align(alignment: Alignment.centerLeft, child: mark),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(it.label, key: const Key('pull-down-label'), style: sans(16, 21, p.ink), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (it.sub != null) ...[
                  const SizedBox(height: 1),
                  Text(it.sub!, key: const Key('pull-down-sub'), style: sans(13, 17, p.ink2), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The tick (or the plus) a row shows on its left, on its own: the glass menu of home's capsule
/// draws its rows with the same marks (people/sky_switch.dart).
class PullDownMarkGlyph extends StatelessWidget {
  const PullDownMarkGlyph({super.key, required this.mark, required this.ticked, required this.color});
  final PullDownMark mark;
  final bool ticked;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: switch (mark) {
          PullDownMark.plus => CustomPaint(painter: _Plus(color)),
          PullDownMark.none => ticked ? CustomPaint(painter: _Tick(color)) : null,
        },
      );
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

class _Plus extends CustomPainter {
  _Plus(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w / 2, h * .06), Offset(w / 2, h * .94), paint);
    canvas.drawLine(Offset(w * .06, h / 2), Offset(w * .94, h / 2), paint);
  }

  @override
  bool shouldRepaint(_Plus old) => old.color != color;
}
