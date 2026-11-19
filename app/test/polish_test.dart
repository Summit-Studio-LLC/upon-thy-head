// Polish by rule (lib/polish/): what the rules change and what they never touch, how a change is
// measured, and how changes survive a correction by hand.
//
//   flutter test test/polish_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/polish/polish.dart';
import 'package:upon_thy_head/polish/rules.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';

/// (language, spoken, polished with every change kept, the kinds of change in order)
const _table = <(String, String, String, List<ChangeKind>)>[
  // ---- English fillers ----
  ('en', 'I lay my hands upon your head, um, to give you a blessing.', 'I lay my hands upon your head, to give you a blessing.', [ChangeKind.filler]),
  ('en', 'I bless you um with peace.', 'I bless you with peace.', [ChangeKind.filler]),
  ('en', 'I bless you uh, with peace.', 'I bless you with peace.', [ChangeKind.filler]),
  ('en', 'Um, I bless you.', 'I bless you.', [ChangeKind.filler]),
  ('en', 'Um, your strength will return.', 'Your strength will return.', [ChangeKind.filler]),
  ('en', 'He knows. Uh, you are loved.', 'He knows. You are loved.', [ChangeKind.filler]),
  ('en', 'Be patient with your body, um. Strength will return.', 'Be patient with your body. Strength will return.', [ChangeKind.filler]),
  ('en', 'In the name of Jesus Christ, amen, um', 'In the name of Jesus Christ, amen', [ChangeKind.filler]),
  ('en', 'I bless you, um, uh, erm, with peace.', 'I bless you, with peace.', [ChangeKind.filler]),
  ('en', 'Hmm, mm, I bless you.', 'I bless you.', [ChangeKind.filler]),
  ('en', 'He knows you.\n\nUm, your strength will return.', 'He knows you.\n\nYour strength will return.', [ChangeKind.filler]),
  ('en', 'I bless you, er, uhm, with peace.', 'I bless you, with peace.', [ChangeKind.filler]),
  ('en', 'I bless you, you know, with peace.', 'I bless you, with peace.', [ChangeKind.filler]),
  ('en', 'And, like, the hands of those who care for you.', 'And, the hands of those who care for you.', [ChangeKind.filler]),
  // ---- English repeats ----
  ('en', 'I bless you with with peace.', 'I bless you with peace.', [ChangeKind.repeat]),
  ('en', 'I bless you with, with peace.', 'I bless you with peace.', [ChangeKind.repeat]),
  ('en', 'I, I bless you.', 'I bless you.', [ChangeKind.repeat]),
  ('en', 'I, I, I bless you.', 'I bless you.', [ChangeKind.repeat]),
  ('en', 'The the Lord is mindful of you.', 'The Lord is mindful of you.', [ChangeKind.repeat]),
  ('en', 'Um, I bless you with with peace and and comfort.', 'I bless you with peace and comfort.', [ChangeKind.filler, ChangeKind.repeat, ChangeKind.repeat]),
  // ---- Spanish ----
  ('es', 'Te bendigo, eh, con paz.', 'Te bendigo, con paz.', [ChangeKind.filler]),
  ('es', 'Eh, te bendigo con paz.', 'Te bendigo con paz.', [ChangeKind.filler]),
  ('es', 'Te bendigo em con paz.', 'Te bendigo con paz.', [ChangeKind.filler]),
  ('es', 'Y, este, te bendigo.', 'Y, te bendigo.', [ChangeKind.filler]),
  ('es', 'Te bendigo, o sea, con paz.', 'Te bendigo, con paz.', [ChangeKind.filler]),
  ('es', 'Y, pues, te bendigo.', 'Y, te bendigo.', [ChangeKind.filler]),
  ('es', 'Las manos de de los médicos.', 'Las manos de los médicos.', [ChangeKind.repeat]),
  ('es', 'Te bendigo con, con paz.', 'Te bendigo con paz.', [ChangeKind.repeat]),
  ('es', 'Yo, yo te bendigo.', 'Yo te bendigo.', [ChangeKind.repeat]),
];

