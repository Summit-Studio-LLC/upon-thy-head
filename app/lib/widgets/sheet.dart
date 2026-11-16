import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'buttons.dart';

/// The prototype's `.sheet`: a raised panel rising from the bottom edge.
/// With [barrier], the rest of the screen dims and a tap on it calls [onDismiss].
class Sheet extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final p = palette;
    // the keyboard pushes the sheet up
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final panel = IgnorePointer(
      ignoring: !on,
      child: AnimatedSlide(
        offset: on ? Offset.zero : const Offset(0, 1.04),
        duration: const Duration(milliseconds: 500),
        curve: easeOut,
        child: Container(
          key: panelKey,
          padding: EdgeInsets.fromLTRB(24, 20, 24, 38 + inset),
          decoration: BoxDecoration(
            color: p.raised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: p.ink.withValues(alpha: .07), offset: const Offset(0, -1))],
          ),
          child: Semantics(scopesRoute: true, explicitChildNodes: true, label: label, child: child),
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
              duration: const Duration(milliseconds: 400),
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
  });

  final Palette palette;
  final bool on, barrier;
  final String title, body, dangerLabel, safeLabel;
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
        Text(title, style: serif(22, 28, p.ink)),
        const SizedBox(height: 6),
        Text(body, style: sans(15, 22, p.ink2)),
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
