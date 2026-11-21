import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'buttons.dart';
import 'measure.dart';
import 'whole_words.dart';

/// The prototype's `.sheet`: a raised panel rising from the bottom edge.
/// With [barrier], the rest of the screen dims and a tap on it calls [onDismiss].
class Sheet extends StatefulWidget {
  const Sheet({
    super.key,
    required this.palette,
    required this.on,
    required this.label,
    required this.child,
    this.panelKey,
    this.barrier = false,
    this.onDismiss,
  });

  final Palette palette;
  final bool on, barrier;
  final String label;
  final Widget child;
  final Key? panelKey;
  final VoidCallback? onDismiss;

  /// A sheet is up somewhere: the edge swipe back does nothing then.
  static bool get anyUp => _up.isNotEmpty;
  static final Set<_SheetState> _up = {};

  @override
  State<Sheet> createState() => _SheetState();
}

class _SheetState extends State<Sheet> {
  void _track() => widget.on ? Sheet._up.add(this) : Sheet._up.remove(this);

  @override
  void initState() {
    super.initState();
    _track();
  }

  @override
  void didUpdateWidget(Sheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _track();
  }

  @override
  void dispose() {
    Sheet._up.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette, on = widget.on, barrier = widget.barrier, label = widget.label;
    final child = widget.child, panelKey = widget.panelKey, onDismiss = widget.onDismiss;
    final p = palette;
    // the keyboard pushes the sheet up
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    // Reduce Motion: it is simply there, and simply gone
    final still = MediaQuery.of(context).disableAnimations;
    // never taller than the screen below the status bar: at the largest text sizes the content
    // scrolls inside the panel instead of running off the top (found on Android at font 2.0 with
    // the display size raised; the same holds for iPhone's largest sizes)
    final wide = MediaQuery.sizeOf(context).width >= Widths.cardFrom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final room = MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).top - 12 - 20 - 38 - inset - (wide ? math.max(20.0, safeBottom) : 0);
    // off, it is slid below the screen and still built: out of VoiceOver's reach as well as the finger's
    final panel = ExcludeSemantics(
      excluding: !on,
      child: IgnorePointer(
        ignoring: !on,
        child: AnimatedSlide(
          offset: on ? Offset.zero : const Offset(0, 1.04),
          duration: still ? Duration.zero : const Duration(milliseconds: 500),
          curve: easeOut,
          // a wide screen (an iPad, not a Split View third): a card of its own width, lifted off the
          // bottom edge and rounded all round; a phone's sheet is as it was
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: Padding(
            padding: EdgeInsets.only(bottom: wide ? math.max(20.0, safeBottom) : 0),
            child: Container(
            key: panelKey,
            width: wide ? Widths.card : null,
            padding: EdgeInsets.fromLTRB(24, 20, 24, (wide ? 28 : 38) + inset),
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: wide ? BorderRadius.circular(28) : const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [BoxShadow(color: p.ink.withValues(alpha: .07), offset: const Offset(0, -1))],
            ),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              label: label,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: room > 0 ? room : 0),
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
          ),
          ),
        ),
      ),
    );
    if (!barrier) return panel;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          ignoring: !on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: still ? Duration.zero : const Duration(milliseconds: 400),
              curve: easeOut,
              child: ColoredBox(color: p.ground.withValues(alpha: .45)),
            ),
          ),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: panel),
    ]);
  }
}

/// A question with a destructive answer and a safe one, as "Discard this recording?".
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.palette,
    required this.on,
    required this.title,
    required this.body,
    required this.dangerLabel,
    required this.safeLabel,
    required this.onDanger,
    required this.onSafe,
    this.panelKey,
    this.dangerKey,
    this.safeKey,
    this.barrier = false,
    this.note,
    this.noteKey,
  });

  final Palette palette;
  final bool on, barrier;
  final String title, body, dangerLabel, safeLabel;

  /// One more line under the body, quieter (or what went wrong, said plainly).
  final String? note;
  final Key? noteKey;
  final VoidCallback onDanger, onSafe;
  final Key? panelKey, dangerKey, safeKey;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Sheet(
      palette: p,
      on: on,
      label: title,
      panelKey: panelKey,
      barrier: barrier,
      onDismiss: onSafe,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        WholeWords(title, maxScale: titleMaxScale, style: serif(22, 28, p.ink)),
        const SizedBox(height: 6),
        Text(body, style: sans(15, 22, p.ink2)),
        if (note != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(note!, key: noteKey, style: sans(14, 20, p.ink3))),
        ],
        const SizedBox(height: 20),
        SheetButtons(
          palette: p,
          left: PillBtn(key: dangerKey, label: dangerLabel, palette: p, kind: PillKind.danger, height: 48, fontSize: 16, onTap: onDanger),
          right: PillBtn(key: safeKey, label: safeLabel, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: onSafe),
        ),
      ]),
    );
  }
}

/// Two buttons side by side, 8 apart, as the prototype's `.sheet .actions`.
class SheetButtons extends StatelessWidget {
  const SheetButtons({super.key, required this.palette, required this.left, required this.right});
  final Palette palette;
  final Widget left, right;

  @override
  Widget build(BuildContext context) =>
      Row(children: [Expanded(child: left), const SizedBox(width: 8), Expanded(child: right)]);
}
