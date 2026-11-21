import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../polish/change.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/measure.dart';
import '../widgets/whole_words.dart';
import 'blessing_file.dart';
import 'receive.dart';

/// A family member's ring that arrived on their own phone (design/entry-and-rings, B1-12, B1-13
/// and B1-16): "Your blessings were kept for you." (or, when this phone already keeps blessings,
/// "Four more of your blessings"), then each new one to read, oldest first ("1 of 7"), with Not now
/// and Keep them. Nothing of it is built while the app is locked: home holds it back until unlocked,
/// as a single blessing's sheet.
class RingArrivalLayer extends StatefulWidget {
  const RingArrivalLayer({
    super.key,
    required this.palette,
    required this.arrival,
    required this.more,
    required this.onKeep,
    required this.onNotNow,
    this.busy = false,
  });

  final Palette palette;
  final ArrivalRing arrival;

  /// This phone already keeps blessings of its own: the words of B1-16 ("Four more…").
  final bool more;
  final VoidCallback onKeep, onNotNow;
  final bool busy;

  @override
  State<RingArrivalLayer> createState() => RingArrivalLayerState();
}

class RingArrivalLayerState extends State<RingArrivalLayer> {
  bool reading = false;
  int index = 0;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(RingArrivalLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.arrival, widget.arrival)) {
      reading = false;
      index = 0;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int i) {
    final n = widget.arrival.fresh.length;
    if (i < 0 || i >= n) return;
    setState(() => index = i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Stack(key: const Key('ring-arrival'), children: [
      Positioned.fill(child: ColoredBox(color: p.ground.withValues(alpha: reading ? .96 : .9))),
      Positioned.fill(child: reading ? _read(p) : _welcome(p)),
    ]);
  }

  BlessingRecord get _first => widget.arrival.fresh.first;
  BlessingRecord get _last => widget.arrival.fresh.last;
  DateTime _local(BlessingRecord r) => r.utc.add(r.utcOffset);

  Widget _welcome(Palette p) {
    final a = widget.arrival;
    final mq = MediaQuery.of(context);
    final n = a.fresh.length;
    final title = widget.more ? Strings.ringMore(n) : Strings.ringWelcome;
    final body = widget.more
        ? Strings.ringMoreBody(a.ring.keptBy, _local(_first), _local(_last),
            firstYearOnly: _first.precision == DatePrecision.year, lastYearOnly: _last.precision == DatePrecision.year)
        : Strings.ringWelcomeBody(a.ring.keptBy, n, _local(_first), yearOnly: _first.precision == DatePrecision.year);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(28, mq.viewPadding.top + 40, 28, mq.viewPadding.bottom + 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: mq.size.height - mq.viewPadding.top - mq.viewPadding.bottom - 68),
        child: Measure(
          max: Widths.form,
          alignment: Alignment.bottomCenter,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: WholeWords(title, textKey: const Key('ring-arrival-title'), maxScale: titleMaxScale, style: serif(40, 46, p.ink, tracking: -.012))),
            const SizedBox(height: 18),
            Text(body, key: const Key('ring-arrival-body'), style: sans(17, 25, p.ink2)),
            const SizedBox(height: 32),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.pill),
                child: PillBtn(
                  key: const Key('ring-arrival-continue'),
                  label: Strings.continueLabel,
                  palette: p,
                  kind: PillKind.primary,
                  onTap: () => setState(() => reading = true),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _read(Palette p) {
    final a = widget.arrival;
    final mq = MediaQuery.of(context);
    final n = a.fresh.length;
    final r = a.fresh[index.clamp(0, n - 1)];
    final title = Strings.isUntitled(r.title) ? Strings.untitled : r.title;
    final words = applyKept(r);
    final paragraphs = words.split(r.entered ? RegExp(r'\n') : RegExp(r'\n\s*\n')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final wordStyle = serif(19, 30, p.ink);
    final foot = Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + mq.viewPadding.bottom * .6),
      decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Measure(
        max: Widths.card,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconBtn(
              key: const Key('ring-arrival-earlier'),
              icon: Glyph.older,
              color: index > 0 ? p.ink : p.ink3,
              palette: p,
              semantics: Strings.earlier,
              onTap: () => _go(index - 1),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(Strings.ofTotal(index + 1, n), key: const Key('ring-arrival-of'), textAlign: TextAlign.center, style: sans(14, 19, p.ink2)),
              ),
            ),
            IconBtn(
              key: const Key('ring-arrival-later'),
              icon: Glyph.newer,
              color: index < n - 1 ? p.ink : p.ink3,
              palette: p,
              semantics: Strings.later,
              onTap: () => _go(index + 1),
            ),
          ]),
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: widget.busy,
            child: Row(children: [
              Expanded(
                child: PillBtn(key: const Key('ring-arrival-not-now'), label: Strings.notNow, palette: p, kind: PillKind.tonal, height: 48, fontSize: 16, onTap: widget.onNotNow),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillBtn(key: const Key('ring-arrival-keep'), label: Strings.keepThem, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: widget.onKeep),
              ),
            ]),
          ),
        ]),
      ),
    );
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          key: const Key('ring-arrival-scroll'),
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(28, mq.viewPadding.top + 32, 28, 32),
          child: Measure(
            max: Widths.reading,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Strings.givenLong(_local(r), r.precision), key: const Key('ring-arrival-date'), style: sans(13, 18, p.ink2, tracking: .005)),
              const SizedBox(height: 6),
              Semantics(header: true, child: WholeWords(title, textKey: const Key('ring-arrival-read-title'), maxScale: titleMaxScale, style: serif(30, 34.5, p.ink, tracking: -.012))),
              const SizedBox(height: 4),
              Text(r.from.isEmpty ? Strings.aBlessing : Strings.blessingFrom(r.from), style: serif(18, 26, p.light, italic: true)),
              const SizedBox(height: 24),
              if (paragraphs.isEmpty)
                Text(Strings.noWords, style: serif(19, 30, p.ink3, italic: true))
              else
                for (var i = 0; i < paragraphs.length; i++)
                  Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 15), child: Text(paragraphs[i], style: wordStyle)),
              if (r.entered) ...[
                const SizedBox(height: 24),
                Text(Strings.enteredNote, style: sans(14, 20, p.ink3)),
              ],
            ]),
          ),
        ),
      ),
      foot,
    ]);
  }
}

/// The words a record's reader sees: the spoken words with the kept changes applied.
String applyKept(BlessingRecord r) => applyChanges(r.spoken, r.changes);
