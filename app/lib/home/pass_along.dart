import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/over_sky_page.dart';

/// "To pass along": the blessings recorded for someone else, newest first. They have no light in the
/// sky and are not in the count; each row says who it is for, when it was given, and whether it has
/// been sent.
class PassAlongLayer extends StatelessWidget {
  const PassAlongLayer({super.key, required this.palette, required this.blessings, required this.onBack, required this.onOpen});

  final Palette palette;

  /// Oldest first, as the store lists them.
  final List<Blessing> blessings;
  final VoidCallback onBack;
  final ValueChanged<Blessing> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final rows = blessings.reversed.toList();
    return OverSkyPage(
      palette: p,
      title: Strings.toPassAlong,
      titleKey: const Key('pass-title'),
      lede: Strings.toPassAlongLede,
      backKey: const Key('pass-back'),
      scrollKey: const Key('pass-scroll'),
      onBack: onBack,
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(Strings.toPassAlongNone, key: const Key('pass-none'), style: sans(15, 22, p.ink3)),
          ),
        for (final b in rows) ...[
          _row(p, b),
          Container(height: 1, color: p.ink.withValues(alpha: .10)),
        ],
      ],
    );
  }

  Widget _row(Palette p, Blessing b) {
    final who = b.recipient.trim();
    final sent = b.sent;
    final status = b.draft ? Strings.notReviewed : (sent == null ? Strings.notSentYet : Strings.sentOn(sent.toLocal()));
    final lines = [
      b.shownTitle,
      if (who.isNotEmpty) Strings.forName(who),
      b.shortDate,
      status,
    ];
    return OpenRow(
      key: Key('pass-row-${b.id}'),
      palette: p,
      semantics: lines.join('. '),
      onTap: () => onOpen(b),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(b.shownTitle, style: serif(20, 26, p.ink)),
        if (who.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(Strings.forName(who), style: serif(16, 22, p.light, italic: true)),
        ],
        const SizedBox(height: 4),
        Text('${b.shortDate}  ·  $status', key: Key('pass-status-${b.id}'), style: sans(13, 18, sent == null ? p.ink2 : p.ink3)),
      ]),
    );
  }
}
