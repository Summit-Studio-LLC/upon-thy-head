import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';
import 'blessing_file.dart';
import 'share.dart';

/// What a blessing file that arrived comes to, once read and set beside the store.
sealed class Arrival {
  const Arrival();
}

/// A blessing this phone does not have: "Keep it with your blessings?"
class ArrivalNew extends Arrival {
  const ArrivalNew(this.record);
  final BlessingRecord record;
}

/// Exactly one this phone has: no question; it opens, saying so.
class ArrivalSame extends Arrival {
  const ArrivalSame(this.mine);
  final Blessing mine;
}

/// One this phone has, but this copy says something else: Replace mine, or Keep mine.
class ArrivalDifferent extends Arrival {
  const ArrivalDifferent(this.record, this.mine);
  final BlessingRecord record;
  final Blessing mine;
}

/// Made by a newer version of the app.
class ArrivalNewer extends Arrival {
  const ArrivalNewer();
}

/// Not something this app can read.
class ArrivalUnreadable extends Arrival {
  const ArrivalUnreadable(this.why);
  final String why;
}

/// A link whose fragment is not a key (cut off when it was copied, or never there).
class ArrivalNoKey extends Arrival {
  const ArrivalNoKey();
}

/// A link that has stopped working: stopped by the sender, or past its 30 days.
class ArrivalStopped extends Arrival {
  const ArrivalStopped();
}

/// A link opened with no internet: "This blessing is on its way."
class ArrivalOnItsWay extends Arrival {
  const ArrivalOnItsWay();
}

/// A link the service could not hand over just now (too many at once, or not available).
class ArrivalNotNow extends Arrival {
  const ArrivalNotNow();
}

/// Read [file] strictly, and look for it among the blessings already kept ([find]).
Future<Arrival> arrivalOf(IncomingFile file, Future<Blessing?> Function(String id) find) async {
  final bytes = file.bytes;
  if (file.tooLarge) return const ArrivalUnreadable('over the size limit');
  if (bytes == null) return const ArrivalUnreadable('no bytes');
  final read = readBlessingFile(bytes);
  switch (read) {
    case BlessingReadNewer():
      return const ArrivalNewer();
    case BlessingReadBad(:final why):
      return ArrivalUnreadable(why);
    case BlessingReadOk(:final record):
      final mine = await find(record.id);
      if (mine == null) return ArrivalNew(record);
      return record.sameAs(mine) ? ArrivalSame(mine) : ArrivalDifferent(record, mine);
  }
}

/// The sheet over the sky for a blessing file that arrived: the question, or why it cannot open.
/// Nothing of it is built while the app is locked (the home screen holds it back until unlocked).
class ReceiveSheet extends StatelessWidget {
  const ReceiveSheet({super.key, required this.palette, required this.on, required this.arrival, required this.onKeep, required this.onNotNow});

  final Palette palette;
  final bool on;

  /// What is shown; the last one stays while the sheet slides away.
  final Arrival? arrival;

  /// Keep (a new one) and Replace mine (a different one).
  final VoidCallback onKeep;

  /// Not now, Keep mine, OK, or a tap on the dimmed sky.
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final a = arrival;
    final record = switch (a) {
      ArrivalNew(:final record) => record,
      ArrivalDifferent(:final record) => record,
      _ => null,
    };
    String heading;
    String? body;
    if (record != null) {
      heading = Strings.isUntitled(record.title) ? Strings.untitled : record.title;
      body = a is ArrivalDifferent ? Strings.alreadyDifferent : Strings.receiveAsk;
    } else {
      (heading, body) = switch (a) {
        ArrivalNewer() => (Strings.fileNewer, null),
        ArrivalStopped() => (Strings.linkStoppedTitle, Strings.linkStoppedBody),
        ArrivalOnItsWay() => (Strings.onItsWay, Strings.onItsWayBody),
        ArrivalNoKey() => (Strings.linkNoKey, Strings.linkNoKeyBody),
        ArrivalNotNow() => (Strings.linkNotNow, Strings.linkNotNowBody),
        ArrivalUnreadable(:final why) when why.startsWith('link') => (Strings.linkUnreadable, null),
        _ => (Strings.fileUnreadable, null),
      };
    }
    final from = record == null ? '' : record.from;
    PillBtn pill(Key key, String label, PillKind kind, VoidCallback onTap) =>
        PillBtn(key: key, label: label, palette: p, kind: kind, height: 48, fontSize: 16, onTap: onTap);
    // hidden (or held back while locked), nothing of it is read aloud
    return ExcludeSemantics(
      excluding: !on,
      child: Sheet(
        palette: p,
        on: on,
        label: heading,
        panelKey: const Key('receive-sheet'),
        barrier: true,
        // A tap on the dimmed sky does nothing here: a blessing someone sent is declined only by
        // its own button, never by a stray tap while the sheet is still rising.
        onDismiss: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(heading, key: const Key('receive-title'), style: record == null ? sans(17, 24, p.ink) : serif(22, 28, p.ink)),
            if (record != null) ...[
              const SizedBox(height: 6),
              Text(from.isEmpty ? Strings.aBlessing : Strings.blessingFrom(from), key: const Key('receive-from'), style: serif(17, 24, p.light, italic: true)),
              const SizedBox(height: 2),
              Text(Strings.longDate(record.utc.add(record.utcOffset)), key: const Key('receive-date'), style: sans(14, 20, p.ink2)),
            ],
            if (body != null) ...[const SizedBox(height: 14), Text(body, key: const Key('receive-body'), style: sans(15, 22, p.ink2))],
            const SizedBox(height: 20),
            if (record == null)
              pill(const Key('receive-ok'), Strings.ok, PillKind.primary, onNotNow)
            else if (a is ArrivalDifferent)
              SheetButtons(
                palette: p,
                left: pill(const Key('receive-keep-mine'), Strings.keepMine, PillKind.quiet, onNotNow),
                right: pill(const Key('receive-replace'), Strings.replaceMine, PillKind.primary, onKeep),
              )
            else
              SheetButtons(
                palette: p,
                left: pill(const Key('receive-not-now'), Strings.notNow, PillKind.quiet, onNotNow),
                right: pill(const Key('receive-keep'), Strings.receiveKeep, PillKind.primary, onKeep),
              ),
          ],
        ),
      ),
    );
  }
}

/// "You already have this blessing.": a quiet line over the reading page for a few seconds, read
/// aloud by VoiceOver.
class ReceiveNotice extends StatelessWidget {
  const ReceiveNotice({super.key, required this.palette, required this.on, required this.text});
  final Palette palette;
  final bool on;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final still = MediaQuery.of(context).disableAnimations;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: still ? Duration.zero : const Duration(milliseconds: 400),
        curve: easeOut,
        child: Center(
          child: Container(
            key: const Key('receive-notice'),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(22)),
            child: Semantics(
              liveRegion: true,
              child: Text(text, textAlign: TextAlign.center, style: sans(15, 21, p.ink)),
            ),
          ),
        ),
      ),
    );
  }
}
