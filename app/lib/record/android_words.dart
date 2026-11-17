import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'transcriber.dart';
import 'words_model.dart';

/// Writing the words on Android (docs/android-plan.md 3.5, tasks 8 to 10).
///
/// The recording is decoded and cut at its silences on the phone (android/.../WordsChannel.kt);
/// each stretch of speech goes to Whisper on its own, with nothing carried over from the stretch
/// before, and the pieces are joined here in order. Measured on a real English voice, this is what
/// keeps whole passages from going missing.
///
/// Its place is kept after every piece (`<support>/words/<recording>.json`), so a writing the app
/// was closed or killed in the middle of carries on from the last finished piece the next time.
/// Writing happens only while the app is open; there is no background service.

/// One finished piece of a recording.
class WordsPiece {
  const WordsPiece({required this.start, required this.end, required this.text, this.mark = ''});

  /// The stretch of speech, in seconds, as the silence finder gave it (unpadded).
  final double start, end;

  /// Its words, cleaned of what Whisper writes for sounds ("(Amen)", "[BLANK_AUDIO]").
  final String text;

  /// "" normally; "repeat" when Whisper repeated itself even on a second reading, and its words
  /// were kept once with a mark ([WordsRules.leftOut]).
  final String mark;

  Map<String, Object> toJson() => {'start': start, 'end': end, 'text': text, if (mark.isNotEmpty) 'mark': mark};

  static WordsPiece fromJson(Map<String, Object?> j) => WordsPiece(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
        text: j['text'] as String? ?? '',
        mark: j['mark'] as String? ?? '',
      );
}

/// The rules for Whisper's text, kept apart so they are tested on their own (test/words_rules_test.dart).
abstract final class WordsRules {
  /// As on iPhone (ios/Runner/OnDeviceSpeech.swift, `paragraphGap`): a silence at least this long
  /// between words starts a new paragraph.
  static const double paragraphGap = 2.0;

  /// Each stretch is given this much of the sound either side of it, as measured (`perseg.sh`).
  static const double pad = 0.2;

  /// Put where Whisper's reading of a stretch was left out because it kept repeating itself.
  static const String leftOut = '…';

  /// What Whisper writes for sounds rather than words: "(Amen)", "[BLANK_AUDIO]", "[Music]", "*sigh*",
  /// "♪ … ♪", "(música)". Dropped, with the space they leave.
  static final RegExp _sounds = RegExp(r'\([^)]*\)|\[[^\]]*\]|\*[^*]*\*|♪[^♪]*♪|♪|【[^】]*】|（[^）]*）');

