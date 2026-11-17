// Rebuilding a blessing from a recording the app was closed during, and clearing audio that
// belongs to nothing (lib/record/recovery.dart), against a real store and real files.
//
//   flutter test test/recovery_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/record/recovery.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';

class FailingJoiner implements AudioJoiner {
  @override
  Future<String?> join(String audioDir, String id) async => throw StateError('the disk is full');
}

void main() {
  late Directory dir;
  late String audio;
  late SqliteBlessingStore store;
  final now = DateTime.utc(2026, 11, 16, 8);
  final began = DateTime.utc(2026, 11, 15, 3, 41, 27);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('recovery');
    audio = p.join(dir.path, 'audio');
    Directory(audio).createSync();
    store = SqliteBlessingStore.open(p.join(dir.path, 'blessings.sqlite'), audioDir: audio);
  });
  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  RecordingNote note(String id) => RecordingNote(
        id: id,
        began: began,
        utcOffset: const Duration(hours: -7),
        place: const Place(40.77, -111.89),
        language: 'es',
      );

  void file(String name, [List<int> bytes = const [1, 2, 3]]) => File(p.join(audio, name)).writeAsBytesSync(bytes);
  List<String> files() => [for (final f in Directory(audio).listSync()) p.basename(f.path)]..sort();
  Recovery recovery({AudioJoiner joiner = const FileJoiner()}) => Recovery(store: store, audioDir: audio, joiner: joiner, now: () => now);

  test('the note holds what rebuilds the blessing, and reads back', () async {
    await note('abc123').write(audio);
    expect(files(), ['abc123.recording.json'], reason: 'written whole: no temporary file left');
    final back = RecordingNote.fromJson(jsonDecode(File(RecordingNote.pathFor(audio, 'abc123')).readAsStringSync()))!;
    expect(back.id, 'abc123');
    expect(back.began, began);
    expect(back.utcOffset, const Duration(hours: -7));
    expect(back.place.lat, 40.77);
    expect(back.place.lon, -111.89);
    expect(back.language, 'es');
  });

  test('a note not written by this app is ignored', () {
    expect(RecordingNote.fromJson(null), isNull);
    expect(RecordingNote.fromJson({'id': 'a'}), isNull);
    expect(RecordingNote.fromJson({...note('x').toJson(), 'id': '../../Documents/blessings'}), isNull);
  });

  test('a recording the app was closed during becomes a draft at its true time, once', () async {
    await note('abc123').write(audio);
    file('abc123.part1.aac', [1, 1]);
    file('abc123.part2.aac', [2, 2, 2]);
    file('abc123.part10.aac', [3]);
    final r = await recovery().run();
    expect(r.recovered, hasLength(1));
    final b = (await store.get('abc123'))!;
    expect(b.utc, DateTime.utc(2026, 11, 15, 3, 41), reason: 'the minute Begin was pressed');
    expect(b.utcOffset, const Duration(hours: -7));
    expect(b.local.day, 14, reason: 'its day where it was given');
    expect(b.place.lat, 40.77);
    expect(b.language, 'es');
    expect(b.draft, isTrue);
    expect(b.ownership, Ownership.forMe);
    expect(b.title, Strings.untitled);
    expect(b.wordsStatus, WordsStatus.pending);
    expect(b.audio, 'abc123.m4a');
    expect(b.created, now);
    expect(File(p.join(audio, 'abc123.m4a')).readAsBytesSync(), [1, 1, 2, 2, 2, 3], reason: 'parts joined in order, 2 before 10');
    expect(files(), ['abc123.m4a'], reason: 'note and parts gone');
    expect(needsWords(b, audioOnPhone: true), isTrue, reason: 'its words are written next');

    final again = await recovery().run();
    expect(again.recovered, isEmpty, reason: 'nothing is recovered twice');
    expect(again.removed, isEmpty);
    expect(await store.count(), 1);
  });

  test('several recordings are all kept, oldest first', () async {
    for (final (id, minute) in [('late', 50), ('early', 10)]) {
      await RecordingNote(id: id, began: DateTime.utc(2026, 11, 15, 3, minute), utcOffset: Duration.zero, place: const Place(0, 0), language: 'en')
          .write(audio);
      file('$id.part1.aac');
    }
    final r = await recovery().run();
    expect([for (final b in r.recovered) b.id], ['early', 'late']);
    expect(await store.count(), 2);
  });

  test('closed after Amen had saved it: not made twice, the note removed', () async {
    final saved = note('abc123').toBlessing(audio: 'abc123.m4a', now: now);
    await store.create(saved);
    file('abc123.m4a');
    await note('abc123').write(audio);
    final r = await recovery().run();
    expect(r.recovered, isEmpty);
    expect(await store.count(), 1);
    expect(files(), ['abc123.m4a']);
  });

  test('closed after the parts were joined but before the store: the joined file is the recording', () async {
    await note('abc123').write(audio);
    file('abc123.m4a', [9, 9]);
    final r = await recovery().run();
    expect(r.recovered.single.audio, 'abc123.m4a');
    expect(File(p.join(audio, 'abc123.m4a')).readAsBytesSync(), [9, 9]);
    expect(files(), ['abc123.m4a']);
  });

  test('closed in the first moment, before anything was written: nothing is kept, nothing left', () async {
    await note('abc123').write(audio);
    file('abc123.part1.aac', const []);
    final r = await recovery().run();
    expect(r.recovered, isEmpty);
    expect(await store.count(), 0);
    expect(files(), isEmpty);
  });

  test('parts that cannot be joined now are left, with their note, for the next launch', () async {
    await note('abc123').write(audio);
    file('abc123.part1.aac');
    final r = await recovery(joiner: FailingJoiner()).run();
    expect(r.recovered, isEmpty);
    expect(files(), ['abc123.part1.aac', 'abc123.recording.json'], reason: 'the clean-up must not take them');
    final later = await recovery().run();
    expect(later.recovered, hasLength(1));
  });

  test('audio that belongs to no blessing is removed; a blessing\'s own is kept', () async {
    await store.create(note('kept').toBlessing(audio: 'kept.m4a', now: now));
    file('kept.m4a');
    file('gone.m4a'); // its blessing was deleted without its file
    file('discarded.part1.aac'); // a discard whose files outlived it
    file('old.part1.m4a'); // a part from before parts were .aac
    file('half.recording.json.tmp'); // a note that was never finished
    final r = await recovery().run();
    expect(r.removed..sort(), ['discarded.part1.aac', 'gone.m4a', 'half.recording.json.tmp', 'old.part1.m4a']);
    expect(files(), ['kept.m4a']);
  });

  test('an unreadable note is removed, and what it pointed at', () async {
    file('abc123.recording.json', utf8.encode('{"id": "abc'));
    file('abc123.part1.aac');
    final r = await recovery().run();
    expect(r.recovered, isEmpty);
    expect(files(), isEmpty);
  });

  test('no audio folder yet: nothing to do', () async {
    Directory(audio).deleteSync(recursive: true);
    final r = await recovery().run();
    expect(r.recovered, isEmpty);
    expect(r.removed, isEmpty);
  });

  test('which drafts still need their words', () {
    Blessing b({bool draft = true, String words = '', WordsStatus status = WordsStatus.pending}) =>
        note('x').toBlessing(audio: 'x.m4a', now: now)
          ..draft = draft
          ..rawText = words
          ..wordsStatus = status;
    expect(needsWords(b(), audioOnPhone: true), isTrue);
    expect(needsWords(b(), audioOnPhone: false), isFalse, reason: 'nothing to write from');
    expect(needsWords(b(words: 'typed'), audioOnPhone: true), isFalse);
    expect(needsWords(b(status: WordsStatus.unavailable), audioOnPhone: true), isFalse, reason: 'marked: could not be written');
    expect(needsWords(b(status: WordsStatus.failed), audioOnPhone: true), isFalse);
    expect(needsWords(b(status: WordsStatus.written), audioOnPhone: true), isFalse, reason: 'heard nothing');
    expect(needsWords(b(draft: false), audioOnPhone: true), isFalse);
  });

  test('the audio rule: a recording whose words are still to come is never let go', () {
    Blessing b({bool draft = true, String words = '', WordsStatus status = WordsStatus.later}) =>
        note('x').toBlessing(audio: 'x.m4a', now: now)
          ..draft = draft
          ..rawText = words
          ..wordsStatus = status;
    // Android before the model is downloaded: Done keeps the recording, typed or not
    expect(keepsRecording(b()), isTrue);
    expect(keepsRecording(b(words: 'typed by hand')), isTrue);
    expect(keepsRecording(b(draft: false, words: 'typed by hand')), isTrue, reason: 'finished, still kept');
    // and it is offered to the phone again, draft or finished, typed or not, while it is here
    expect(wordsDueFromRecording(b(), audioOnPhone: true), isTrue);
    expect(wordsDueFromRecording(b(draft: false, words: 'typed'), audioOnPhone: true), isTrue);
    expect(wordsDueFromRecording(b(), audioOnPhone: false), isFalse, reason: 'nothing to write from');
    // once words are written from it (or on iPhone, where they always are), Done lets it go
    for (final s in [WordsStatus.written, WordsStatus.pending, WordsStatus.unavailable, WordsStatus.failed]) {
      expect(keepsRecording(b(status: s)), isFalse, reason: '$s');
      expect(wordsDueFromRecording(b(status: s), audioOnPhone: true), isFalse, reason: '$s');
    }
  });

  test('the sheet says when, in the words the owner chose', () {
    final at = DateTime(2026, 11, 15, 21, 41);
    expect(Strings.recoveredTitle(1), 'A recording was kept');
    expect(Strings.recoveredTitle(2), 'Two recordings were kept');
    expect(Strings.recoveredBody([at]),
        'The app closed while a blessing was being recorded on Sunday, November 15, 9:41 at night. What had been recorded is saved.');
    expect(Strings.recoveredBody([at, at]), 'The app closed while two blessings were being recorded. What had been recorded is saved.');
  });
}
