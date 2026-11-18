// Family members: who is kept on this phone, whose ring each blessing is on, and the store's part.
//
//   flutter test test/people_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/record/recovery.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/strings.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('people');
    path = '${dir.path}/blessings.sqlite';
  });
  tearDown(() {
    Strings.use(UiLanguage.english);
    dir.deleteSync(recursive: true);
  });

  Blessing make(String id, DateTime utc, {String personId = '', Ownership owner = Ownership.forMe, String audio = ''}) => Blessing(
        id: id,
        title: 'Title $id',
        from: 'Giver $id',
        recipient: '',
        utc: utc,
        utcOffset: Duration.zero,
        place: const Place(40.23, -111.66),
        ownership: owner,
        personId: personId,
        rawText: 'words $id',
        audio: audio,
        draft: false,
        created: DateTime.utc(2026, 1, 1),
      );

  group('a person', () {
    test('ids are long, random and never repeat', () {
      final ids = {for (var i = 0; i < 500; i++) newPerson('Emma').id};
      expect(ids, hasLength(500));
      expect(ids.every((id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id)), isTrue);
    });

    test('a name is trimmed, its spaces made single, and kept to the limit', () {
      expect(cleanName('  Emma   Rose \n'), 'Emma Rose');
      expect(cleanName('x' * 200).length, nameLimit);
      expect(cleanName('   '), '');
    });

    test('a birth date reads back as the same day, whatever the zone', () {
      final d = Day(2008, 8, 3);
      expect(d.code, '2008-08-03');
      expect(Day.parse('2008-08-03'), d);
      expect(Day.parse(null), isNull);
      expect(Day.parse('nonsense'), isNull);
      expect(d.local, DateTime(2008, 8, 3));
    });

    test('whose: me, a family member, or passing it along, and applied to a blessing', () {
      final b = make('a', DateTime.utc(2026, 1, 1));
      expect(Whose.ofBlessing(b), Whose.me);
      WhosePerson('p1').apply(b);
      expect((b.ownership, b.personId), (Ownership.forMe, 'p1'));
      expect(Whose.ofBlessing(b), WhosePerson('p1'));
      Whose.passing.apply(b);
      expect((b.ownership, b.personId), (Ownership.passingOn, ''), reason: 'passing along belongs to no ring');
      Whose.me.apply(b);
      expect((b.ownership, b.personId), (Ownership.forMe, ''));
    });
  });

  group('the store', () {
    test('a version 7 file keeps every blessing, all for me, and gains an empty family', () async {
      var db = sqlite3.open(path);
      SqliteBlessingStore.migrateTo(db, 7);
      db.execute("INSERT INTO blessings (id, title, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
          "raw_text, polished_text, draft, created_at_ms, updated_at_ms, first_text) VALUES "
          "('a', 'A', 'for_me', 29000000, 0, 40.2, -111.6, 'words', '', 0, 5, 6, 'words'), "
          "('b', 'B', 'for_me', 29000100, 0, 40.2, -111.6, 'words', '', 1, 5, 6, 'words'), "
          "('c', 'C', 'passing_on', 29000200, 0, 40.2, -111.6, 'words', '', 0, 5, 6, 'words')");
      db.close();

      final s = SqliteBlessingStore.open(path);
      expect(await s.people(), isEmpty);
      final all = await s.list();
      expect([for (final b in all) b.id]..sort(), ['a', 'b', 'c'], reason: 'nothing lost, nothing doubled');
      expect(all.every((b) => b.personId.isEmpty), isTrue);
      final f = Family(await s.people(), await s.list(ownership: Ownership.forMe));
      expect([for (final b in f.on('')) b.id], ['a', 'b']);
      expect(f.on('').where((b) => b.draft), hasLength(1));
      await s.close();
      db = sqlite3.open(path);
      expect(db.userVersion, SqliteBlessingStore.schemaVersion);
      db.close();
    });

    test('family members are added, changed and read back in the order they were added', () async {
      final s = SqliteBlessingStore.open(path);
      final emma = newPerson('Emma', born: Day(2008, 8, 3));
      final james = newPerson('James');
      await s.addPerson(emma);
      await s.addPerson(james);
      expect([for (final p in await s.people()) p.name], ['Emma', 'James']);
      expect((await s.people()).first.born, Day(2008, 8, 3));
      expect((await s.people()).last.born, isNull);

      await s.updatePerson(Person(id: emma.id, name: 'Emma Rose', created: emma.created));
      final back = (await s.people()).first;
      expect((back.id, back.name, back.born), (emma.id, 'Emma Rose', null));
      expect(() => s.updatePerson(newPerson('Nobody')), throwsStateError);
      await s.close();
    });

    test('a blessing keeps its ring through a save; passing along keeps none', () async {
      final s = SqliteBlessingStore.open(path);
      final emma = newPerson('Emma');
      await s.addPerson(emma);
      await s.create(make('a', DateTime.utc(2026, 1, 1), personId: emma.id));
      expect((await s.get('a'))!.personId, emma.id);
      final b = (await s.get('a'))!;
      b.ownership = Ownership.passingOn; // the store, not the caller, keeps a passed one off every ring
      await s.update(b);
      expect((await s.get('a'))!.personId, '');
      await s.close();
    });

    test('removing a family member removes their blessings and recordings, and nothing of anyone else', () async {
      final audioDir = Directory('${dir.path}/audio')..createSync();
      final s = SqliteBlessingStore.open(path, audioDir: audioDir.path);
      final emma = newPerson('Emma'), james = newPerson('James');
      await s.addPerson(emma);
      await s.addPerson(james);
      for (final name in ['e1.m4a', 'e2.m4a', 'm1.m4a', 'j1.m4a']) {
        File('${audioDir.path}/$name').writeAsStringSync('x');
      }
      await s.create(make('e1', DateTime.utc(2026, 1, 1), personId: emma.id, audio: 'e1.m4a'));
      await s.create(make('e2', DateTime.utc(2026, 1, 2), personId: emma.id, audio: 'e2.m4a'));
      await s.create(make('m1', DateTime.utc(2026, 1, 3), audio: 'm1.m4a'));
      await s.create(make('j1', DateTime.utc(2026, 1, 4), personId: james.id, audio: 'j1.m4a'));
      await s.create(make('p1', DateTime.utc(2026, 1, 5), owner: Ownership.passingOn));

      await s.removePerson(emma.id);
      expect([for (final p in await s.people()) p.name], ['James']);
      expect([for (final b in await s.list()) b.id]..sort(), ['j1', 'm1', 'p1']);
      expect(File('${audioDir.path}/e1.m4a').existsSync(), isFalse);
      expect(File('${audioDir.path}/e2.m4a').existsSync(), isFalse);
      expect(File('${audioDir.path}/m1.m4a').existsSync(), isTrue);
      expect(File('${audioDir.path}/j1.m4a').existsSync(), isTrue);

      await s.removePerson('');
      expect(await s.count(), 3, reason: 'the person\'s own ring is never removed');
      await s.close();
    });
  });

  group('the family', () {
    final emma = Person(id: 'e', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.utc(2026));
    final james = Person(id: 'j', name: 'James', created: DateTime.utc(2026));

    test('each blessing is on one ring; an unknown ring is kept with mine; passing ones on none', () {
      final f = Family([emma, james], [
        make('m1', DateTime.utc(2026, 2, 1)),
        make('e1', DateTime.utc(2026, 3, 1), personId: 'e'),
        make('e0', DateTime.utc(2026, 1, 1), personId: 'e')..draft = true,
        make('x1', DateTime.utc(2026, 4, 1), personId: 'gone'),
        make('p1', DateTime.utc(2026, 5, 1), owner: Ownership.passingOn),
      ]);
      expect([for (final b in f.on('')) b.id], ['m1', 'x1']);
      expect([for (final b in f.on('e')) b.id], ['e0', 'e1'], reason: 'oldest first');
      expect(f.on('j'), isEmpty);
      expect([for (final b in f.on('e')) b.draft], [true, false]);
      expect(f.known('e'), 'e');
      expect(f.known('gone'), '');
      expect(f.title(''), 'For me');
      expect(f.title('e'), 'For Emma');
    });

    test('the menu: me and each one with their count and a tick on the one showing, then add and manage', () {
      final f = Family([emma, james], [
        make('m1', DateTime.utc(2025, 6, 1)),
        make('e1', DateTime.utc(2026, 3, 1), personId: 'e')..draft = true,
      ]);
      final items = f.menu('e');
      expect([for (final i in items) i.code], ['me', 'p:e', 'p:j', 'add', 'manage']);
      expect([for (final i in items) i.label], ['For me', 'For Emma', 'For James', 'Add a family member', 'Manage family']);
      expect([for (final i in items) i.ticked], [false, true, false, false, false]);
      expect(items[0].sub, 'One blessing since June 2025');
      expect(items[1].sub, 'One blessing since March 2026', reason: 'a draft waiting is said by the badge on home, not here');
      expect(items[2].sub, Strings.countLine(0, DateTime(0)));
      expect(items[3].groupStart, isTrue);
      expect([for (final i in items) SkyMenu.ringOf(i.code)], ['', 'e', 'j', null, null]);
    });

    test('with nobody added, the menu is For me and Add, no Manage', () {
      final items = Family(const [], const []).menu('');
      expect([for (final i in items) i.code], ['me', 'add']);
      expect(items.first.ticked, isTrue);
    });

    test('in Spanish', () {
      Strings.use(UiLanguage.spanish);
      final f = Family([emma], const []);
      expect([for (final i in f.menu('')) i.label], ['Para mí', 'Para Emma', 'Agregar a un familiar', 'Administrar la familia']);
    });
  });

  group('the ring begins on the birth date', () {
    test('a birth date before the first blessing moves the start of the ring back', () {
      final now = DateTime(2026, 6, 1);
      final bs = [make('a', DateTime.utc(2024, 6, 1)), make('b', DateTime.utc(2025, 6, 1))];
      final without = RingPlacement.angles(bs, now);
      final withBirth = RingPlacement.angles(bs, now, begins: DateTime(2008, 8, 3));
      expect(withBirth.at[0], greaterThan(without.at[0]), reason: 'the first light is no longer at the very start');
    });

    test('a birth date after the first blessing changes nothing', () {
      final now = DateTime(2026, 6, 1);
      final bs = [make('a', DateTime.utc(2024, 6, 1)), make('b', DateTime.utc(2025, 6, 1))];
      expect(RingPlacement.angles(bs, now, begins: DateTime(2025, 1, 1)).at, RingPlacement.angles(bs, now).at);
    });
  });

  test('the last sky showing is remembered, and forgetting it means mine', () async {
    final s = await Settings.open('${dir.path}/settings.json');
    expect(s.sky, '');
    await s.setSky('abc');
    expect((await Settings.open('${dir.path}/settings.json')).sky, 'abc');
    await s.setSky('');
    expect((await Settings.open('${dir.path}/settings.json')).sky, '');
  });

  test('a recording begun for a family member is recovered onto their ring', () {
    final draft = draftBlessing(DateTime.utc(2026, 1, 1), place: const Place(40, -111), personId: 'e');
    final note = RecordingNote.of(draft);
    final again = RecordingNote.fromJson(note.toJson())!;
    expect(again.personId, 'e');
    expect(again.toBlessing(audio: 'a.m4a', now: DateTime.utc(2026, 1, 1)).personId, 'e');
    expect(again.toBlessing(audio: 'a.m4a', now: DateTime.utc(2026, 1, 1), personId: '').personId, '',
        reason: 'when they have since been removed, it is kept as mine');
    final mine = RecordingNote.of(draftBlessing(DateTime.utc(2026, 1, 1), place: const Place(40, -111)));
    expect(mine.toJson().containsKey('person'), isFalse, reason: 'a note written for me reads as the old ones did');
  });
}
