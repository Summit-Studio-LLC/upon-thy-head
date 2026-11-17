import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/sent_link.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/over_sky_page.dart';
import '../widgets/sheet.dart';
import 'link_service.dart';
import 'links.dart';

/// "Your links", from Settings and from the link-made sheet: every link sent, newest first. A live
/// one can be stopped (asked once); one that has stopped or run out is shown quietly until it is
/// cleared, 30 days later.
class YourLinksLayer extends StatefulWidget {
  const YourLinksLayer({super.key, required this.palette, required this.on, required this.links, required this.onBack, DateTime Function()? now})
      : now = now ?? DateTime.now;

  final Palette palette;
  final bool on;
  final Links? links;
  final VoidCallback onBack;
  final DateTime Function() now;

  @override
  State<YourLinksLayer> createState() => YourLinksLayerState();
}

class YourLinksLayerState extends State<YourLinksLayer> {
  List<SentLink> _rows = const [];
  SentLink? _asking;
  bool _stopping = false;

  /// What went wrong with the last stop, said plainly under its row.
  String? _trouble;
  String? _troubleId;

  @override
  void initState() {
    super.initState();
    if (widget.on) unawaited(reload());
  }

  @override
  void didUpdateWidget(YourLinksLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !oldWidget.on) {
      _trouble = _troubleId = null;
      _asking = null;
      unawaited(reload());
    }
    if (!widget.on && oldWidget.on) _asking = null;
  }

  Future<void> reload() async {
    final l = widget.links;
    if (l == null) return;
    final rows = await l.list();
    if (mounted) setState(() => _rows = rows);
  }

  /// Android's back: the Stop question goes, if it is up.
  bool closeSheet() {
    if (_asking == null) return false;
    setState(() => _asking = null);
    return true;
  }

  Future<void> _stop() async {
    final link = _asking, l = widget.links;
    if (link == null || l == null || _stopping) return;
    setState(() => _stopping = true);
    StopResult r;
    try {
      r = await l.stop(link);
    } catch (_) {
      r = StopResult.failed;
    }
    if (!mounted) return;
    setState(() {
      _stopping = false;
      _asking = null;
      _troubleId = r == StopResult.stopped ? null : link.id;
      _trouble = switch (r) {
        StopResult.stopped => null,
        StopResult.offline => Strings.stopOffline,
        StopResult.failed => Strings.stopFailed,
      };
    });
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final now = widget.now().toUtc();
    return Stack(children: [
      Positioned.fill(
        child: OverSkyPage(
          palette: p,
          title: Strings.yourLinks,
          titleKey: const Key('links-title'),
          lede: Strings.linksLede,
          backKey: const Key('links-back'),
          scrollKey: const Key('links-scroll'),
          onBack: widget.onBack,
          children: [
            if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(Strings.linksNone, key: const Key('links-none'), style: sans(15, 22, p.ink3)),
              ),
            for (final l in _rows) ...[
              _row(p, l, now),
              Container(height: 1, color: p.ink.withValues(alpha: .10)),
            ],
          ],
        ),
      ),
      Positioned.fill(
        child: ConfirmSheet(
          palette: p,
          on: widget.on && _asking != null,
          barrier: true,
          title: Strings.stopQ,
          body: Strings.stopBody,
          dangerLabel: Strings.stopLink,
          safeLabel: Strings.cancel,
          onDanger: _stop,
          onSafe: () => setState(() => _asking = null),
          panelKey: const Key('stop-sheet'),
          dangerKey: const Key('stop-confirm'),
          safeKey: const Key('stop-cancel'),
        ),
      ),
    ]);
  }

  Widget _row(Palette p, SentLink l, DateTime now) {
    final state = l.stateAt(now);
    final live = state == LinkState.live;
    final line = switch (state) {
      LinkState.live => Strings.linkSentStops(l.sent.toLocal(), l.expires.toLocal(), now.toLocal()),
      LinkState.stopped => Strings.linkStoppedOn(l.stopped!.toLocal()),
      LinkState.expired => Strings.linkEndedOn(l.expires.toLocal()),
    };
    final trouble = _troubleId == l.id ? _trouble : null;
    return Padding(
      key: Key('link-row-${l.id}'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Strings.isUntitled(l.title) ? Strings.untitled : l.title, style: serif(19, 25, live ? p.ink : p.ink3)),
              const SizedBox(height: 3),
              Text(line, key: Key('link-line-${l.id}'), style: sans(13, 18, live ? p.ink2 : p.ink3)),
            ]),
          ),
          if (live) ...[
            const SizedBox(width: 12),
            PillBtn(
              key: Key('link-stop-${l.id}'),
              label: Strings.stop,
              palette: p,
              kind: PillKind.tonal,
              height: 40,
              fontSize: 15,
              onTap: () => setState(() {
                _trouble = _troubleId = null;
                _asking = l;
              }),
            ),
          ],
        ]),
        if (trouble != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(trouble, key: const Key('link-trouble'), style: sans(14, 20, p.danger))),
        ],
      ]),
    );
  }
}
