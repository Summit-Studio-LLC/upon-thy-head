import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'measure.dart';
import 'swap_text.dart';

/// A word for a button, as the recording screen's Close and Discard.
class TextBtn extends StatefulWidget {
  const TextBtn({super.key, required this.label, required this.palette, required this.onTap});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<TextBtn> createState() => _TextBtnState();
}

class _TextBtnState extends State<TextBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: sans(17, 22, _down ? p.ink : p.ink2),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

enum PillKind { primary, quiet, tonal, danger }

/// The prototype's `.btn`: a full-width pill.
class PillBtn extends StatefulWidget {
  const PillBtn({
    super.key,
    required this.label,
    required this.palette,
    required this.kind,
    required this.onTap,
    this.height = 52,
    this.fontSize = 17,
    this.fadeLabel = false,
    this.enabled,
    this.semanticsLabel,
  });

  final String label;
  final Palette palette;
  final PillKind kind;

  /// Set: told to VoiceOver as available or not (a dimmed Continue).
  final bool? enabled;

  /// What VoiceOver reads, when it is more than the label.
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final double height, fontSize;

  /// A new label fades out the old one and in (the changes sheet's buttons).
  final bool fadeLabel;

  @override
  State<PillBtn> createState() => _PillBtnState();
}

class _PillBtnState extends State<PillBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final (Color bg, Color fg) = switch (widget.kind) {
      PillKind.primary => (_down ? Color.lerp(p.light, p.ink, .25)! : p.light, p.ground),
      PillKind.quiet => (p.ink.withValues(alpha: _down ? .07 : 0), p.ink),
      PillKind.tonal => (p.ink.withValues(alpha: _down ? .14 : .09), p.ink),
      PillKind.danger => (p.ink.withValues(alpha: _down ? .14 : .09), p.danger),
    };
    return Semantics(
      button: true,
      // a pill with nothing to do is said to be unavailable
      enabled: widget.enabled ?? (widget.onTap == null ? false : null),
      label: widget.semanticsLabel ?? widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      // an iPad: a pill that spans its column on a phone keeps to a phone's width, centred
      child: Center(
      heightFactor: 1,
      child: _PhoneWidth(
      max: Widths.pill,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .985 : 1,
          duration: const Duration(milliseconds: 200),
          curve: easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(widget.height / 2)),
            // a label too long for the pill (large text sizes, longer languages) shrinks to fit on one
            // line rather than wrapping out of it; one that fits is left as it is
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: widget.fadeLabel
                  ? SwapText(widget.label, style: sans(widget.fontSize, widget.fontSize * 1.25, fg, weight: FontWeight.w500, tracking: -.005))
                  : Text(widget.label, style: sans(widget.fontSize, widget.fontSize * 1.25, fg, weight: FontWeight.w500, tracking: -.005)),
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

/// The prototype's `.topbar .txtbtn`: a word in the light colour.
class LightTextBtn extends StatefulWidget {
  const LightTextBtn({super.key, required this.label, required this.palette, required this.onTap, this.enabled = true, this.disabledHint});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  /// False: dimmed, said to be unavailable (with [disabledHint]), and a tap does nothing.
  final bool enabled;
  final String? disabledHint;

  @override
  State<LightTextBtn> createState() => _LightTextBtnState();
}

class _LightTextBtnState extends State<LightTextBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final on = widget.enabled;
    return Semantics(
      button: true,
      enabled: on ? null : false,
      label: widget.label,
      hint: on ? null : widget.disabledHint,
      excludeSemantics: true,
      onTap: on ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: on ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: AnimatedOpacity(
            opacity: on ? 1 : .4,
            duration: const Duration(milliseconds: 200),
            child: Text(widget.label, style: sans(17, 22, p.light, weight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}


/// Holds a pill to [max] wide where its space has an edge (a pill spanning its column), and leaves
/// it its own width where the space has none (a pill beside other things in a row, as Stop on Your
/// links). A plain width limit would make the second kind [max] wide and push its neighbours out.
class _PhoneWidth extends SingleChildRenderObjectWidget {
  const _PhoneWidth({required this.max, super.child});

  final double max;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPhoneWidth(max);

  @override
  void updateRenderObject(BuildContext context, _RenderPhoneWidth renderObject) => renderObject.max = max;
}

class _RenderPhoneWidth extends RenderProxyBox {
  _RenderPhoneWidth(this._max);

  double _max;
  set max(double v) {
    if (v == _max) return;
    _max = v;
    markNeedsLayout();
  }

  BoxConstraints _inner(BoxConstraints c) =>
      c.maxWidth.isFinite ? c.copyWith(minWidth: math.min(c.minWidth, _max), maxWidth: math.min(c.maxWidth, _max)) : c;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child == null ? constraints.smallest : constraints.constrain(child!.getDryLayout(_inner(constraints)));

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child!.layout(_inner(constraints), parentUsesSize: true);
    size = constraints.constrain(child!.size);
  }
}
