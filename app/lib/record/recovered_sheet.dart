import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';

/// "A recording was kept": at launch, over the dimmed sky, when the app had been closed while a
/// blessing was being recorded and what was recorded has been saved as a draft.
class RecoveredSheet extends StatelessWidget {
  const RecoveredSheet({
    super.key,
    required this.palette,
    required this.on,
    required this.recovered,
    required this.onReview,
    required this.onLater,
  });

  final Palette palette;
  final bool on;

  /// The blessings saved, oldest first.
  final List<Blessing> recovered;
  final VoidCallback onReview, onLater;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final title = Strings.recoveredTitle(recovered.isEmpty ? 1 : recovered.length);
    return Sheet(
      palette: p,
      on: on,
      label: title,
      panelKey: const Key('recovered-sheet'),
      barrier: true,
      onDismiss: onLater,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, key: const Key('recovered-title'), style: serif(22, 28, p.ink)),
        const SizedBox(height: 6),
        Text(
          recovered.isEmpty ? '' : Strings.recoveredBody([for (final b in recovered) b.local]),
          key: const Key('recovered-body'),
          style: sans(15, 22, p.ink2),
        ),
        const SizedBox(height: 20),
        SheetButtons(
          palette: p,
          left: PillBtn(
            key: const Key('recovered-later'),
            label: Strings.recoveredLater,
            palette: p,
            kind: PillKind.quiet,
            height: 48,
            fontSize: 16,
            onTap: onLater,
          ),
          right: PillBtn(
            key: const Key('recovered-review'),
            label: Strings.reviewNow,
            palette: p,
            kind: PillKind.primary,
            height: 48,
            fontSize: 16,
            onTap: onReview,
          ),
        ),
      ]),
    );
  }
}
