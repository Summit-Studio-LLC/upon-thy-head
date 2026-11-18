import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';

Map<String, Object?> jsonOf(BlessingRecord r) => jsonDecode(utf8.decode(r.toFileBytes())) as Map<String, Object?>;

BlessingRead readMap(Map<String, Object?> m) => readBlessingFile(utf8.encode(jsonEncode(m)));

BlessingRecord ok(BlessingRead r) {
  if (r is! BlessingReadOk) fail('expected a blessing, got $r');
  return r.record;
}

void bad(BlessingRead r, [String? why]) {
  expect(r, isA<BlessingReadBad>(), reason: 'expected a refusal${why == null ? '' : ' ($why)'}');
}

void main() {
  final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
  final en = Strings.wordsFor(UiLanguage.english);

  group('writing', () {
    test('the sample: every field the receiver needs, and nothing else', () {
      final j = jsonOf(BlessingRecord.of(surgery));
      expect(j.keys.toList(), ['format', 'version', 'id', 'title', 'given', 'offset', 'from', 'for', 'tags', 'language', 'words', 'changes', 'place']);
      expect(j['format'], 'upon-thy-head/blessing');
      expect(j['version'], 1);
      expect(j['id'], 'surgery');
      expect(j['title'], 'Comfort before surgery');
      expect(j['given'], '2026-03-03T16:40Z');
      expect(j['offset'], -420);
      expect(j['from'], 'Dad');
      expect(j['for'], 'Emma');
      expect(j['tags'], ['Comfort', 'Healing']);
      expect(j['words'], surgery.rawText);
      expect((j['changes'] as List).length, surgery.changes.length);
      // the place, to a tenth of a degree (Noah, 2026-11-16: "Location can be shared")
      expect(j['place'], {'lat': (surgery.place.lat * 10).round() / 10, 'lon': (surgery.place.lon * 10).round() / 10});
      // no audio, no first transcript, nothing about the phone
      final text = utf8.decode(BlessingRecord.of(surgery).toFileBytes());
      for (final word in ['audio', 'first', 'device', 'created', 'updated', 'draft']) {
        expect(text.contains('"$word'), isFalse, reason: word);
      }
    });

    test('the same blessing always gives the same bytes', () {
      expect(BlessingRecord.of(surgery).toFileBytes(), BlessingRecord.of(sampleBlessings().firstWhere((b) => b.id == 'surgery')).toFileBytes());
    });

    test('named as the PDF is', () {
      expect(blessingFileName(shareFileName(surgery, en)), 'Comfort before surgery, March 3, 2026.blessing');
    });
  });

  group('round trip', () {
    test('the sample comes back exactly: words, polished words, every change and whether it is kept', () {
      surgery.changes[1].kept = false;
      final back = ok(readBlessingFile(BlessingRecord.of(surgery).toFileBytes()));
      final b = back.toBlessing(place: const Place(10, 20));
      expect(b.title, surgery.title);
      expect(b.utc, surgery.utc);
      expect(b.utcOffset, surgery.utcOffset);
      expect(b.longDate, surgery.longDate);
      expect(b.from, 'Dad');
      expect(b.recipient, 'Emma');
      expect(b.tags, surgery.tags);
      expect(b.rawText, surgery.rawText);
      expect(b.words, surgery.words);
      expect(b.polishedText, surgery.polishedText);
      expect(b.keptChanges, surgery.keptChanges);
      expect([for (final c in b.changes) c.toString()], [for (final c in surgery.changes) c.toString()]);
      // the receiver's own, finished, at the place it was given (not the receiver's)
      expect(b.ownership, Ownership.forMe);
      expect(b.draft, isFalse);
      expect(b.place.lat, (surgery.place.lat * 10).round() / 10);
      expect(b.place.lon, (surgery.place.lon * 10).round() / 10);
      expect(b.audio, '');
      expect(back.sameAs(surgery), isTrue);
      // restoring every change gives the spoken words
      for (final c in b.changes) {
        c.kept = false;
      }
      expect(b.words, surgery.rawText);
    });

    test('accents, an emoji, paragraph breaks, quotes and a tab come back character for character', () {
      const words = 'Querida Lucía, te bendigo con paz 🙏 y “fortaleza”.\n\nÑandú, señor, corazón — ¿sí? ¡Sí!\n\n\tAmén.';
      final b = Blessing(id: 'a1', title: 'Para Lucía ✨', from: 'Abuelo Ruiz', recipient: 'Lucía', utc: DateTime.utc(2025, 12, 24, 23, 59), utcOffset: const Duration(minutes: 330), place: samplePlace, rawText: words, language: 'es', draft: false);
      final r = ok(readBlessingFile(BlessingRecord.of(b).toFileBytes())).toBlessing(place: samplePlace);
      expect(r.rawText, words);
      expect(r.title, 'Para Lucía ✨');
      expect(r.utcOffset, const Duration(minutes: 330));
      expect(r.language, 'es');
    });

    test('a different word is not the same content; ownership and draft do not count', () {
      final rec = BlessingRecord.of(surgery);
      final copy = rec.toBlessing(place: samplePlace)..ownership = Ownership.passingOn;
      expect(rec.sameAs(copy), isTrue);
      copy.rawText = copy.rawText.replaceFirst('comfort', 'confort');
      expect(rec.sameAs(copy), isFalse);
      final kept = rec.toBlessing(place: samplePlace)..changes.first.kept = !rec.changes.first.kept;
      expect(rec.sameAs(kept), isFalse);
    });

    test('Replace mine writes every field over, the place too; draft and recording are left to the caller', () {
      final mine = BlessingRecord.of(surgery).toBlessing(place: const Place(1, 2))
        ..rawText = 'Changed.'
        ..changes = []
        ..place = const Place(1, 2)
        ..draft = true
        ..audio = 'surgery.m4a';
      BlessingRecord.of(surgery).writeOver(mine);
      expect(BlessingRecord.of(surgery).sameAs(mine), isTrue);
      expect(mine.place.lat, (surgery.place.lat * 10).round() / 10);
      expect(mine.draft, isTrue);
      expect(mine.audio, 'surgery.m4a');
    });

    test('a file with no place (made before 2026-11-16) keeps the place already there on Replace mine', () {
      final old = jsonOf(BlessingRecord.of(surgery))..remove('place');
      final rec = ok(readMap(old));
      final mine = rec.toBlessing(place: const Place(1, 2));
      rec.writeOver(mine);
      expect(mine.place.lat, 1);
    });
  });

  group('the place', () {
    Map<String, Object?> good() => jsonOf(BlessingRecord.of(surgery));

    test('a file made before the place was carried still opens, at the receiver\'s place, with nothing raised', () {
      final old = good()..remove('place');
      final rec = ok(readMap(old));
      expect(rec.place, isNull);
      final b = rec.toBlessing(place: const Place(19.4, -99.1));
      expect(b.place.lat, 19.4);
      expect(b.place.lon, -99.1);
      // and writing it again leaves the field out
      expect(jsonOf(rec).containsKey('place'), isFalse);
    });

    test('null is the same as missing', () {
      expect(ok(readMap({...good(), 'place': null})).place, isNull);
    });

    test('whatever was written, only a tenth of a degree is kept', () {
      final r = ok(readMap({...good(), 'place': {'lat': 40.770412, 'lon': -111.891937}}));
      expect(r.place!.lat, 40.8);
      expect(r.place!.lon, -111.9);
      final whole = ok(readMap({...good(), 'place': {'lat': 0, 'lon': 180}}));
      expect(whole.place!.lat, 0);
      expect(whole.place!.lon, 180);
    });

    test('a sharper place in the sender\'s blessing is rounded before it is written', () {
      final b = BlessingRecord.of(surgery).toBlessing(place: samplePlace)..place = const Place(40.770412, -111.891937);
      expect(jsonOf(BlessingRecord.of(b))['place'], {'lat': 40.8, 'lon': -111.9});
    });

    test('a broken place refuses the file', () {
      for (final p in [
        'here',
        [40.8, -111.9],
        {'lat': 40.8},
        {'lat': '40.8', 'lon': -111.9},
        {'lat': 91, 'lon': 0},
        {'lat': 0, 'lon': -180.5},
      ]) {
        bad(readMap({...good(), 'place': p}), '$p');
      }
    });
  });

  group('refusals', () {
    Map<String, Object?> good() => jsonOf(BlessingRecord.of(surgery));

    test('newer version: recognised as newer, whatever else it holds', () {
      final r = readMap({'format': 'upon-thy-head/blessing', 'version': 3, 'something': 'new'});
      expect(r, isA<BlessingReadNewer>());
      expect((r as BlessingReadNewer).version, 3);
    });

    test('rubbish, empty, not UTF-8, not JSON, not an object, not ours', () {
      bad(readBlessingFile(const []));
      bad(readBlessingFile([0xff, 0xfe, 0x00, 0x41]));
      bad(readBlessingFile(utf8.encode('hello')));
      bad(readBlessingFile(utf8.encode('[1, 2, 3]')));
      bad(readMap({'version': 1, 'id': 'x'}));
      bad(readMap({...good(), 'format': 'something/else'}));
      bad(readMap({...good(), 'version': '1'}));
      bad(readMap({...good(), 'version': 0}));
    });

    test('over the size limit, even when it is a real blessing inside', () {
      final big = {...good(), 'padding': 'x' * (blessingFileMaxBytes + 10)};
      bad(readMap(big), 'size');
    });

    test('unknown fields are ignored', () {
      final r = ok(readMap({...good(), 'colour': 'blue', 'extra': {'a': 1}}));
      expect(r.title, 'Comfort before surgery');
    });

    test('a missing or empty title falls back to the untitled blessing', () {
      final m = good()..remove('title');
      expect(ok(readMap(m)).title, Strings.untitled);
      expect(ok(readMap({...good(), 'title': '   '})).title, Strings.untitled);
    });

    test('each required field missing', () {
      for (final k in ['id', 'given', 'offset', 'words']) {
        bad(readMap(good()..remove(k)), k);
      }
    });

    test('every field checked: types, lengths, patterns', () {
      final cases = <String, Object?>{
        'id': 'has spaces',
        'title': 'x' * (BlessingLimits.title + 1),
        'from': 'y' * (BlessingLimits.name + 1),
        'for': 42,
        'given': '2026-02-30T10:00Z',
        'offset': 19 * 60,
        'language': 'english please',
        'tags': ['ok', 7],
        'words': 'x' * (BlessingLimits.words + 1),
        'changes': 'none',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        bad(readMap({...good(), key: value}), key);
      }
      bad(readMap({...good(), 'given': '3026-01-01T00:00Z'}), 'far future');
      bad(readMap({...good(), 'given': '1850-01-01T00:00Z'}), 'too early');
      bad(readMap({...good(), 'tags': List.filled(BlessingLimits.tags + 1, 'a')}), 'too many tags');
    });

    test('control characters and broken characters', () {
      bad(readMap({...good(), 'title': 'a\u0000b'}));
      bad(readMap({...good(), 'from': 'line\nbreak'}));
      bad(readMap({...good(), 'title': 'half \ud83d'}));
      bad(readMap({...good(), 'words': 'bell \u0007'}));
      // line breaks are fine in the words
      expect(ok(readMap({...good(), 'words': 'one\n\ntwo', 'changes': []})).spoken, 'one\n\ntwo');
    });

    test('changes must stand on the words, in order, not overlapping, of a known kind', () {
      final words = 'Um, be still, be still and know.';
      Map<String, Object?> withChanges(List<Map<String, Object?>> cs) => {...good(), 'words': words, 'changes': cs};
      Map<String, Object?> c(int at, String was, {String now = '', String kind = 'filler', Object kept = true}) =>
          {'at': at, 'was': was, 'now': now, 'kind': kind, 'source': 'rules', 'kept': kept};
      expect(ok(readMap(withChanges([c(0, 'Um, ', now: 'B'), c(14, 'be still ', kind: 'repeat')]))).changes.length, 2);
      bad(readMap(withChanges([c(1, 'Um, ')])), 'not where it says');
      bad(readMap(withChanges([c(30, 'know. and more')])), 'past the end');
      bad(readMap(withChanges([c(14, 'be still '), c(0, 'Um, ')])), 'out of order');
      bad(readMap(withChanges([c(0, 'Um, be'), c(4, 'be')])), 'overlapping');
      bad(readMap(withChanges([c(0, 'Um, ', kind: 'magic')])), 'unknown kind');
      bad(readMap(withChanges([c(0, 'Um, ', kept: 'yes')])), 'kept not a bool');
      bad(readMap(withChanges([c(0, '')])), 'empty was');
    });

    test('nothing in it is fetched or run: a link or script is only text', () {
      final r = ok(readMap({...good(), 'title': '<script>alert(1)</script> https://example.com', 'words': 'See https://example.com', 'changes': []}));
      expect(r.title, '<script>alert(1)</script> https://example.com');
    });
  });
}
