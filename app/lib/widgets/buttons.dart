import 'package:flutter/widgets.dart';

import '../theme.dart';
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          height: 44,
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
      enabled: widget.enabled,
      label: widget.semanticsLabel ?? widget.label,
      excludeSemantics: true,
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
    );
  }
}

/// The prototype's `.topbar .txtbtn`: a word in the light colour.
class LightTextBtn extends StatefulWidget {
  const LightTextBtn({super.key, required this.label, required this.palette, required this.onTap});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<LightTextBtn> createState() => _LightTextBtnState();
}

class _LightTextBtnState extends State<LightTextBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: Text(widget.label, style: sans(17, 22, p.light, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