/// Never touched: each of these comes back with no changes at all.
const _untouched = <(String, String)>[
  ('en', 'Holy, holy, holy is the Lord God Almighty.'),
  ('en', 'Verily, verily, I say unto you.'),
  ('en', 'You are very very loved.'),
  ('en', 'He had had a long illness.'),
  ('en', 'He knows that that worry is real.'),
  ('en', 'In the name of Jesus Christ, amen, amen.'),
  ('en', 'Emma, Emma, the Lord knows you.'),
  ('en', 'Seven, seven times seventy.'),
  ('en', 'For 40 40 days.'),
  ('en', 'What it is is a blessing.'),
  ('en', 'Give her her blessing.'),
  ('en', 'You, you and your family are loved.'),
  ('en', 'Will will be there.'),
  ('en', 'I bless you, you know the Lord.'),
  ('en', 'You know, I bless you.'),
  ('en', 'I would like to bless you.'),
  ('en', 'You are like a tree.'),
  ('en', 'The museum held a drum.'),
  ('en', 'Erm-like sounds.'),
  ('en', 'I bless you with\n\nwith peace.'),
  ('en', 'Uh-oh, said the child.'),
  ('en', 'Ah, my daughter, the Lord knows you.'), // "ah" can be meant (Noah, 2026-11-15)
  ('es', 'Este día es especial.'),
  ('es', 'Te bendigo en este día, este día de paz.'),
  ('es', 'O sea que te bendigo.'),
  ('es', 'Pues te bendigo con paz.'),
  ('es', 'Santo, santo, santo.'),
  ('es', 'Amén, amén.'),
  ('es', 'Dice que que vendrá.'), // "que que" can be grammatical: never a stumble
  ('es', 'Lo que que dijo es verdad.'),
  ('es', 'Te bendigo con muy muy grande amor.'),
  ('es', 'Um, te bendigo.'), // "um" is an English filler; in Spanish it is left
  ('en', 'Eh, I bless you.'), // "eh" is on the Spanish list only
  ('en', ''),
  ('en', 'Peace.'),
];

