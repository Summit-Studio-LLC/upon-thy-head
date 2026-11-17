import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/blessing.dart';
import '../data/store.dart';
import '../sky/astro.dart';
import '../strings.dart';

/// A blessing is given once; it cannot be asked for again. So from the moment Begin is pressed, a
/// small note beside the audio (`<id>.recording.json` in the audio folder) holds enough to rebuild
/// the blessing if the app is closed before Amen: its id, the minute and clock offset it began, the
/// place and the language. The parts of the recording are the files `<id>.part1.aac`, `<id>.part2.aac`
/// … beside it (see ios/Runner/SpeechChannel.swift); they are found on disk rather than listed in
/// the note, so the note is written once and never rewritten while recording.
///
/// The note is removed when the blessing is in the store (after Amen) or when the recording is
/// discarded. At the next launch, a note still there means the app was closed while recording:
/// [Recovery] joins the parts and saves the blessing as a draft.
class RecordingNote {
  const RecordingNote({
    required this.id,
    required this.began,
    required this.utcOffset,
    required this.place,
    required this.language,
  });

  final String id;

  /// When Begin was pressed (UTC).
  final DateTime began;
  final Duration utcOffset;
  final Place place;

  /// "en" or "es".
  final String language;

  static const suffix = '.recording.json';

  /// The note's file in [audioDir].
  static String pathFor(String audioDir, String id) => p.join(audioDir, '$id$suffix');

  /// The note for [draft] as its recording begins.
  factory RecordingNote.of(Blessing draft) => RecordingNote(
        id: draft.id,
        began: draft.utc,
        utcOffset: draft.utcOffset,
        place: draft.place,
        language: draft.language,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'began_utc_ms': began.millisecondsSinceEpoch,
        'utc_offset_minutes': utcOffset.inMinutes,
        'latitude': place.lat,
        'longitude': place.lon,
        'language': language,
      };

  /// Null when [j] is not a note this app could have written.
  static RecordingNote? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], began = j['began_utc_ms'], offset = j['utc_offset_minutes'];
    final lat = j['latitude'], lon = j['longitude'];
    if (id is! String || !_plainId.hasMatch(id) || began is! int || offset is! int || lat is! num || lon is! num) return null;
    return RecordingNote(
      id: id,
      began: DateTime.fromMillisecondsSinceEpoch(began, isUtc: true),
      utcOffset: Duration(minutes: offset),
      place: Place(lat.toDouble(), lon.toDouble()),
      language: j['language'] is String ? j['language'] as String : '',
    );
  }

  /// Ids are hex (see newBlessingId); nothing that could name a path elsewhere.
  static final _plainId = RegExp(r'^[0-9a-zA-Z_-]+$');

  /// Write the note into [audioDir], whole or not at all (a new file, then renamed over).
  Future<void> write(String audioDir) async {
    await Directory(audioDir).create(recursive: true);
    final path = pathFor(audioDir, id);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(path);
  }

  static Future<void> remove(String audioDir, String id) async {
    for (final f in [File(pathFor(audioDir, id)), File('${pathFor(audioDir, id)}.tmp')]) {
      try {
        if (await f.exists()) await f.delete();
      } on FileSystemException catch (e) {
        debugPrint('recovery: could not remove ${f.path}: $e');
      }
    }
  }

  /// The blessing this recording becomes: a draft, given when Begin was pressed, with [audio].
  Blessing toBlessing({required String audio, required DateTime now}) => Blessing(
        id: id,
        title: Strings.untitled,
        from: '',
        utc: began,
        utcOffset: utcOffset,
        place: place,
        ownership: Ownership.forMe,
        draft: true,
        audio: audio,
        language: language,
        wordsStatus: WordsStatus.pending,
        created: now.toUtc(),
      );
}

/// Joins the parts of a recording the app was closed during (on iOS, ios/Runner/SpeechChannel.swift).
abstract class AudioJoiner {
  /// Join the parts of recording [id] in [audioDir] into `<id>.m4a` and remove them. The file's
  /// name, or null when nothing had been recorded. Throws when the parts could not be joined; they
  /// are then left for the next launch.
  Future<String?> join(String audioDir, String id);
}

/// Where there is no native side (tests on the host): the parts' bytes one after another. Only the
/// bookkeeping is real; the bytes are not playable audio unless there is one part.
class FileJoiner implements AudioJoiner {
  const FileJoiner();

  @override
  Future<String?> join(String audioDir, String id) async {
    final parts = partsOf(audioDir, id);
    final out = File(p.join(audioDir, '$id.m4a'));
    final heard = [for (final f in parts) if (f.lengthSync() > 0) f];
    if (heard.isEmpty) {
      for (final f in parts) {
        f.deleteSync();
      }
      if (out.existsSync() && out.lengthSync() > 0) return p.basename(out.path);
      if (out.existsSync()) out.deleteSync();
      return null;
    }
    final sink = out.openWrite();
    for (final f in heard) {
      await sink.addStream(f.openRead());
    }
    await sink.close();
    for (final f in parts) {
      f.deleteSync();
    }
    return p.basename(out.path);
  }
}

/// The parts of recording [id] in [audioDir], in order (`<id>.part1.aac`, `<id>.part2.aac`, …).
List<File> partsOf(String audioDir, String id) {
  final dir = Directory(audioDir);
  if (!dir.existsSync()) return const [];
  final re = RegExp('^${RegExp.escape(id)}\\.part(\\d+)\\.aac\$');
  final found = <(int, File)>[];
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final m = re.firstMatch(p.basename(e.path));
    if (m != null) found.add((int.parse(m.group(1)!), e));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, f) in found) f];
}

