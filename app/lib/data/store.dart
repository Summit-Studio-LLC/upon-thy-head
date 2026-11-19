import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../people/person.dart';
import '../polish/change.dart';
import '../record/android_words.dart';
import '../review/tags.dart';
import '../sky/astro.dart';
import 'blessing.dart';
import 'sent_link.dart';

/// Where blessings are kept. The screens use only this; no SQL leaves this file.
abstract class BlessingStore {
  /// Every blessing, oldest given first; only those of [ownership] when it is set. "For me" here
  /// means on a ring: the person's own and every family member's (see [Blessing.personId]).
  Future<List<Blessing>> list({Ownership? ownership});

  /// The family members kept here, in the order they were added.
  Future<List<Person>> people();

  /// Adds [p].
  Future<void> addPerson(Person p);

  /// Writes [p]'s name and birth date over the stored one.
  Future<void> updatePerson(Person p);

  /// Removes the family member and every blessing on their ring, with their recordings, in one go.
  /// Nothing of anyone else's is touched.
  Future<void> removePerson(String id);

  Future<Blessing?> get(String id);

  Future<int> count();

  /// Adds [b]. Its [Blessing.created] and [Blessing.updated] are kept as they are.
  Future<void> create(Blessing b);

  /// Writes every field of [b] over the stored one and sets [Blessing.updated] to now.
  Future<void> update(Blessing b);

  /// Removes the blessing and its recording.
  Future<void> delete(String id);

  /// The recording's file, or null when [b] has none.
  String? audioPath(Blessing b);

  /// Every tag used on any blessing, most used first (then alphabetically).
  Future<List<String>> allTags();

  /// Erase the recording and forget it, keeping the words. The review step calls this when the
  /// person has finished reviewing.
  Future<void> eraseAudio(Blessing b);

  /// Writes the outcome of speech recognition for blessing [id] without touching its title, names,
  /// tags, changes or draft state (which the person may be editing at the same time). Answers
  /// false when the blessing was deleted meanwhile.
  Future<bool> saveTranscript(String id, {required WordsStatus status, String? words});

  /// Every link made on this phone, newest first. A link outlives its blessing (one passed along
  /// and then deleted keeps working until it stops), so each keeps a copy of the title.
  Future<List<SentLink>> links();

  Future<void> addLink(SentLink link);

  /// The link was stopped at [at] (here, or found gone at the service).
  Future<void> setLinkStopped(String id, DateTime at);

  /// Forget a link (one that ended a while ago).
  Future<void> removeLink(String id);

  Future<void> close();
}

/// [BlessingStore] in an SQLite file on the device.
class SqliteBlessingStore implements BlessingStore {
  SqliteBlessingStore._(this._db, this.audioDir);

  final Database _db;

  /// Where recordings are kept (see data/audio.dart); null where there are none (unit tests).
  final String? audioDir;