  static String clean(String s) {
    var t = s.replaceAll(_sounds, ' ');
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
    t = t.replaceAllMapped(RegExp(r' ([,.;:!?])'), (m) => m[1]!);
    t = t.trim();
    // nothing but punctuation left ("…", "-", ".")
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t)) return '';
    return t;
  }

  static List<String> _words(String s) =>
      s.toLowerCase().split(RegExp(r"[^\p{L}\p{N}']+", unicode: true)).where((w) => w.isNotEmpty).toList();

  /// Whisper went round in a loop: a word said five times running, a run of two to twelve words
  /// said four times running, or far more words than anyone says in [seconds].
  static bool repeats(String s, {double seconds = 0}) {
    final w = _words(s);
    if (seconds > 0 && w.length > 8 + seconds * 6) return true;
    for (var n = 1; n <= 12; n++) {
      final need = n == 1 ? 5 : 4;
      for (var i = 0; i + n * need <= w.length; i++) {
        var reps = 1;
        while (i + n * (reps + 1) <= w.length && _same(w, i, i + n * reps, n)) {
          reps++;
        }
        if (reps >= need) return true;
      }
    }
    return false;
  }

  static bool _same(List<String> w, int a, int b, int n) {
    for (var k = 0; k < n; k++) {
      if (w[a + k] != w[b + k]) return false;
    }
    return true;
  }

  /// A reading that still loops after a second try: its words up to where the loop begins, once,
  /// then [leftOut]. Never the loop written out many times.
  static String cutLoop(String s) {
    final tokens = s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final w = [for (final t in tokens) t.toLowerCase().replaceAll(RegExp(r"[^\p{L}\p{N}']", unicode: true), '')];
    for (var i = 0; i < w.length; i++) {
      for (var n = 1; n <= 12 && i + 2 * n <= w.length; n++) {
        final need = n == 1 ? 3 : 2;
        var reps = 1;
        while (i + n * (reps + 1) <= w.length && _same(w, i, i + n * reps, n)) {
          reps++;
        }
        if (reps >= need) {
          final kept = tokens.sublist(0, i + n).join(' ');
          return kept.isEmpty ? leftOut : '$kept $leftOut';
        }
      }
    }
    return tokens.length > 40 ? '${tokens.sublist(0, 40).join(' ')} $leftOut' : '${tokens.join(' ')} $leftOut';
  }

  /// The pieces joined in order: a blank line where the speaker paused for [paragraphGap], a space
  /// otherwise; each paragraph trimmed and begun with a capital, as iPhone does
  /// (OnDeviceSpeech.swift, `join` and `sentence`). Whisper's own punctuation and capitals inside
  /// a paragraph are kept as it wrote them, as iPhone keeps its engine's.
  static String join(List<WordsPiece> pieces) {
    final kept = [for (final x in pieces) if (x.text.trim().isNotEmpty) x];
    final out = StringBuffer();
    final para = StringBuffer();
    WordsPiece? last;
    void endParagraph() {
      final t = para.toString().trim();
      if (t.isNotEmpty) {
        if (out.isNotEmpty) out.write('\n\n');
        out.write(sentence(t));
      }
      para.clear();
    }

    for (final x in kept) {
      final t = x.text.trim();
      if (last != null) {
        final gap = x.start - last.end;
        if (gap >= paragraphGap) {
          endParagraph();
        } else {
          para.write(' ');
        }
      }
      para.write(t);
      last = x;
    }
    endParagraph();
    return out.toString();
  }

  /// A paragraph as iPhone writes it: trimmed, its first letter a capital (after any opening
  /// Spanish ¿ or ¡). Nothing else is changed.
  static String sentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    final i = t.indexOf(RegExp(r'\p{L}', unicode: true));
    if (i < 0) return t;
    return t.substring(0, i) + t[i].toUpperCase() + t.substring(i + 1);
  }

  /// The stretches as pieces to read: each padded by [pad] either side, within the recording.
  static List<(double, double)> padded(List<(double, double)> stretches, double seconds) => [
        for (final (a, b) in stretches) (math.max(0, a - pad), math.min(seconds <= 0 ? b + pad : seconds, b + pad)),
      ];
}

/// How far the writing of one recording has come.
class WordsProgress {
  const WordsProgress({required this.done, required this.total, this.resumed = 0});

  final int done, total;

  /// The piece it carried on from, when the app had been closed in the middle (0: from the start).
  final int resumed;
}

/// What the native side does (WordsChannel.kt); a fake in the unit tests.
abstract class WordsEngine {
  /// The recording's length and stretches of speech; throws [WordsCannot] when this phone cannot
  /// write [language] now.
  Future<({double seconds, List<(double, double)> stretches})> prepare(String path, String language);

  Future<({String text, double noSpeech})> piece(String path, double start, double end, String language, double temperature);

  Future<void> release();
}

class WordsCannot implements Exception {
  const WordsCannot(this.code);

  /// "later" (the model is not on the phone yet) or "unavailable".
  final String code;

  @override
  String toString() => 'WordsCannot($code)';
}

class NativeWordsEngine implements WordsEngine {
  const NativeWordsEngine();

  static const _channel = MethodChannel('upon_thy_head/words');

  Map<String, Object> get _model => WordsModel.instance.spec.toMap();

