// Entering a past blessing from a written copy (design/entry-and-rings, Part A): the three ways a
// date can be known, how each reads in both languages, where its light sits, the store's version 9,
// and the blessing file and link carrying both.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/strings.dart';

Blessing entered(String id, DatePrecision p, int y, [int m = 1, int d = 1]) {
  final b = enteredBlessing(DateTime(2026, 11, 18), place: samplePlace)
    ..title = 'Before college'
    ..from = 'Dad'
    ..rawText = 'Daniel, by the authority of the Melchizedek Priesthood which I hold.\nI bless you.\n\nAmen.'
    ..draft = false;
  setGiven(b, p, y, m, d);
  return Blessing(
    id: id,
    title: b.title,
    from: b.from,
    utc: b.utc,
    utcOffset: b.utcOffset,
    place: b.place,
    rawText: b.rawText,
    draft: false,
    entered: true,
    precision: p,
  );
}

void main() {
  final en = Strings.wordsFor(UiLanguage.english), es = Strings.wordsFor(UiLanguage.spanish);
  tearDown(() => Strings.use(UiLanguage.english));

  group('how each reads', () {
    final day = entered('day', DatePrecision.day, 1998, 8, 23);
    final month = entered('month', DatePrecision.month, 1998, 8);
    final year = entered('year', DatePrecision.year, 1998);

    test('English: the day, the month, the year', () {
      Strings.use(UiLanguage.english);
      expect(day.longDate, 'Sunday, August 23, 1998');
      expect(month.longDate, 'August 1998');
      expect(year.longDate, '1998');
      expect(day.shortDate, 'Aug 23, 1998');
      expect(month.shortDate, 'Aug 1998');
      expect(year.shortDate, '1998');
    });

    test('Spanish: el día, el mes, el año', () {
      Strings.use(UiLanguage.spanish);
      expect(day.longDate, 'domingo, 23 de agosto de 1998');
      expect(month.longDate, 'agosto de 1998');
      expect(year.longDate, '1998');
      expect(month.shortDate, 'ago 1998');
      expect(year.shortDate, '1998');
    });

    test('the count line reaches back to the first, by what is known of it', () {
      final five = sampleBlessings().where((b) => b.ownership == Ownership.forMe).toList();
      expect(countLine([...five, month]), startsWith('${en.count(five.length + 1)} blessings since August 1998'));
      expect(countLine([...five, year]), endsWith('since 1998'));
      Strings.use(UiLanguage.spanish);
      expect(countLine([...five, month]), endsWith('desde agosto de 1998'));
      expect(countLine([...five, year]), endsWith('desde 1998'));
      expect(es.countLine(6, DateTime(1998), yearOnly: true), 'Seis bendiciones desde 1998');
      expect(en.countLine(6, DateTime(1998, 8)), 'Six blessings since August 1998');
    });

    test('the date sheet\'s line under the wheels', () {
      expect(en.precisionNote(DatePrecision.month, DateTime(1998, 8, 15)), 'Only the month is known. Its light sits at mid-August 1998.');
      expect(en.precisionNote(DatePrecision.year, DateTime(1998, 7, 2)), 'Only the year is known. Its light sits at mid-1998.');
      expect(es.precisionNote(DatePrecision.month, DateTime(1998, 8, 15)), 'Solo se sabe el mes. Su luz se sitúa a mediados de agosto de 1998.');
      expect(es.precisionNote(DatePrecision.year, DateTime(1998, 7, 2)), 'Solo se sabe el año. Su luz se sitúa a mediados de 1998.');
      expect(en.precisionNote(DatePrecision.day, DateTime(1998, 8, 23)), '');
    });

    test('shared text, PDF and its file name say only what is known', () {
      expect(shareText(year, en).split('\n')[1], '1998');
      expect(shareText(month, es).split('\n')[1], 'agosto de 1998');
      expect(sharePdf(year, en)['date'], '1998');
      expect(shareFileName(year, en), 'Before college, 1998.pdf');
      expect(shareFileName(month, en), 'Before college, August 1998.pdf');
      expect(shareFileName(day, en), 'Before college, August 23, 1998.pdf');
      expect(shareFileName(month, es), 'Before college, agosto de 1998.pdf');
    });
  });

  group('where its light sits', () {
    test('noon of the day, the 15th, July 2; on the phone\'s clock for that date', () {
      expect(entered('a', DatePrecision.day, 1998, 8, 23).local, DateTime.utc(1998, 8, 23, 12));
      expect(entered('b', DatePrecision.month, 1998, 8).local, DateTime.utc(1998, 8, 15, 12));
      expect(entered('c', DatePrecision.year, 1998).local, DateTime.utc(1998, 7, 2, 12));
    });

    test('a year-only light is ordered by its middle day among full dates of the same year', () {
      final year = entered('y', DatePrecision.year, 1998);
      final march = entered('m', DatePrecision.day, 1998, 3, 1), november = entered('n', DatePrecision.day, 1998, 11, 1);
      final f = Family(const [], [november, year, march]);
      expect([for (final b in f.on('')) b.id], ['m', 'y', 'n']);
    });

    test('the earliest moves the ring\'s start back, and the others come closer together', () {
      final five = sampleBlessings().where((b) => b.ownership == Ownership.forMe).toList()..sort((a, b) => a.utc.compareTo(b.utc));
      final now = DateTime.utc(2026, 11, 18);
      final before = RingPlacement.angles(five, now).at;
      final year = entered('y', DatePrecision.year, 1998);
      final after = RingPlacement.angles([year, ...five], now).at;
      expect(after.first, 0);
      // the same five, now in the last part of a 28-year ring
      expect(after.last - after[1], lessThan(before.last - before.first));
      expect(after[1], greaterThan(250));
    });

    test('entered on a family member\'s sky: on her ring only', () {
      final emma = Person(id: 'emma', name: 'Emma', created: DateTime.utc(2026));
      final e = enteredBlessing(DateTime(2026, 11, 18), place: samplePlace, personId: 'emma')
        ..rawText = 'Emma, I bless you.'
        ..draft = false;
      setGiven(e, DatePrecision.year, 2016);
      final mine = sampleBlessings();
      final f = Family([emma], [...mine, e]);
      expect([for (final b in f.on('emma')) b.id], [e.id]);
      expect(f.on('').any((b) => b.id == e.id), isFalse);
      expect(f.on('').length, mine.where((b) => b.ownership == Ownership.forMe || b.personId.isEmpty).length);
    });

    test('an entry with no date yet is on no ring, and counts nowhere', () {
      final draft = enteredBlessing(DateTime(2026, 11, 18), place: samplePlace);
      final f = Family(const [], [...sampleBlessings(), draft]);
      expect(f.on('').any((b) => b.id == draft.id), isFalse);
      expect(f.unplaced.map((b) => b.id), [draft.id]);
      expect(isEmptyEntry(draft), isTrue);
      draft.rawText = 'I';
      expect(isEmptyEntry(draft), isFalse);
    });

    test('paragraphs entered are kept: each line break ends one; a recording\'s only a blank line', () {
      final b = entered('p', DatePrecision.year, 1998);
      expect(b.paragraphs, ['Daniel, by the authority of the Melchizedek Priesthood which I hold.', 'I bless you.', 'Amen.']);
      final r = Blessing(id: 'r', title: 'x', from: '', utc: b.utc, utcOffset: b.utcOffset, place: b.place, rawText: b.rawText);
      expect(r.paragraphs.length, 2);
    });
  });

  group('the store, version 9', () {
    late String path;
    setUp(() => path = '${Directory.systemTemp.createTempSync('entry').path}/b.sqlite');

    test('a version 8 file: every blessing recorded, on a known day, nothing lost', () async {
      var db = sqlite3.open(path);
      SqliteBlessingStore.migrateTo(db, 8);
      db.execute("INSERT INTO blessings (id, title, giver, recipient, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
          "raw_text, polished_text, draft, created_at_ms, updated_at_ms, audio, language, first_text, person_id) VALUES "
          "('old', 'Comfort', 'Dad', 'Emma', 'for_me', 29000000, -420, 40.2, -111.6, 'I bless you', 'I bless you', 0, 5, 6, '', 'en', 'I bless you', '')");
      db.close();
      final s = SqliteBlessingStore.open(path);
      final b = (await s.get('old'))!;
      expect(b.precision, DatePrecision.day);
      expect(b.entered, isFalse);
      expect(b.title, 'Comfort');
      expect(b.rawText, 'I bless you');
      await s.close();
      db = sqlite3.open(path);
      expect(db.userVersion, 10);
      expect(SqliteBlessingStore.schemaVersion, 10);
      db.close();
    });

    test('each precision and entered are kept and read back; one with no date yet too', () async {
      final s = SqliteBlessingStore.open(path);
      for (final p in DatePrecision.values) {
        final b = entered(p.code, p == DatePrecision.unset ? DatePrecision.day : p, 1998, 8, 23)..precision = p;
        await s.create(b);
        final back = (await s.get(p.code))!;
        expect(back.precision, p);
        expect(back.entered, isTrue);
        expect(back.utc, b.utc);
      }
      final b = (await s.get('year'))!;
      setGiven(b, DatePrecision.day, 1998, 9, 1);
      await s.update(b);
      expect((await s.get('year'))!.precision, DatePrecision.day);
      expect((await s.get('year'))!.longDate, 'Tuesday, September 1, 1998');
      await s.close();
    });
  });

  group('the blessing file and the link', () {
    test('recorded on a known day: version 1, exactly as before', () {
      final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
      final j = jsonDecode(utf8.decode(BlessingRecord.of(surgery).toFileBytes())) as Map;
      expect(j['version'], 1);
      expect(j.containsKey('precision'), isFalse);
      expect(j.containsKey('entered'), isFalse);
    });

    test('entered, year only: version 2, and it comes back as 1998 and entered', () {
      final b = entered('y1998', DatePrecision.year, 1998);
      final r = BlessingRecord.of(b);
      final j = jsonDecode(utf8.decode(r.toFileBytes())) as Map;
      expect(j['version'], 2);
      expect(j['precision'], 'year');
      expect(j['entered'], true);
      final back = (readBlessingFile(r.toFileBytes()) as BlessingReadOk).record;
      expect(back.precision, DatePrecision.year);
      expect(back.entered, isTrue);
      expect(back.sameAs(b), isTrue);
      final kept = back.toBlessing(place: samplePlace);
      expect(kept.longDate, '1998');
      expect(kept.entered, isTrue);
      expect(kept.paragraphs, b.paragraphs);
      // the compact copy (the link's) the same
      expect((readBlessingJson(utf8.decode(r.toCompactBytes())) as BlessingReadOk).record.precision, DatePrecision.year);
    });

    test('a file made before version 2 still reads: a full date, as spoken', () {
      final old = {
        'format': 'upon-thy-head/blessing',
        'version': 1,
        'id': 'old',
        'title': 'Comfort',
        'given': '2026-03-03T16:40Z',
        'offset': -420,
        'words': 'I bless you',
      };
      final r = (readBlessingFile(utf8.encode(jsonEncode(old))) as BlessingReadOk).record;
      expect(r.precision, DatePrecision.day);
      expect(r.entered, isFalse);
    });

    test('an unknown precision, or entered that is not true or false, refuses the file', () {
      Map<String, Object> f(Map<String, Object> extra) =>
          {'format': 'upon-thy-head/blessing', 'version': 2, 'id': 'x', 'given': '1998-07-02T18:00Z', 'offset': -360, 'words': 'w', ...extra};
      expect(readBlessingFile(utf8.encode(jsonEncode(f({'precision': 'week'})))), isA<BlessingReadBad>());
      expect(readBlessingFile(utf8.encode(jsonEncode(f({'entered': 'yes'})))), isA<BlessingReadBad>());
      expect(readBlessingFile(utf8.encode(jsonEncode(f({'precision': 'month'})))), isA<BlessingReadOk>());
    });
  });
}
