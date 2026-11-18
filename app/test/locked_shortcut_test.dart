// The lock and the shortcuts (home/locked.dart): Record a blessing goes to the recording start while
// locked, as the locked New blessing button does, and shows nothing of any blessing or family
// member; Open my blessings waits for the unlock.
//
//   flutter test test/locked_shortcut_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/home/locked.dart';
import 'package:upon_thy_head/share/share.dart';

void main() {
  test('locked: Record a blessing goes at once; Open my blessings waits for the unlock', () {
    expect(shortcutPassesLock(ShortcutPlace.record, locked: true, asking: false), isTrue);
    expect(shortcutPassesLock(ShortcutPlace.home, locked: true, asking: false), isFalse);
    // unlocked, both go
    expect(shortcutPassesLock(ShortcutPlace.record, locked: false, asking: false), isTrue);
    expect(shortcutPassesLock(ShortcutPlace.home, locked: false, asking: false), isTrue);
    // never while the phone is asking (nothing opens behind its sheet)
    for (final p in ShortcutPlace.values) {
      for (final locked in [true, false]) {
        expect(shortcutPassesLock(p, locked: locked, asking: true), isFalse, reason: '$p locked=$locked');
      }
    }
  });

  test('the locked recording reveals nothing: only its own light, and it is For me', () {
    final kept = sampleBlessings()..first.personId = 'p_emma';
    // on Emma's sky, locked: For me, and no earlier light
    final person = recordingPerson(locked: true, ring: 'p_emma');
    expect(person, '');
    final draft = draftBlessing(DateTime.utc(2026, 11, 18, 20), place: samplePlace, personId: person);
    final lights = recordingLights(locked: true, blessings: kept, draft: draft);
    expect(lights, [draft]);
    expect(lights.single.personId, '');
    // unlocked, the same recording on Emma's sky is hers, among the lights already there
    expect(recordingPerson(locked: false, ring: 'p_emma'), 'p_emma');
    expect(recordingLights(locked: false, blessings: kept, draft: draft), [...kept, draft]);
  });
}