  @override
  Future<({double seconds, List<(double, double)> stretches})> prepare(String path, String language) async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('prepare', {'path': path, 'language': language, 'model': _model});
      final s = [for (final x in (m!['stretches'] as List)) (x as num).toDouble()];
      return (seconds: (m['seconds'] as num).toDouble(), stretches: [for (var i = 0; i + 1 < s.length; i += 2) (s[i], s[i + 1])]);
    } on PlatformException catch (e) {
      if (e.code == 'later' || e.code == 'unavailable') throw WordsCannot(e.code);
      rethrow;
    }
  }

  @override
  Future<({String text, double noSpeech})> piece(String path, double start, double end, String language, double temperature) async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('piece', {
        'path': path,
        'start': start,
        'end': end,
        'language': language,
        'temperature': temperature,
        'model': _model,
      });
      return (text: m!['text'] as String, noSpeech: (m['noSpeech'] as num).toDouble());
    } on PlatformException catch (e) {
      if (e.code == 'later' || e.code == 'unavailable') throw WordsCannot(e.code);
      rethrow;
    }
  }

  @override
  Future<void> release() => _channel.invokeMethod<void>('release');
}

/// Writes the words of Android recordings, one piece at a time, and keeps its place.
class AndroidWords implements Transcriber {
  AndroidWords({WordsEngine? engine, this._folder}) : _engine = engine ?? const NativeWordsEngine();

  static final AndroidWords instance = AndroidWords();

  final WordsEngine _engine;
  final Future<String> Function()? _folder;

  /// How far each recording (by its path) has come, while it is being written.
  final ValueNotifier<Map<String, WordsProgress>> progress = ValueNotifier(const {});

  /// Tests: how long each piece waits before it is read (so a test can close the app in between).
  static Duration debugPieceDelay = Duration.zero;

  Future<String> _dir() async => _folder != null ? await _folder() : p.join(p.dirname(await _audioParent()), 'words');
  static Future<String> Function() _audioParent = () async => throw StateError('no folder');

  /// Where the place of each recording is kept: beside the audio folder, as `words/`.
  static void useAudioFolder(String audioDir) => _audioParent = () async => audioDir;

  File _placeFile(String dir, String path) => File(p.join(dir, '${p.basename(path)}.json'));

  // ---- one piece at a time, the latest asked for first ----

  /// Each waiting turn, with the number of the recording it is for (later asked, higher).
  final List<(int, Completer<void>)> _waiting = [];
  bool _busy = false;
  int _jobs = 0, _asked = 0;

  Future<void> _turn(int job) {
    if (!_busy) {
      _busy = true;
      return Future.value();
    }
    final c = Completer<void>();
    _waiting.add((job, c));
    return c.future;
  }

  void _done() {
    if (_waiting.isEmpty) {
      _busy = false;
      return;
    }
    // the recording asked for last goes first: a blessing just finished, or the one being
    // reviewed, goes before older recordings still waiting (which the home screen gives one at a
    // time, oldest first)
    var best = 0;
    for (var i = 1; i < _waiting.length; i++) {
      if (_waiting[i].$1 > _waiting[best].$1) best = i;
    }
    _waiting.removeAt(best).$2.complete();
  }

  @override
  Future<Transcript> transcribe(String path, SpeechLanguage language) async {
    _jobs++;
    final job = ++_asked;
    try {
      return await _write(path, language, job);
    } on WordsCannot catch (e) {
      return e.code == 'unavailable' ? const Transcript.unavailable() : const Transcript.later();
    } finally {
      _jobs--;
      _clear(path);
      if (_jobs == 0) {
        try {
          await _engine.release();
        } catch (_) {}
      }
    }
  }

  void _clear(String path) {
    if (!progress.value.containsKey(path)) return;
    progress.value = {...progress.value}..remove(path);
  }

  Future<Transcript> _write(String path, SpeechLanguage language, int job) async {
    final sw = Stopwatch()..start();
    final dir = await _dir();
    final place = _placeFile(dir, path);
    // the engine is held for the whole recording, given up between pieces only to a newer one
    await _turn(job);
    try {
      return await _writeHolding(path, language, job, dir, place, sw);
    } finally {
      _done();
    }
  }

  /// A newer recording is waiting: let it go first, then carry on.
  Future<void> _yield(int job) async {
    if (!_waiting.any((w) => w.$1 > job)) return;
    _done();
    await _turn(job);
  }

