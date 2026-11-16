// The blessings store against a real SQLite file.
//
//   flutter test test/store_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/sky/astro.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('blessings');
    path = '${dir.path}/blessings.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Blessing make(String id, DateTime utc, {Ownership owner = Ownership.forMe}) => Blessing(
        id: id,
        title: 'Title $id',
        from: 'Giver $id',
        recipient: 'Emma',
        utc: utc,
        utcOffset: const Duration(hours: -7),
        place: const Place(40.23, -111.66),
        ownership: owner,
        rawText: 'raw, um, $id',
        changes: [Change(start: 3, was: ', um,', now: '', kind: ChangeKind.filler)],
        polishAsked: true,
        tags: const ['comfort', 'family'],
        draft: true,
        created: DateTime.utc(2026, 1, 1, 12),
      );

  test('create and read back every field', () async {
    final s = SqliteBlessingStore.open(path);
    final b = make('a', DateTime.utc(2026, 3, 3, 16, 40, 27));
    await s.create(b);
    final r = (await s.get('a'))!;
    expect(r.title, 'Title a');
    expect(r.from, 'Giver a');
    expect(r.recipient, 'Emma');
    expect(r.ownership, Ownership.forMe);
    expect(r.utc, DateTime.utc(2026, 3, 3, 16, 40), reason: 'kept to the minute');
    expect(r.utcOffset, const Duration(hours: -7));
    expect(r.local.day, 3);
    expect(r.place.lat, 40.23);
    expect(r.place.lon, -111.66);
    expect(r.rawText, 'raw, um, a');
    expect(r.polishedText, 'raw a');
    expect(r.changes.single.start, 3);
    expect(r.changes.single.was, ', um,');
    expect(r.changes.single.now, '');
    expect(r.changes.single.kind, ChangeKind.filler);
    expect(r.changes.single.source, 'rules');
    expect(r.changes.single.kept, isTrue);
    expect(r.polishAsked, isTrue);
    expect(r.tags, ['comfort', 'family']);
    expect(r.draft, isTrue);
    expect(r.created, DateTime.utc(2026, 1, 1, 12));
    expect(r.updated, DateTime.utc(2026, 1, 1, 12));
    expect(await s.get('missing'), isNull);
    expect(await s.count(), 1);
    await s.close();
  });

  test('update changes the fields and the updated time', () async {
    final s = SqliteBlessingStore.open(path);
    await s.create(make('a', DateTime.utc(2026, 3, 3)));
    final b = (await s.get('a'))!
      ..title = 'Comfort'
      ..from = 'Dad'
      ..tags = ['peace']
      ..draft = false;
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    await s.update(b);
    final r = (await s.get('a'))!;
    expect(r.title, 'Comfort');
    expect(r.from, 'Dad');
    expect(r.tags, ['peace']);
    expect(r.draft, isFalse);
    expect(r.created, DateTime.utc(2026, 1, 1, 12));
    expect(r.updated.isAfter(before), isTrue);
    expect(() => s.update(make('nobody', DateTime.utc(2026))), throwsStateError);
    await s.close();
  });

  test('delete removes the blessing and its tags', () async {
    final s = SqliteBlessingStore.open(path);
    await s.create(make('a', DateTime.utc(2026, 3, 3)));
    await s.create(make('b', DateTime.utc(2026, 4, 3)));
    await s.delete('a');
    expect(await s.get('a'), isNull);
    expect((await s.list()).map((b) => b.id), ['b']);
    await s.close();
    final db = sqlite3.open(path);
    expect(db.select("SELECT count(*) AS n FROM blessing_tags WHERE blessing_id = 'a'").first['n'], 0);
    db.close();
  });

  test('list is ordered by the time given, oldest first', () async {
    final s = SqliteBlessingStore.open(path);
    await s.create(make('mid', DateTime.utc(2025, 8, 24)));
    await s.create(make('new', DateTime.utc(2026, 10, 5)));
    await s.create(make('old', DateTime.utc(2024, 6, 3)));
    expect((await s.list()).map((b) => b.id), ['old', 'mid', 'new']);
    await s.close();
  });

  test('the "for me" filter', () async {
    final s = SqliteBlessingStore.open(path);
    await s.create(make('mine', DateTime.utc(2025)));
    await s.create(make('theirs', DateTime.utc(2024), owner: Ownership.passingOn));
    expect((await s.list(ownership: Ownership.forMe)).map((b) => b.id), ['mine']);
    expect((await s.list(ownership: Ownership.passingOn)).map((b) => b.id), ['theirs']);
    expect((await s.list()).map((b) => b.id), ['theirs', 'mine']);
    await s.close();
  });

  test('reopening the file keeps everything', () async {
    var s = SqliteBlessingStore.open(path);
    expect(await seedSamplesIfEmpty(s), isTrue);
    final b = (await s.get('surgery'))!..title = 'Before the operation';
    await s.update(b);
    await s.delete('job');
    await s.close();

    s = SqliteBlessingStore.open(path);
    final all = await s.list(ownership: Ownership.forMe);
    expect(all.map((b) => b.id), ['fever', 'baby', 'primary', 'surgery']);
    expect(all[3].title, 'Before the operation');
    expect(all[3].words, startsWith('Emma, I lay my hands upon your head to give'));
    expect(all[3].changes, hasLength(5));
    expect(all[3].words, surgeryPolished);
    expect(all[0].hasWords, isFalse);
    expect(await seedSamplesIfEmpty(s), isFalse, reason: 'seeding only fills an empty store');
    await s.close();
  });

  test('schema version is recorded, and a newer file is refused', () async {
    var s = SqliteBlessingStore.open(path);
    await s.close();
    final db = sqlite3.open(path);
    expect(db.userVersion, SqliteBlessingStore.schemaVersion);
    db.userVersion = SqliteBlessingStore.schemaVersion + 1;
    db.close();
    expect(() => SqliteBlessingStore.open(path), throwsStateError);
  });

  test('a blessing\'s recording: kept with it, erased on review, deleted with it', () async {
    final audio = Directory('${dir.path}/audio')..createSync();
    final s = SqliteBlessingStore.open(path, audioDir: audio.path);
    File('${audio.path}/a.m4a').writeAsBytesSync([1, 2, 3]);
    File('${audio.path}/b.m4a').writeAsBytesSync([4, 5, 6]);
    final a = make('a', DateTime.utc(2026, 3, 3))
      ..audio = 'a.m4a'
      ..language = 'es';
    final b = make('b', DateTime.utc(2026, 3, 4))..audio = 'b.m4a';
    await s.create(a);
    await s.create(b);
    final r = (await s.get('a'))!;
    expect(r.audio, 'a.m4a');
    expect(r.language, 'es');
    expect(s.audioPath(r), '${audio.path}/a.m4a');

    // the review step: the words stay, the recording goes
    await s.eraseAudio(r);
    expect(File('${audio.path}/a.m4a').existsSync(), isFalse);
    expect((await s.get('a'))!.audio, '');
    expect((await s.get('a'))!.rawText, 'raw, um, a');
    expect(s.audioPath((await s.get('a'))!), isNull);

    // deleting a blessing deletes its recording
    await s.delete('b');
    expect(File('${audio.path}/b.m4a').existsSync(), isFalse);

    // a name that is not a plain file name in the folder is never deleted
    final outside = File('${dir.path}/keep.m4a')..writeAsBytesSync([7]);
    await s.create(make('c', DateTime.utc(2026, 3, 5))..audio = '../keep.m4a');
    await s.delete('c');
    expect(outside.existsSync(), isTrue);
    await s.close();
  });

  test('a version 1 file gains the recording columns and keeps its blessings', () async {
    final db = sqlite3.open(path);
    db.execute('''CREATE TABLE blessings (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, giver TEXT NOT NULL DEFAULT '',
      recipient TEXT NOT NULL DEFAULT '', ownership TEXT NOT NULL CHECK (ownership IN ('for_me', 'passing_on')),
      given_utc_minute INTEGER NOT NULL, utc_offset_minutes INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
      raw_text TEXT NOT NULL DEFAULT '', polished_text TEXT NOT NULL DEFAULT '', edits_json TEXT NOT NULL DEFAULT '[]',
      draft INTEGER NOT NULL DEFAULT 1, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL) STRICT''');
    db.execute('''CREATE TABLE blessing_tags (blessing_id TEXT NOT NULL REFERENCES blessings (id) ON DELETE CASCADE,
      tag TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (blessing_id, tag)) STRICT''');
    db.execute("INSERT INTO blessings (id, title, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
        "raw_text, created_at_ms, updated_at_ms) VALUES ('old', 'Old', 'for_me', 29000000, -420, 40.2, -111.6, 'words', 0, 0)");
    db.userVersion = 1;
    db.close();
    final s = SqliteBlessingStore.open(path);
    final r = (await s.get('old'))!;
    expect(r.rawText, 'words');
    expect(r.audio, '');
    expect(r.language, '');
    await s.close();
    final again = sqlite3.open(path);
    expect(again.userVersion, SqliteBlessingStore.schemaVersion);
    again.close();
  });

  test('a version 2 file gains the first writing of the words, copied from the words, and loses nothing', () async {
    // a version 2 file as the last release wrote it, made by the code's own first two steps
    var db = sqlite3.open(path);
    SqliteBlessingStore.migrateTo(db, 2);
    db.execute("INSERT INTO blessings (id, title, giver, recipient, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
        "raw_text, polished_text, edits_json, draft, created_at_ms, updated_at_ms, audio, language) VALUES "
        "('d', 'Blessing', 'Dad', 'Emma', 'for_me', 29000000, -420, 40.2, -111.6, 'I bless you with pieces', '', '[]', 1, 5, 6, 'd.m4a', 'en'), "
        "('f', 'Done', '', '', 'passing_on', 29000001, -360, 40.3, -111.7, '', '', '[]', 0, 7, 8, '', '')");
    db.execute("INSERT INTO blessing_tags (blessing_id, tag, position) VALUES ('d', 'Comfort', 0), ('d', 'Family', 1)");
    db.close();

    final s = SqliteBlessingStore.open(path);
    final d = (await s.get('d'))!, f = (await s.get('f'))!;
    expect(d.firstText, 'I bless you with pieces', reason: 'until now the words were the first writing');
    expect(d.rawText, 'I bless you with pieces');
    expect(d.title, 'Blessing');
    expect(d.from, 'Dad');
    expect(d.recipient, 'Emma');
    expect(d.tags, ['Comfort', 'Family']);
    expect(d.rawText, 'I bless you with pieces');
    expect(d.draft, isTrue);
    expect(d.audio, 'd.m4a');
    expect(d.language, 'en');
    expect(d.created.millisecondsSinceEpoch, 5);
    expect(d.updated.millisecondsSinceEpoch, 6);
    expect(f.firstText, '');
    expect(f.ownership, Ownership.passingOn);
    expect(f.draft, isFalse);
    await s.close();
    db = sqlite3.open(path);
    expect(db.userVersion, SqliteBlessingStore.schemaVersion);
    db.close();
  });

  test('a version 3 file marks drafts with a recording and no words as still to be written', () async {
    var db = sqlite3.open(path);
    SqliteBlessingStore.migrateTo(db, 3);
    db.execute("INSERT INTO blessings (id, title, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
        "raw_text, draft, created_at_ms, updated_at_ms, audio, language, first_text) VALUES "
        "('waiting', 'Blessing', 'for_me', 29000000, -420, 40.2, -111.6, '', 1, 5, 6, 'waiting.m4a', 'en', ''), "
        "('heard', 'Blessing', 'for_me', 29000001, -420, 40.2, -111.6, 'words', 1, 5, 6, 'heard.m4a', 'en', 'words'), "
        "('done', 'Done', 'for_me', 29000002, -420, 40.2, -111.6, '', 0, 5, 6, '', '', ''), "
        "('typed', 'Old', 'for_me', 29000003, -420, 40.2, -111.6, '', 1, 5, 6, '', '', '')");
    db.close();
    final s = SqliteBlessingStore.open(path);
    expect((await s.get('waiting'))!.wordsStatus, WordsStatus.pending);
    expect((await s.get('heard'))!.wordsStatus, WordsStatus.written);
    expect((await s.get('done'))!.wordsStatus, WordsStatus.written);
    expect((await s.get('typed'))!.wordsStatus, WordsStatus.written, reason: 'no recording: nothing to write from');
    await s.close();
    db = sqlite3.open(path);
    expect(db.userVersion, SqliteBlessingStore.schemaVersion);
    db.close();
  });

  test('the words state is stored and read back', () async {
    final s = SqliteBlessingStore.open(path);
    for (final w in WordsStatus.values) {
      await s.create(make(w.code, DateTime.utc(2026, 3, 3))..wordsStatus = w);
      expect((await s.get(w.code))!.wordsStatus, w);
    }
    final b = (await s.get('pending'))!..wordsStatus = WordsStatus.unavailable;
    await s.update(b);
    expect((await s.get('pending'))!.wordsStatus, WordsStatus.unavailable);
    await s.close();
  });

  test('the first writing of the words is kept whatever the words become', () async {
    final s = SqliteBlessingStore.open(path);
    final b = make('a', DateTime.utc(2026, 3, 3))
      ..rawText = ''
      ..firstText = '';
    await s.create(b);
    // the words arrive
    b
      ..rawText = 'I bless you with pieces'
      ..firstText = 'I bless you with pieces';
    await s.update(b);
    // the person corrects them; nothing may change the first writing now
    b
      ..rawText = 'I bless you with peace'
      ..firstText = 'something else';
    await s.update(b);
    final r = (await s.get('a'))!;
    expect(r.rawText, 'I bless you with peace');
    expect(r.firstText, 'I bless you with pieces');
    await s.close();
  });

  test('tags and who it was for round-trip, and every tag in use is listed, most used first', () async {
    final s = SqliteBlessingStore.open(path);
    await s.create(make('a', DateTime.utc(2026, 3, 3))..tags = ['Healing', 'Family']);
    await s.create(make('b', DateTime.utc(2026, 3, 4))..tags = ['Family']);
    final c = make('c', DateTime.utc(2026, 3, 5))
      ..tags = ['Work', 'Calling', 'Work']
      ..recipient = 'Mateo Ruiz';
    await s.create(c);
    final r = (await s.get('c'))!;
    expect(r.tags, ['Work', 'Calling'], reason: 'kept in order, once each');
    expect(r.recipient, 'Mateo Ruiz');
    expect(await s.allTags(), ['Family', 'Calling', 'Healing', 'Work']);
    r
      ..tags = ['Calling']
      ..recipient = '';
    await s.update(r);
    final again = (await s.get('c'))!;
    expect(again.tags, ['Calling']);
    expect(again.recipient, '');
    expect(await s.allTags(), ['Family', 'Calling', 'Healing']);
    await s.close();
  });

  test('a version 4 file has its tags brought to a capital first letter, once each', () async {
    var db = sqlite3.open(path);
    SqliteBlessingStore.migrateTo(db, 4);
    db.execute("INSERT INTO blessings (id, title, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
        "draft, created_at_ms, updated_at_ms) VALUES ('t', 'T', 'for_me', 29000000, -420, 40.2, -111.6, 0, 5, 6)");
    db.execute("INSERT INTO blessing_tags (blessing_id, tag, position) VALUES "
        "('t', 'healing', 0), ('t', 'new job', 1), ('t', 'Healing', 2), ('t', 'éxito', 3), ('t', 'Family', 4)");
    db.close();
    final s = SqliteBlessingStore.open(path);
    expect((await s.get('t'))!.tags, ['Healing', 'New job', 'Éxito', 'Family']);
    await s.close();
    db = sqlite3.open(path);
    expect(db.userVersion, SqliteBlessingStore.schemaVersion);
    db.close();
  });

  test('a version 5 file has its earlier edits placed in the spoken words, all kept', () async {
    // the sample blessing as version 5 stored it: polished words, and five edits with no positions
    final sample = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    var db = sqlite3.open(path);
    SqliteBlessingStore.migrateTo(db, 5);
    final legacy = jsonEncode([
      for (final e in legacySurgeryEdits)
        {'level': 'light', 'what': e.kind, 'was': e.was, 'now': e.now},
    ]);
    db.execute("INSERT INTO blessings (id, title, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
        "raw_text, polished_text, edits_json, draft, created_at_ms, updated_at_ms, first_text) VALUES "
        "('surgery', 'Comfort before surgery', 'for_me', 29000000, -420, 40.2, -111.6, ?, ?, ?, 0, 5, 6, ?), "
        "('plain', 'Plain', 'for_me', 29000001, -420, 40.2, -111.6, 'words', '', '[]', 0, 5, 6, 'words'), "
        "('lost', 'Lost', 'for_me', 29000002, -420, 40.2, -111.6, 'I bless you', 'I bless', ?, 0, 5, 6, 'I bless you')",
        [sample.rawText, surgeryPolished, legacy, sample.rawText,
         jsonEncode([{'level': 'light', 'what': 'Filler removed', 'was': 'not there', 'now': ''}])]);
    db.close();

    final s = SqliteBlessingStore.open(path);
    final b = (await s.get('surgery'))!;
    expect(b.changes, hasLength(5));
    expect([for (final c in b.changes) c.kind], [ChangeKind.filler, ChangeKind.reworded, ChangeKind.repeat, ChangeKind.reworded, ChangeKind.reworded]);
    expect([for (final c in b.changes) c.size], [ChangeSize.light, ChangeSize.moderate, ChangeSize.light, ChangeSize.moderate, ChangeSize.heavy],
        reason: 'measured from the words, as the prototype shows them');
    expect(b.changes.every((c) => c.kept), isTrue);
    for (final c in b.changes) {
      expect(b.rawText.substring(c.start, c.end), c.was);
    }
    expect(b.polishedText, surgeryPolished, reason: 'the same polished words as before');
    expect(b.words, surgeryPolished);
    expect(b.polishAsked, isTrue);
    expect((await s.get('plain'))!.changes, isEmpty);
    expect((await s.get('plain'))!.polishAsked, isFalse);
    final lost = (await s.get('lost'))!;
    expect(lost.changes, isEmpty, reason: 'an edit whose words are not in the spoken words is dropped');
    expect(lost.words, 'I bless you');
    await s.close();
    db = sqlite3.open(path);
    expect(db.userVersion, SqliteBlessingStore.schemaVersion);
    expect(db.select("SELECT count(*) AS n FROM pragma_table_info('blessings') WHERE name = 'edits_json'").first['n'], 0);
    db.close();
  });

  test('changes keep their state through a save, and go with their blessing', () async {
    final s = SqliteBlessingStore.open(path);
    final b = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    await s.create(b);
    b.changes[1].kept = false;
    b.changes[4].kept = false;
    await s.update(b);
    final r = (await s.get('surgery'))!;
    expect([for (final c in r.changes) c.kept], [true, false, true, true, false]);
    expect(r.keptChanges, 3);
    expect(r.words, contains('He knows about, He knows the worry'));
    expect(r.words, contains('your strength, it’s going to come back to you'));
    expect(r.words, contains('upon your head to give'));
    await s.delete('surgery');
    final db = sqlite3.open(path);
    expect(db.select('SELECT count(*) AS n FROM blessing_changes').first['n'], 0);
    db.close();
    await s.close();
  });
}
