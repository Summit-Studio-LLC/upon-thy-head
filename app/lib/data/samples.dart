import 'dart:math' as math;

import '../polish/change.dart';

import 'blessing.dart';
import 'store.dart';

/// `--dart-define=SEED_SAMPLES=true` puts the five sample blessings into an
/// empty store; `SEED_SAMPLES=dense` puts about 120 plain ones there instead,
/// for testing a crowded ring. Neither is for people's phones.
const String seedSamples = String.fromEnvironment('SEED_SAMPLES');
const bool seedSamplesFlag = seedSamples == 'true' || seedSamples == 'dense' || seedSamples == 'first-run';

/// `SEED_SAMPLES=first-run` (test builds): the five samples, and the first run all the same, as a
/// fresh install has it (a seeded build otherwise never sees the first run). The Android lock and
/// location run (tool/android_lock.sh) uses it to meet the first run and then a sky with blessings.
const bool seedWithFirstRun = seedSamples == 'first-run';

/// The design prototype's five blessings. Only "Comfort before surgery" has its words.
List<Blessing> sampleBlessings() {
  final made = DateTime.utc(2026, 11, 1);
  Blessing b(String id, String title, String from, DateTime utc, int offsetHours, {String raw = '', List<Change> changes = const [], List<String> tags = const []}) =>
      Blessing(
        id: id,
        title: title,
        from: from,
        utc: utc,
        utcOffset: Duration(hours: offsetHours),
        place: samplePlace,
        recipient: 'Emma',
        ownership: Ownership.forMe,
        rawText: raw,
        changes: [for (final c in changes) c.copy()],
        polishAsked: changes.isNotEmpty,
        tags: tags,
        draft: false,
        created: made,
        updated: made,
      );
  return [
    b('fever', 'Healing, the night of the fever', 'Grandpa Ruiz', DateTime.utc(2024, 6, 3, 5, 30), -6, tags: ['Healing', 'Family']),
    b('baby', 'When the baby came early', 'Mateo', DateTime.utc(2025, 1, 12, 10, 20), -7, tags: ['Family']),
    b('primary', 'Set apart to teach Primary', 'Bishop Alvarez', DateTime.utc(2025, 8, 24, 18, 50), -6, tags: ['Calling']),
    b('surgery', 'Comfort before surgery', 'Dad', DateTime.utc(2026, 3, 3, 16, 40), -7,
        raw: _surgeryRaw, changes: surgeryChanges(), tags: ['Comfort', 'Healing']),
    b('job', 'Before the new job', 'Dad', DateTime.utc(2026, 10, 5, 1, 40), -6, tags: ['Work']),
  ];
}

/// For testing only: 120 blessings spread unevenly over the fourteen years
/// ending this year (some years busy, some quiet, a few given days apart),
/// none later than [now]. Titles are plain ("Test blessing 37"). The same
/// every time for the same year.
List<Blessing> denseBlessings({DateTime? now, int count = 120}) {
  now ??= DateTime.now();
  final rnd = math.Random(14);
  final start = DateTime.utc(now.year - 13).millisecondsSinceEpoch, end = now.toUtc().millisecondsSinceEpoch - 36e5;
  final span = end - start;
  // busy stretches: clusters round a few dates, plus a thin scatter
  final centres = [for (var i = 0; i < 9; i++) rnd.nextDouble()];
  final times = <int>[];
  for (var i = 0; i < count; i++) {
    double u;
    if (rnd.nextDouble() < .55) {
      final c = centres[rnd.nextInt(centres.length)];
      // a few weeks to several months either side
      final g = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * (rnd.nextBool() ? .01 : .04);
      u = c + g;
    } else {
      u = rnd.nextDouble();
    }
    times.add(start + (u.clamp(0.0, 1.0) * span).round());
  }
  times.sort();
  final made = DateTime.utc(2026, 11, 1);
  return [
    for (var i = 0; i < times.length; i++)
      Blessing(
        id: 'dense-${(i + 1).toString().padLeft(3, '0')}',
        title: 'Test blessing ${i + 1}',
        from: 'Dad',
        utc: DateTime.fromMillisecondsSinceEpoch(times[i], isUtc: true),
        utcOffset: const Duration(hours: -7),
        place: samplePlace,
        ownership: Ownership.forMe,
        draft: false,
        created: made,
        updated: made,
      ),
  ];
}

/// Seeds the samples when the store is empty ([dense]: the 120). Returns true if it did.
Future<bool> seedSamplesIfEmpty(BlessingStore store, {bool dense = false}) async {
  if (await store.count() > 0) return false;
  for (final b in dense ? denseBlessings() : sampleBlessings()) {
    await store.create(b);
  }
  return true;
}

// The prototype's WORDS, with each change E applied (polished) or not (raw).
const surgeryPolished = 'Emma, I lay my hands upon your head to give you a blessing of comfort.\n\n'
    'Your Heavenly Father knows you. He knows the worry you have carried these weeks, and He wants you to know that you have not carried it alone.\n\n'
    'I bless you with peace as you go into this surgery, and I bless the hands of those who will care for you. Be patient with your body as it heals. Strength will return to you in its time.\n\n'
    'I say these things in the name of Jesus Christ, amen.';

const _surgeryRaw = 'Emma, I lay my hands upon your head, um, right now, to give you a blessing of comfort.\n\n'
    'Your Heavenly Father knows you. He knows about, He knows the worry you have carried these weeks, and He wants you to know that you have not carried it alone.\n\n'
    'I bless you with, with peace as you go into this surgery, and I bless the hands of those who are going to be caring for you. Be patient with your body as it heals. your strength, it’s going to come back to you in its time.\n\n'
    'I say these things in the name of Jesus Christ, amen.';

/// The prototype's five changes (its E), as an earlier polish stored them: words and replacements
/// with no positions. Three are rewordings no rule here would make; they stand for what a later
/// source of changes (a model on the phone) could propose, and show the screen at every size.
const legacySurgeryEdits = [
  (kind: 'Filler removed', was: ', um, right now,', now: ''),
  (kind: 'Reworded', was: 'knows about, He knows', now: 'knows'),
  (kind: 'Repeated word removed', was: 'with, with peace', now: 'with peace'),
  (kind: 'Reworded', was: 'are going to be caring', now: 'will care'),
  (kind: 'Reworded', was: 'your strength, it’s going to come back to you', now: 'Strength will return to you'),
];

/// The sample's changes, placed in its spoken words.
List<Change> surgeryChanges() => locateChanges(_surgeryRaw, [for (final e in legacySurgeryEdits) (kind: kindOfLegacy(e.kind), was: e.was, now: e.now)], source: 'sample');