  Future<Transcript> _writeHolding(String path, SpeechLanguage language, int job, String dir, File place, Stopwatch sw) async {
    final prep = await _engine.prepare(path, language.code);
    // its place, if the app was closed in the middle of it
    final pieces = <WordsPiece>[];
    try {
      if (place.existsSync()) {
        final j = jsonDecode(await place.readAsString()) as Map<String, Object?>;
        if (j['language'] == language.code && j['count'] == prep.stretches.length) {
          pieces.addAll([for (final x in (j['pieces'] as List)) WordsPiece.fromJson((x as Map).cast<String, Object?>())]);
        }
      }
    } catch (e) {
      debugPrint('words: could not read its place: $e');
      pieces.clear();
    }
    final resumed = pieces.length;
    if (resumed > 0) debugPrint('words: ${p.basename(path)} carries on from piece ${resumed + 1} of ${prep.stretches.length}');
    final reads = WordsRules.padded(prep.stretches, prep.seconds);
    void show() => progress.value = {
          ...progress.value,
          path: WordsProgress(done: pieces.length, total: prep.stretches.length, resumed: resumed),
        };
    show();
    var retried = 0, marked = 0;
    for (var i = pieces.length; i < prep.stretches.length; i++) {
      if (debugPieceDelay > Duration.zero) await Future<void>.delayed(debugPieceDelay);
      final (a, b) = reads[i];
      final (s0, s1) = prep.stretches[i];
      await _yield(job);
      var mark = '';
      final first = await _engine.piece(path, a, b, language.code, 0);
      var text = WordsRules.clean(first.text);
      if (WordsRules.repeats(text, seconds: b - a)) {
        retried++;
        final again = await _engine.piece(path, a, b, language.code, 0.4);
        final t2 = WordsRules.clean(again.text);
        if (WordsRules.repeats(t2, seconds: b - a)) {
          marked++;
          mark = 'repeat';
          text = WordsRules.cutLoop(t2.length < text.length ? t2 : text);
        } else {
          text = t2;
        }
      }
      pieces.add(WordsPiece(start: s0, end: s1, text: text, mark: mark));
      if (kDebugMode) debugPrint('words: piece ${i + 1}/${prep.stretches.length} ${s0.toStringAsFixed(2)}-${s1.toStringAsFixed(2)} ${jsonEncode(text)}');
      await _keep(dir, place, language, prep.stretches.length, pieces);
      show();
    }
    final text = WordsRules.join(pieces);
    try {
      if (place.existsSync()) await place.delete();
    } catch (_) {}
    debugPrint('words: wrote ${p.basename(path)}: ${prep.seconds.toStringAsFixed(1)} s, ${pieces.length} pieces '
        '(${resumed > 0 ? 'carried on from ${resumed + 1}, ' : ''}$retried read again, $marked left out) in ${sw.elapsedMilliseconds} ms');
    // tests compare the final words of an interrupted writing with an uninterrupted one
    if (kDebugMode) {
      debugPrint('words: text ${p.basename(path)} ${jsonEncode(text)}');
      // the log cuts long lines, so the whole text goes to a file too (tool/android_words.py)
      try {
        final f = File(p.join(p.dirname(dir), 'words_text', '${p.basename(path)}.txt'));
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(text);
      } catch (_) {}
    }
    return Transcript(text: text, engine: 'whisper', locale: language.code);
  }

  Future<void> _keep(String dir, File place, SpeechLanguage language, int count, List<WordsPiece> pieces) async {
    try {
      await Directory(dir).create(recursive: true);
      final tmp = File('${place.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({'version': 1, 'language': language.code, 'count': count, 'pieces': [for (final x in pieces) x.toJson()]}),
        flush: true,
      );
      await tmp.rename(place.path);
    } catch (e) {
      debugPrint('words: could not keep its place: $e');
    }
  }

  /// At launch: places kept for recordings that are no longer on the phone.
  Future<void> tidy(Set<String> audioNames) async {
    try {
      final d = Directory(await _dir());
      if (!d.existsSync()) return;
      for (final f in d.listSync()) {
        final n = p.basename(f.path);
        final audio = n.endsWith('.json') ? n.substring(0, n.length - 5) : n;
        if (!audioNames.contains(audio)) f.deleteSync();
      }
    } catch (e) {
      debugPrint('words: tidy: $e');
    }
  }
}