void main() {
  const rules = PolishRules();

  test('the review row: all kept, some kept, none kept', () {
    expect(Strings.polishedRow(2, 2), '2 changes');
    expect(Strings.polishedRow(1, 2), '1 of 2 kept');
    expect(Strings.polishedRow(0, 2), 'Original words');
  });

  group('the rules change only what they should', () {
    for (final (lang, spoken, polished, kinds) in _table) {
      test('$lang: "$spoken"', () {
        final found = rules.find(spoken, lang);
        expect(applyChanges(spoken, found), polished);
        expect([for (final c in found) c.kind], kinds);
        for (final c in found) {
          expect(spoken.substring(c.start, c.end), c.was, reason: 'each change sits where its words are');
        }
      });
    }
  });

  group('the rules never touch', () {
    for (final (lang, spoken) in _untouched) {
      test('$lang: "$spoken"', () {
        expect(rules.find(spoken, lang), isEmpty);
      });
    }
  });

  test('applying every change and then restoring every one gives back the spoken words, byte for byte', () {
    final spokenAll = [for (final t in _table) t.$2, sampleBlessings().firstWhere((b) => b.id == 'surgery').rawText];
    for (final spoken in spokenAll) {
      final lang = spoken.contains('bendigo') || spoken.contains('médicos') ? 'es' : 'en';
      final changes = Polish.find(spoken, lang);
      final b = _blessing(spoken, lang)..changes = changes;
      expect(b.words, isNot(spoken), reason: 'polished: "$spoken"');
      for (final c in b.changes) {
        c.kept = false;
      }
      expect(b.words, spoken);
      expect(b.polishedText.codeUnits, spoken.codeUnits);
      for (final c in b.changes) {
        c.kept = true;
      }
      // and one at a time, from either end
      for (final c in b.changes.reversed) {
        c.kept = false;
      }
      expect(b.polishedText, spoken);
    }
    final sample = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    for (final c in sample.changes) {
      c.kept = false;
    }
    expect(sample.words.codeUnits, sample.rawText.codeUnits);
  });

  test('size is measured from the words, not declared', () {
    expect(measureSize(', um, right now,', ''), ChangeSize.light);
    expect(measureSize('knows about, He knows', 'knows'), ChangeSize.moderate);
    expect(measureSize('with, with peace', 'with peace'), ChangeSize.light);
    expect(measureSize('are going to be caring', 'will care'), ChangeSize.moderate);
    expect(measureSize('your strength, it’s going to come back to you', 'Strength will return to you'), ChangeSize.heavy);
    expect(measureSize('um, ', ''), ChangeSize.light);
    expect(measureSize('Um, your', 'Your'), ChangeSize.light);
    expect(measureSize('with with', 'with'), ChangeSize.light);
    final sample = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    expect([for (final c in sample.changes) c.size.code], ['light', 'moderate', 'light', 'moderate', 'heavy']);
  });

  test('the sheet shows the words without the commas and spaces a removal took with it', () {
    final c = rules.find('upon your head, um, to give', 'en').single;
    expect(c.was, 'um, ');
    expect(c.shownWas, 'um');
    expect(c.shownNow, '');
    final r = rules.find('I bless you with, with peace', 'en').single;
    expect((r.shownWas, r.shownNow), ('with, with', 'with'));
  });

  group('a correction by hand after polishing', () {
    const spoken = 'Um, I bless you with with peace, and I bless the hands of those, uh, who care for you.';

    Blessing polished() {
      final b = _blessing(spoken, 'en');
      expect(Polish.run(b), 3);
      b.changes[1].kept = false; // "with with" restored
      return b;
    }

    test('changes whose words are untouched keep their place and state', () {
      final b = polished();
      // a different word corrected: "hands" → "hand"
      Polish.correct(b, spoken.replaceFirst('hands', 'hand'));
      expect(b.changes, hasLength(3));
      expect([for (final c in b.changes) c.kept], [true, false, true]);
      for (final c in b.changes) {
        expect(b.rawText.substring(c.start, c.end), c.was);
      }
      expect(b.words, 'I bless you with with peace, and I bless the hand of those, who care for you.');
      expect(Polish.refresh(b), isFalse, reason: 'nothing new');
    });

    test('a change whose words were edited is dropped', () {
      final b = polished();
      Polish.correct(b, spoken.replaceFirst('with with', 'with wit'));
      expect([for (final c in b.changes) c.was], ['Um, ', 'uh, ']);
      Polish.correct(b, b.rawText.replaceFirst(', uh, who', ', uhh, who'));
      expect([for (final c in b.changes) c.was], ['Um, ']);
    });

    test('a word typed onto the edge of a change makes it part of another word, and drops it', () {
      final b = polished();
      Polish.correct(b, spoken.replaceFirst('with with peace', 'with withy peace'));
      expect(b.changes.where((c) => c.kind == ChangeKind.repeat), isEmpty);
    });

    test('typed letter by letter, as the box sends them', () {
      final b = polished();
      var text = spoken;
      // "care" → "cares", one letter at a time, then "for" deleted letter by letter
      for (final step in [spoken.replaceFirst('care for', 'cares for'), spoken.replaceFirst('care for', 'cares fo'), spoken.replaceFirst('care for', 'cares f'), spoken.replaceFirst('care for', 'cares ')]) {
        Polish.correct(b, step);
        text = step;
      }
      expect(b.rawText, text);
      expect([for (final c in b.changes) c.kept], [true, false, true]);
    });

    test('the rules look again at the new words, and add what is new as kept', () {
      final b = polished();
      Polish.correct(b, spoken.replaceFirst('who care', 'who, um, care'));
      expect(Polish.refresh(b), isTrue);
      expect(b.changes, hasLength(4));
      expect([for (final c in b.changes) c.kept], [true, false, true, true]);
      expect(b.words, 'I bless you with with peace, and I bless the hands of those, who, care for you.');
      // restoring all of them gives back the corrected spoken words exactly
      for (final c in b.changes) {
        c.kept = false;
      }
      expect(b.words, b.rawText);
    });

    test('no polish asked: a correction adds nothing', () {
      final b = _blessing(spoken, 'en');
      Polish.correct(b, '$spoken Um, amen.');
      expect(Polish.refresh(b), isFalse);
      expect(b.changes, isEmpty);
    });

    test('a restored change found again by the rules is not added a second time', () {
      final b = polished();
      expect(Polish.run(b), 0);
      expect(b.changes[1].kept, isFalse);
    });
  });

  group('paragraph breaks and quotes around fillers', () {
    test('a standalone filler before a blank line keeps the paragraph break intact', () {
      const first = 'First paragraph. Um.\n\nSecond paragraph.';
      final c1 = rules.find(first, 'en');
      expect(c1, hasLength(1));
      expect(c1.single.was, 'Um.');
      expect(applyChanges(first, c1), contains('\n\n'));

      const start = 'Um.\n\nSecond paragraph.';
      final c2 = rules.find(start, 'en');
      expect(c2, hasLength(1));
      expect(c2.single.was, 'Um.');
      expect(applyChanges(start, c2), '\n\nSecond paragraph.');

      const spanish = 'Eh.\n\nSegundo párrafo.';
      final c3 = rules.find(spanish, 'es');
      expect(c3, hasLength(1));
      expect(c3.single.was, 'Eh.');
      expect(applyChanges(spanish, c3), '\n\nSegundo párrafo.');
    });

    test('unpaired quotes next to fillers are never stripped', () {
      const closing = '“I bless you. Um.” Next.';
      final c1 = rules.find(closing, 'en');
      expect(applyChanges(closing, c1), contains('”'));
      expect(applyChanges(closing, c1), contains('“'));

      const opening = 'Um, “your strength” will return.';
      final c2 = rules.find(opening, 'en');
      expect(applyChanges(opening, c2), '“your strength” will return.');
    });
  });
}

Blessing _blessing(String spoken, String lang) => Blessing(
      id: 'x',
      title: 'T',
      from: '',
      utc: DateTime.utc(2026, 11, 15),
      utcOffset: Duration.zero,
      place: const Place(0, 0),
      rawText: spoken,
      language: lang,
    );