  /// The file in the app's documents folder (backed up with the phone; never leaves it otherwise).
  static Future<String> defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'blessings.sqlite');
  }

  /// Opens (creating if needed) the store at [path] and brings its schema up to date.
  static SqliteBlessingStore open(String path, {String? audioDir}) {
    File(path).parent.createSync(recursive: true);
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    migrate(db);
    return SqliteBlessingStore._(db, audioDir);
  }

  /// The schema version this code writes.
  static int get schemaVersion => _migrations.length;

  /// Step i takes the schema from version i to i + 1. Add new steps at the end; never edit old ones.
  static final List<void Function(Database)> _migrations = [
    (db) {
      db.execute('''
        CREATE TABLE blessings (
          id TEXT NOT NULL PRIMARY KEY,
          title TEXT NOT NULL,
          giver TEXT NOT NULL DEFAULT '',
          recipient TEXT NOT NULL DEFAULT '',
          ownership TEXT NOT NULL CHECK (ownership IN ('for_me', 'passing_on')),
          given_utc_minute INTEGER NOT NULL,
          utc_offset_minutes INTEGER NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          raw_text TEXT NOT NULL DEFAULT '',
          polished_text TEXT NOT NULL DEFAULT '',
          edits_json TEXT NOT NULL DEFAULT '[]',
          draft INTEGER NOT NULL DEFAULT 1,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        ) STRICT''');
      db.execute('CREATE INDEX blessings_by_owner_and_date ON blessings (ownership, given_utc_minute)');
      db.execute('''
        CREATE TABLE blessing_tags (
          blessing_id TEXT NOT NULL REFERENCES blessings (id) ON DELETE CASCADE,
          tag TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (blessing_id, tag)
        ) STRICT''');
    },
    // 2: the recording, kept until reviewed, and the language it was spoken in
    (db) {
      db.execute("ALTER TABLE blessings ADD COLUMN audio TEXT NOT NULL DEFAULT ''");
      db.execute("ALTER TABLE blessings ADD COLUMN language TEXT NOT NULL DEFAULT ''");
    },
    // 3: the words as the phone first wrote them, kept unchanged under the person's corrections.
    // Until now nothing could correct the words, so what is there is still the first writing.
    (db) {
      db.execute("ALTER TABLE blessings ADD COLUMN first_text TEXT NOT NULL DEFAULT ''");
      db.execute('UPDATE blessings SET first_text = raw_text');
    },
    // 4: whether the words have been written from the recording yet, so a blessing saved at Amen
    // whose words were not yet written when the app closed gets them at the next launch. A draft
    // that already has its recording and no words is taken as not yet written.
    (db) {
      db.execute("ALTER TABLE blessings ADD COLUMN words_state TEXT NOT NULL DEFAULT 'written'");
      db.execute("UPDATE blessings SET words_state = 'pending' WHERE draft = 1 AND audio != '' AND trim(raw_text) = ''");
    },
    // 5: tags begin with a capital ("healing" → "Healing"), as they now do when added. Two tags on
    // one blessing that become the same are kept once, in the place of the first.
    (db) {
      final rows = db.select('SELECT blessing_id, tag FROM blessing_tags ORDER BY blessing_id, position');
      final byBlessing = <String, List<String>>{};
      for (final r in rows) {
        (byBlessing[r['blessing_id'] as String] ??= []).add(r['tag'] as String);
      }
      db.execute('DELETE FROM blessing_tags');
      for (final MapEntry(key: id, value: tags) in byBlessing.entries) {
        final kept = TagRules.add([], tags.join(','));
        for (var i = 0; i < kept.length; i++) {
          db.execute('INSERT INTO blessing_tags (blessing_id, tag, position) VALUES (?, ?, ?)', [id, kept[i], i]);
        }
      }
    },
    // 6: polish's changes get their own table, each with its place in the spoken words and whether
    // it is kept or restored. The earlier `edits_json` had neither: each earlier change is found in
    // the spoken words in order and kept (they were all applied before); one that cannot be found
    // is dropped. `polished_text` stays as a copy of the polished words, worked out on every save.
    (db) {
      db.execute('''
        CREATE TABLE blessing_changes (
          blessing_id TEXT NOT NULL REFERENCES blessings (id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          start_at INTEGER NOT NULL CHECK (start_at >= 0),
          was TEXT NOT NULL CHECK (was != ''),
          now TEXT NOT NULL,
          kind TEXT NOT NULL,
          source TEXT NOT NULL,
          kept INTEGER NOT NULL CHECK (kept IN (0, 1)),
          PRIMARY KEY (blessing_id, position)
        ) STRICT''');
      db.execute('ALTER TABLE blessings ADD COLUMN polish_asked INTEGER NOT NULL DEFAULT 0');
      for (final r in db.select("SELECT id, raw_text, edits_json FROM blessings WHERE edits_json NOT IN ('', '[]')")) {
        final old = [
          for (final e in jsonDecode(r['edits_json'] as String) as List)
            if (e is Map && e['was'] is String && e['now'] is String)
              (kind: kindOfLegacy(e['what'] is String ? e['what'] as String : ''), was: e['was'] as String, now: e['now'] as String),
        ];
        final changes = locateChanges(r['raw_text'] as String, old);
        _insertChanges(db, r['id'] as String, changes);
        db.execute('UPDATE blessings SET polish_asked = 1 WHERE id = ?', [r['id']]);
      }
      db.execute('ALTER TABLE blessings DROP COLUMN edits_json');
    },
    // 7: links made on this phone (share/links.dart), and when a blessing being passed along was
    // sent. A link names its blessing but does not go with it: one passed along and then deleted
    // keeps working until it stops, and stays in "Your links". Its stop token is never here; it is
    // in the Keychain (share/link_crypto.dart).
    (db) {
      db.execute('''
        CREATE TABLE links (
          id TEXT NOT NULL PRIMARY KEY,
          blessing_id TEXT NOT NULL,
          title TEXT NOT NULL,
          sent_at_ms INTEGER NOT NULL,
          expires_at_ms INTEGER NOT NULL,
          stopped_at_ms INTEGER
        ) STRICT''');
      db.execute('CREATE INDEX links_by_blessing ON links (blessing_id)');
      db.execute('ALTER TABLE blessings ADD COLUMN sent_at_ms INTEGER');
    },
    // 8: family members (people/person.dart), each with a ring of their own, and whose ring each
    // blessing is on. Every blessing so far is the person's own ('').
    (db) {
      db.execute('''
        CREATE TABLE people (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL CHECK (name != ''),
          born TEXT,
          created_at_ms INTEGER NOT NULL
        ) STRICT''');
      db.execute("ALTER TABLE blessings ADD COLUMN person_id TEXT NOT NULL DEFAULT ''");
      db.execute('CREATE INDEX blessings_by_person ON blessings (person_id)');
    },
    // 9: blessings entered from a written copy (typed or pasted, not recorded), and how much of the
    // date each is known to: the day, the month, or only the year ('unset' while an entry is still
    // being written). Every blessing so far was recorded, on a known day.
    (db) {
      db.execute("ALTER TABLE blessings ADD COLUMN date_precision TEXT NOT NULL DEFAULT 'day' CHECK (date_precision IN ('day', 'month', 'year', 'unset'))");
      db.execute('ALTER TABLE blessings ADD COLUMN entered INTEGER NOT NULL DEFAULT 0 CHECK (entered IN (0, 1))');
    },
    // 10: a family member's ring handed to their own phone (share/ring_file.dart): who kept each
    // blessing that came that way ('' for every other), and when a ring here was last handed over.
    (db) {
      db.execute("ALTER TABLE blessings ADD COLUMN kept_by TEXT NOT NULL DEFAULT ''");
      db.execute('ALTER TABLE people ADD COLUMN handed_at_ms INTEGER');
    },
  ];

  static void _insertChanges(Database db, String id, List<Change> changes) {
    for (var i = 0; i < changes.length; i++) {
      final c = changes[i];
      db.execute(
        'INSERT INTO blessing_changes (blessing_id, position, start_at, was, now, kind, source, kept) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, i, c.start, c.was, c.now, c.kind.code, c.source, c.kept ? 1 : 0],
      );
    }
  }

  static void migrate(Database db) => migrateTo(db, _migrations.length);

  /// Brings [db] up to schema version [to] (tests use this to make a file as an older release left it).
  static void migrateTo(Database db, int to) {
    final from = db.userVersion;
    if (from > _migrations.length) {
      throw StateError('The blessings file is version $from; this app reads up to ${_migrations.length}.');
    }
    for (var v = from; v < to; v++) {
      _tx(db, () {
        _migrations[v](db);
        db.userVersion = v + 1;
      });
    }
  }

  static T _tx<T>(Database db, T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _owner(Ownership o) => switch (o) {
        Ownership.forMe => 'for_me',
        Ownership.passingOn => 'passing_on',
      };

  static const _columns = 'id, title, giver, recipient, ownership, given_utc_minute, utc_offset_minutes, '
      'latitude, longitude, raw_text, polished_text, polish_asked, draft, created_at_ms, updated_at_ms, audio, language, words_state, first_text, sent_at_ms, '
      'person_id, date_precision, entered, kept_by';

  List<Object?> _values(Blessing b) => [
        b.id,
        b.title,
        b.from,
        b.recipient,
        _owner(b.ownership),
        b.utc.millisecondsSinceEpoch ~/ 60000,
        b.utcOffset.inMinutes,
        b.place.lat,
        b.place.lon,
        b.rawText,
        b.polishedText,
        b.polishAsked ? 1 : 0,
        b.draft ? 1 : 0,
        b.created.millisecondsSinceEpoch,
        b.updated.millisecondsSinceEpoch,
        b.audio,
        b.language,
        b.wordsStatus.code,
        b.firstText,
        b.sent?.millisecondsSinceEpoch,
        // one passed along is on no ring
        b.ownership == Ownership.passingOn ? '' : b.personId,
        b.precision.code,
        b.entered ? 1 : 0,
        b.keptBy,
      ];

  Blessing _read(Row r, Map<String, List<String>> tags, Map<String, List<Change>> changes) {
    final id = r['id'] as String;
    return Blessing(
      id: id,
      title: r['title'] as String,
      from: r['giver'] as String,
      recipient: r['recipient'] as String,
      ownership: r['ownership'] == 'passing_on' ? Ownership.passingOn : Ownership.forMe,
      personId: r['person_id'] as String,
      utc: DateTime.fromMillisecondsSinceEpoch((r['given_utc_minute'] as int) * 60000, isUtc: true),
      utcOffset: Duration(minutes: r['utc_offset_minutes'] as int),
      place: Place(r['latitude'] as double, r['longitude'] as double),
      rawText: r['raw_text'] as String,
      changes: changes[id] ?? [],
      polishAsked: r['polish_asked'] == 1,
      tags: tags[id] ?? const [],
      draft: r['draft'] == 1,
      audio: r['audio'] as String,
      language: r['language'] as String,
      wordsStatus: WordsStatus.fromCode(r['words_state'] as String),
      firstText: r['first_text'] as String,
      sent: r['sent_at_ms'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['sent_at_ms'] as int, isUtc: true),
      created: DateTime.fromMillisecondsSinceEpoch(r['created_at_ms'] as int, isUtc: true),
      updated: DateTime.fromMillisecondsSinceEpoch(r['updated_at_ms'] as int, isUtc: true),
      precision: DatePrecision.fromCode(r['date_precision'] as String),
      entered: r['entered'] == 1,
      keptBy: r['kept_by'] as String,
    );
  }

  Map<String, List<String>> _tags([String? id]) {
    final rows = id == null
        ? _db.select('SELECT blessing_id, tag FROM blessing_tags ORDER BY blessing_id, position')
        : _db.select('SELECT blessing_id, tag FROM blessing_tags WHERE blessing_id = ? ORDER BY position', [id]);
    final out = <String, List<String>>{};
    for (final r in rows) {
      (out[r['blessing_id'] as String] ??= []).add(r['tag'] as String);
    }
    return out;
  }

  Map<String, List<Change>> _changes([String? id]) {
    final rows = id == null
        ? _db.select('SELECT * FROM blessing_changes ORDER BY blessing_id, position')
        : _db.select('SELECT * FROM blessing_changes WHERE blessing_id = ? ORDER BY position', [id]);
    final out = <String, List<Change>>{};
    for (final r in rows) {
      (out[r['blessing_id'] as String] ??= []).add(Change(
        start: r['start_at'] as int,
        was: r['was'] as String,
        now: r['now'] as String,
        kind: ChangeKind.fromCode(r['kind'] as String),
        source: r['source'] as String,
        kept: r['kept'] == 1,
      ));
    }
    return out;
  }

  void _writeChanges(Blessing b) {
    _db.execute('DELETE FROM blessing_changes WHERE blessing_id = ?', [b.id]);
    final sorted = [...b.changes]..sort((x, y) => x.start.compareTo(y.start));
    _insertChanges(_db, b.id, sorted);
  }

  void _writeTags(Blessing b) {
    _db.execute('DELETE FROM blessing_tags WHERE blessing_id = ?', [b.id]);
    final seen = <String>{};
    for (final t in b.tags) {
      if (!seen.add(t)) continue;
      _db.execute('INSERT INTO blessing_tags (blessing_id, tag, position) VALUES (?, ?, ?)', [b.id, t, seen.length - 1]);
    }
  }

  @override
  Future<List<Blessing>> list({Ownership? ownership}) async {
    final rows = ownership == null
        ? _db.select('SELECT $_columns FROM blessings ORDER BY given_utc_minute, created_at_ms, id')
        : _db.select('SELECT $_columns FROM blessings WHERE ownership = ? ORDER BY given_utc_minute, created_at_ms, id', [_owner(ownership)]);
    final tags = _tags(), changes = _changes();
    return [for (final r in rows) _read(r, tags, changes)];
  }

  @override
  Future<Blessing?> get(String id) async {
    final rows = _db.select('SELECT $_columns FROM blessings WHERE id = ?', [id]);
    return rows.isEmpty ? null : _read(rows.first, _tags(id), _changes(id));
  }

  @override
  Future<int> count() async => _db.select('SELECT count(*) AS n FROM blessings').first['n'] as int;

  @override
  Future<void> create(Blessing b) async {
    _tx(_db, () {
      _db.execute('INSERT INTO blessings ($_columns) VALUES (${List.filled(24, '?').join(', ')})', _values(b));
      _writeTags(b);
      _writeChanges(b);
    });
  }

  @override
  Future<void> update(Blessing b) async {
    b.updated = DateTime.now().toUtc();
    _tx(_db, () {
      final v = _values(b);
      _db.execute(
        'UPDATE blessings SET title = ?, giver = ?, recipient = ?, ownership = ?, given_utc_minute = ?, utc_offset_minutes = ?, '
        'latitude = ?, longitude = ?, raw_text = ?, polished_text = ?, polish_asked = ?, draft = ?, created_at_ms = ?, updated_at_ms = ?, '
        'audio = ?, language = ?, words_state = ?, '
        // the first writing is kept as it was once there is one
        "first_text = CASE WHEN first_text = '' THEN ? ELSE first_text END, "
        'sent_at_ms = ?, person_id = ?, date_precision = ?, entered = ?, kept_by = ? '
        'WHERE id = ?',
        [...v.skip(1), b.id],
      );
      if (_db.updatedRows != 1) throw StateError('No blessing ${b.id} to update');
      _writeTags(b);
      _writeChanges(b);
    });
  }

  @override
  Future<List<Person>> people() async => [
        for (final r in _db.select('SELECT * FROM people ORDER BY created_at_ms, rowid'))
          Person(
            id: r['id'] as String,
            name: r['name'] as String,
            born: Day.parse(r['born'] as String?),
            handed: r['handed_at_ms'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['handed_at_ms'] as int, isUtc: true),
            created: DateTime.fromMillisecondsSinceEpoch(r['created_at_ms'] as int, isUtc: true),
          ),
      ];

  @override
  Future<void> addPerson(Person p) async => _db.execute(
        'INSERT INTO people (id, name, born, created_at_ms, handed_at_ms) VALUES (?, ?, ?, ?, ?)',
        [p.id, p.name, p.born?.code, p.created.millisecondsSinceEpoch, p.handed?.millisecondsSinceEpoch],
      );

  @override
  Future<void> updatePerson(Person p) async {
    _db.execute('UPDATE people SET name = ?, born = ?, handed_at_ms = ? WHERE id = ?', [p.name, p.born?.code, p.handed?.millisecondsSinceEpoch, p.id]);
    if (_db.updatedRows != 1) throw StateError('No family member ${p.id} to update');
  }

  @override
  Future<void> removePerson(String id) async {
    // never the person's own ring, whatever is asked
    if (id.isEmpty) return;
    final audio = [for (final r in _db.select('SELECT audio FROM blessings WHERE person_id = ?', [id])) r['audio'] as String];
    _tx(_db, () {
      _db.execute('DELETE FROM blessings WHERE person_id = ?', [id]);
      _db.execute('DELETE FROM people WHERE id = ?', [id]);
    });
    for (final a in audio) {
      await _deleteFile(a);
    }
  }

  @override
  Future<void> delete(String id) async {
    final rows = _db.select('SELECT audio FROM blessings WHERE id = ?', [id]);
    _db.execute('DELETE FROM blessings WHERE id = ?', [id]);
    if (rows.isNotEmpty) await _deleteFile(rows.first['audio'] as String);
  }

  @override
  Future<List<String>> allTags() async => [
        for (final r in _db.select('SELECT tag, count(*) AS n FROM blessing_tags GROUP BY tag ORDER BY n DESC, tag COLLATE NOCASE'))
          r['tag'] as String,
      ];

  @override
  String? audioPath(Blessing b) => b.audio.isEmpty || audioDir == null ? null : p.join(audioDir!, b.audio);

  @override
  Future<void> eraseAudio(Blessing b) async {
    final name = b.audio;
    if (name.isEmpty) return;
    final now = DateTime.now().toUtc();
    _db.execute('UPDATE blessings SET audio = ?, updated_at_ms = ? WHERE id = ?', ['', now.millisecondsSinceEpoch, b.id]);
    b
      ..audio = ''
      ..updated = now;
    await _deleteFile(name);
  }

  @override
  Future<bool> saveTranscript(String id, {required WordsStatus status, String? words}) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (words == null) {
      _db.execute('UPDATE blessings SET words_state = ?, updated_at_ms = ? WHERE id = ?', [status.code, now, id]);
    } else {
      _db.execute(
        'UPDATE blessings SET words_state = ?, '
        "first_text = CASE WHEN first_text = '' THEN ? ELSE first_text END, "
        "polished_text = CASE WHEN trim(raw_text) = '' THEN ? ELSE polished_text END, "
        "raw_text = CASE WHEN trim(raw_text) = '' THEN ? ELSE raw_text END, "
        'updated_at_ms = ? WHERE id = ?',
        [status.code, words, words, words, now, id],
      );
    }
    return _db.updatedRows == 1;
  }

  Future<void> _deleteFile(String name) async {
    if (name.isEmpty) return;
    // only a plain file name inside the audio folder, never a path elsewhere
    if (p.basename(name) != name) return;
    await AndroidWords.instance.forget(name, audioDir: audioDir);
    if (audioDir == null) return;
    final f = File(p.join(audioDir!, name));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<SentLink>> links() async => [
        for (final r in _db.select('SELECT * FROM links ORDER BY sent_at_ms DESC, id'))
          SentLink(
            id: r['id'] as String,
            blessingId: r['blessing_id'] as String,
            title: r['title'] as String,
            sent: DateTime.fromMillisecondsSinceEpoch(r['sent_at_ms'] as int, isUtc: true),
            expires: DateTime.fromMillisecondsSinceEpoch(r['expires_at_ms'] as int, isUtc: true),
            stopped: r['stopped_at_ms'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['stopped_at_ms'] as int, isUtc: true),
          ),
      ];

  @override
  Future<void> addLink(SentLink l) async => _db.execute(
        'INSERT INTO links (id, blessing_id, title, sent_at_ms, expires_at_ms, stopped_at_ms) VALUES (?, ?, ?, ?, ?, ?)',
        [l.id, l.blessingId, l.title, l.sent.millisecondsSinceEpoch, l.expires.millisecondsSinceEpoch, l.stopped?.millisecondsSinceEpoch],
      );

  @override
  Future<void> setLinkStopped(String id, DateTime at) async =>
      _db.execute('UPDATE links SET stopped_at_ms = ? WHERE id = ? AND stopped_at_ms IS NULL', [at.millisecondsSinceEpoch, id]);

  @override
  Future<void> removeLink(String id) async => _db.execute('DELETE FROM links WHERE id = ?', [id]);

  @override
  Future<void> close() async => _db.close();
}