/// What the launch found and did.
class RecoveryReport {
  const RecoveryReport({this.recovered = const [], this.removed = const []});

  /// The blessings rebuilt from recordings the app was closed during, oldest first.
  final List<Blessing> recovered;

  /// The files removed from the audio folder because nothing they belong to remains.
  final List<String> removed;
}

/// At launch, before the sky: recordings the app was closed during become draft blessings, and
/// audio that belongs to no blessing is removed.
class Recovery {
  Recovery({required this.store, required this.audioDir, required this.joiner, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final BlessingStore store;
  final String audioDir;
  final AudioJoiner joiner;
  final DateTime Function() _now;

  Future<RecoveryReport> run() async {
    final recovered = await recover();
    final removed = await cleanUp();
    return RecoveryReport(recovered: recovered, removed: removed);
  }

  /// Every note left in the audio folder: the blessing saved as a draft (unless the store already
  /// has it, when the app was closed just after Amen), then the note removed. A recording in which
  /// nothing was heard at all (closed within its first moment) leaves nothing.
  Future<List<Blessing>> recover() async {
    final dir = Directory(audioDir);
    if (!dir.existsSync()) return const [];
    final out = <Blessing>[];
    final notes = [
      for (final e in dir.listSync())
        if (e is File && e.path.endsWith(RecordingNote.suffix)) e,
    ];
    for (final f in notes) {
      RecordingNote? note;
      try {
        note = RecordingNote.fromJson(jsonDecode(await f.readAsString()));
      } catch (e) {
        debugPrint('recovery: unreadable note ${p.basename(f.path)}: $e');
      }
      if (note == null) {
        // not a note this app wrote whole; the clean-up removes whatever it pointed at
        await f.delete();
        continue;
      }
      if (await store.get(note.id) != null) {
        // closed after Amen had saved it: the store has the blessing; its words come with the rest
        await RecordingNote.remove(audioDir, note.id);
        continue;
      }
      final String? audio;
      try {
        audio = await joiner.join(audioDir, note.id);
      } catch (e) {
        // leave the note and the parts; the next launch tries again
        debugPrint('recovery: could not join ${note.id}: $e');
        continue;
      }
      if (audio == null) {
        debugPrint('recovery: ${note.id} had nothing recorded');
        await RecordingNote.remove(audioDir, note.id);
        continue;
      }
      final b = note.toBlessing(audio: audio, now: _now());
      await store.create(b);
      await RecordingNote.remove(audioDir, note.id);
      debugPrint('recovery: kept ${note.id} ($audio)');
      out.add(b);
    }
    out.sort((a, b) => a.utc.compareTo(b.utc));
    return out;
  }

  /// Remove every file in the audio folder that belongs to no blessing and to no recording whose
  /// note is still there (one that could not be joined this time). The names removed.
  Future<List<String>> cleanUp() async {
    final dir = Directory(audioDir);
    if (!dir.existsSync()) return const [];
    final kept = {for (final b in await store.list()) b.audio}..remove('');
    final names = [for (final e in dir.listSync()) if (e is File) p.basename(e.path)];
    final waiting = {
      for (final n in names)
        if (n.endsWith(RecordingNote.suffix)) n.substring(0, n.length - RecordingNote.suffix.length),
    };
    final removed = <String>[];
    for (final n in names) {
      if (kept.contains(n)) continue;
      if (waiting.contains(idOfFile(n))) continue;
      try {
        File(p.join(audioDir, n)).deleteSync();
        removed.add(n);
      } on FileSystemException catch (e) {
        debugPrint('recovery: could not remove $n: $e');
      }
    }
    if (removed.isNotEmpty) debugPrint('recovery: removed ${removed.length} stray file(s): ${removed.join(', ')}');
    return removed;
  }
}

/// The blessing id a file in the audio folder belongs to: its name up to the first dot.
String idOfFile(String name) {
  final i = name.indexOf('.');
  return i < 0 ? name : name.substring(0, i);
}

/// The words of [b] are still to be written from its recording: a draft with audio on the phone,
/// no words, and not marked as words that could not be written.
/// The words of [b] could not be written on this phone when it was recorded, its audio is still
/// here, and nothing has been typed: worth trying again (at launch and when its review page opens).
bool couldTryWordsAgain(Blessing b, {required bool audioOnPhone}) =>
    b.draft && audioOnPhone && b.wordsStatus == WordsStatus.unavailable && b.rawText.trim().isEmpty;

bool needsWords(Blessing b, {required bool audioOnPhone}) =>
    b.draft && audioOnPhone && b.wordsStatus == WordsStatus.pending && b.rawText.trim().isEmpty;

/// The audio-keeping rule. A recording is erased when its review is finished (Done), except one
/// whose words the phone has not written yet (`WordsStatus.later`: an Android recording, until
/// docs/android-plan.md task 8). That one is kept, typed words or not, until the phone has written
/// words from it; then it is erased if the review was already finished (home_screen.dart,
/// `_finishReview` and `_writeLaterWords`). Deleting the blessing still deletes its recording.
bool keepsRecording(Blessing b) => b.wordsStatus == WordsStatus.later;

/// A recording kept for its words, still on the phone: given to the phone again at every launch and
/// whenever its review page opens, draft or finished, typed or not.
bool wordsDueFromRecording(Blessing b, {required bool audioOnPhone}) => audioOnPhone && b.wordsStatus == WordsStatus.later;
