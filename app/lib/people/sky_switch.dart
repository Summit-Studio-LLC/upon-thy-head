import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/pull_down.dart';

/// The switch at the top left of home: whose sky is showing ("For me", "For Emma") and a small
/// chevron, in a capsule of liquid glass (package:liquid_glass_widgets), the sky bending through
/// it. A tap morphs the capsule into its menu, the package's glass menu: For me and each family
/// member with their count line and a tick on the one showing, then Add a family member and Manage
/// family ([menu]). A row tapped is passed to [onChosen]; a tap outside closes it unchanged.
///
/// The capsule's words stop growing at 1.6× the usual size; the menu's rows follow the person's
/// own text size, every line whole (wrapping, never "…"), and the menu scrolls when it is taller
/// than the screen.
class SkySwitch extends StatefulWidget {
  const SkySwitch({
    super.key,
    required this.palette,
    required this.label,
    required this.menu,
    required this.onChosen,
    this.onOpening,
    this.onClosed,
  });

  final Palette palette;

  /// "For me", "For Emma".
  final String label;

  /// The rows, read each time the menu opens.
  final List<PullDownItem> Function() menu;

  /// Before the menu opens: false keeps it shut (locked, or home busy with something else).
  final Future<bool> Function()? onOpening;

  /// The code of the row tapped.
  final ValueChanged<String> onChosen;

  /// The menu began to close, with a row chosen or without.
  final VoidCallback? onClosed;

  @override
  State<SkySwitch> createState() => _SkySwitchState();
}

/// The words of the capsule stop growing here.
const _capsuleMaxScale = 1.6;

class _SkySwitchState extends State<SkySwitch> {
  final _menu = GlassMenuController();
  List<PullDownItem> _items = const [];
  bool _opening = false;

  Future<void> _tap() async {
    if (_menu.isOpen) return _menu.close();
    if (_opening) return;
    _opening = true;
    try {
      final ok = await (widget.onOpening?.call() ?? Future.value(true));
      if (!ok || !mounted) return;
      setState(() => _items = widget.menu());
      // open once the rows are in, so the menu is sized for them
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _menu.open();
      });
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(16) / 16;
    // large text: the whole width between the margins, so words are not stacked one to a line
    final large = scale > largeText;
    final width = large ? mq.size.width - 32 : math.min(300.0, mq.size.width - 32);
    return GlassMenu(
      controller: _menu,
      items: [for (final it in _items) ..._row(it, scale, large, width)],
      menuWidth: width,
      menuAlignment: GlassMenuAlignment.topLeft,
      autoAdjustToScreen: true,
      menuPadding: const EdgeInsets.all(16),
      menuSemanticLabel: widget.label,
      // dim and quiet: no bright glare under the finger
      glowIntensity: 0,
      selectionColor: p.ink.withValues(alpha: .10),
      onClose: widget.onClosed,
      triggerBuilder: (context, _) => _capsule(context),
    );
  }

  List<Widget> _row(PullDownItem it, double scale, bool large, double menuWidth) {
    final p = widget.palette;
    final titleStyle = sans(16, 21, p.ink), subStyle = sans(13, 17, p.ink2);
    final mark = PullDownMarkGlyph(key: const Key('pull-down-mark'), mark: it.mark, ticked: it.ticked, color: p.ink);
    // The package draws a row's words on one line each (two at most for the name) and ends what
    // does not fit in "…": a count line naming a month ("Seis bendiciones desde junio de 2024")
    // at the usual size, and at large text the names, "Add a family member" and the count lines.
    // So whenever a row's words would not fit the package's lines, they are drawn here instead, in
    // the slot the package gives the tick, wide enough to fill the row (the menu's 12 each side,
    // the row's 16 each side, the package's 12 after the tick, one to spare), each line wrapping as
    // far as it needs and never cut short. The package's own words are kept but not seen, so a
    // screen reader still hears the name and then the count line, as before. A row that fits is
    // left to the package, as it always was.
    final slot = menuWidth - 24 - 32 - 12 - 1;
    int linesOf(String text, TextStyle style, double width) {
      final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.linear(scale))
        ..layout(maxWidth: math.max(1.0, width));
      final n = math.max(1, tp.computeLineMetrics().length);
      tp.dispose();
      return n;
    }

    // whether the package's own one line holds each: its words are as wide as the row less the
    // tick's 14 and the 12 after it
    final packageWidth = menuWidth - 24 - 32 - 14 - 12;
    final fits = linesOf(it.label, titleStyle, packageWidth) == 1 && (it.sub == null || linesOf(it.sub!, subStyle, packageWidth) == 1);
    final ownWords = large || !fits;
    // drawn here, they are as wide as the slot less the tick and the 12 after it
    final ownWidth = slot - 14 - 12;
    final titleLines = ownWords ? linesOf(it.label, titleStyle, ownWidth) : 1;
    final subLines = it.sub == null ? 0 : (ownWords ? linesOf(it.sub!, subStyle, ownWidth) : 1);
    // the row's height as drawn, so the menu is measured to fit its rows exactly
    final words = 21 * scale * titleLines + (it.sub == null ? 0 : 1 + 17 * scale * subLines);
    const hidden = Color(0x00000000);
    return [
      if (it.groupStart) const GlassMenuDivider(),
      GlassMenuItem(
        key: Key('pull-down-${it.code}'),
        title: it.label,
        subtitle: it.sub,
        maxLines: 1,
        height: math.max(44, 16 + words),
        titleStyle: ownWords ? titleStyle.copyWith(color: hidden) : titleStyle,
        subtitleStyle: ownWords ? subStyle.copyWith(color: hidden, fontSize: .01, height: 1) : subStyle,
        // the app's own tick and plus, where iPhone's menus put the tick: before the name
        icon: !ownWords
            ? mark
            : SizedBox(
                key: Key('pull-down-words-${it.code}'),
                width: slot,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // beside the name's first line
                  Padding(padding: EdgeInsets.only(top: math.max(0, (21 * scale - 14) / 2)), child: mark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.label, style: titleStyle),
                      if (it.sub != null) ...[
                        const SizedBox(height: 1),
                        Text(it.sub!, style: subStyle),
                      ],
                    ]),
                  ),
                ]),
              ),
        iconSize: 14,
        semanticsSelected: it.ticked,
        semanticLabel: it.semantics ?? it.label,
        onTap: () => widget.onChosen(it.code),
      ),
    ];
  }

  Widget _capsule(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: Strings.skySwitchLabel(widget.label),
      excludeSemantics: true,
      onTap: () => unawaited(_tap()),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _capsuleMaxScale,
        child: GlassButton.custom(
          key: const Key('sky-switch-glass'),
          onTap: () => unawaited(_tap()),
          excludeFromSemantics: true,
          shape: const LiquidRoundedRectangle(borderRadius: 999),
          // a gentle give under the finger, as the capsule is wide
          stretch: .2,
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
