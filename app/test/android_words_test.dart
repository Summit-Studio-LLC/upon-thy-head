import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/record/android_words.dart';
import 'package:upon_thy_head/record/recovery.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/sky/astro.dart';

/// Android's words (lib/record/android_words.dart): the rules for Whisper's text, the joining into
/// paragraphs, the order and the carrying on, with a fake engine in place of whisper.cpp.

WordsPiece piece(double a, double b, String t) => WordsPiece(start: a, end: b, text: t);

/// A fake engine: [texts] by the stretch's start; counts what was asked.
class FakeEngine implements WordsEngine {
  FakeEngine(this.stretches, this.texts, {this.seconds = 60});

  final List<(double, double)> stretches;
  final Map<double, List<String>> texts;
  final double seconds;
  final List<String> asked = [];
  int prepared = 0;
  String? cannot;

  /// Holds each piece until released, when set.
  Completer<void>? gate;

  /// Pieces after this many never finish (the app closed while one was being read).
  int? stopAfter;

  @override
  Future<({double seconds, List<(double, double)> stretches})> prepare(String path, String language) async {
    if (cannot != null) throw WordsCannot(cannot!);
    prepared++;
    return (seconds: seconds, stretches: stretches);
  }

  @override
  Future<({String text, double noSpeech})> piece(String path, double start, double end, String language, double temperature) async {
    asked.add('${path.split('/').last}@${(start + WordsRules.pad).toStringAsFixed(1)}/$temperature');
    if (gate != null) await gate!.future;
    if (stopAfter != null && asked.length > stopAfter!) await Completer<void>().future;
    final s = stretches.firstWhere((x) => (x.$1 - WordsRules.pad - start).abs() < .01 || (start == 0 && x.$1 < WordsRules.pad));
    final options = texts[s.$1] ?? const [''];
    final n = asked.where((a) => a.startsWith('${path.split('/').last}@${s.$1.toStringAsFixed(1)}')).length;
    return (text: options[(n - 1).clamp(0, options.length - 1)], noSpeech: 0.0);
  }

  @override
  Future<void> release() async {}
}

void main() {
  group('joining into paragraphs, as iPhone does', () {
    test('a silence of two seconds or more starts a paragraph; a shorter one is a space', () {
      final text = WordsRules.join([
        piece(0.5, 4.0, 'Emma, I lay my hands upon your head.'),
        piece(4.6, 8.0, 'to give you a blessing of comfort.'),
        piece(10.0, 14.0, 'your Heavenly Father knows you.'),
        piece(16.0, 18.0, 'Amen.'),
      ]);
      expect(text, 'Emma, I lay my hands upon your head. to give you a blessing of comfort.\n\nYour Heavenly Father knows you.\n\nAmen.');
    });

    test('Whisper\'s own punctuation inside a paragraph is kept; only the first letter is raised', () {
      expect(WordsRules.join([piece(0, 2, 'i bless you'), piece(2.3, 4, 'With peace.')]), 'I bless you With peace.');
      expect(WordsRules.sentence('  ¿cómo estás?'), '¿Cómo estás?');
      expect(WordsRules.sentence('...'), '...');
    });

    test('empty pieces (sounds only) are left out, and do not break a paragraph', () {
      expect(WordsRules.join([piece(0, 2, 'I bless you'), piece(2.5, 3, ''), piece(3.4, 5, 'with peace.')]), 'I bless you with peace.');
      expect(WordsRules.join([piece(0, 2, ''), piece(5, 6, '')]), '');
      expect(WordsRules.join(const []), '');
    });

    test('a paragraph is measured between the words, not the padding', () {
      final r = WordsRules.padded([(1.0, 3.0), (5.0, 7.0)], 7.1);
      expect(r, [(0.8, 3.2), (4.8, 7.1)]);
      expect(WordsRules.padded([(0.1, 1.0)], 10), [(0.0, 1.2)]);
    });
  });

  group('the bracket guard', () {
    test('what Whisper writes for sounds is dropped', () {
      expect(WordsRules.clean('[BLANK_AUDIO]'), '');
      expect(WordsRules.clean(' (Amen) '), '');
      expect(WordsRules.clean('[Music] I bless you [Music]'), 'I bless you');
      expect(WordsRules.clean('*sighs* I bless you (coughs), with peace.'), 'I bless you, with peace.');
      expect(WordsRules.clean('♪ la la la ♪'), '');
      expect(WordsRules.clean('(música) Te bendigo'), 'Te bendigo');
      expect(WordsRules.clean('…'), '');
      expect(WordsRules.clean(' - '), '');
    });

    test('ordinary words and punctuation are left alone', () {
      expect(WordsRules.clean('Emma, I lay my hands upon your head.'), 'Emma, I lay my hands upon your head.');
      expect(WordsRules.clean('Te bendigo con paz.'), 'Te bendigo con paz.');
      expect(WordsRules.clean("It's 1 o'clock."), "It's 1 o'clock.");
    });
  });

  group('the repeat guard', () {
    test('a word five times running, or a run of words four times running, is a loop', () {
      expect(WordsRules.repeats('amen amen amen amen amen'), isTrue);
      expect(WordsRules.repeats('amen amen amen amen'), isFalse);
      expect(WordsRules.repeats('I bless you. I bless you. I bless you. I bless you.'), isTrue);
      expect(WordsRules.repeats('I bless you. I bless you. I bless you.'), isFalse);
      expect(WordsRules.repeats('I bless you with peace, and I bless you with strength.'), isFalse);
    });

    test('far more words than anyone says in the time is a loop', () {
      final many = List.generate(30, (i) => 'w$i').join(' ');
      expect(WordsRules.repeats(many, seconds: 2), isTrue);
      expect(WordsRules.repeats(many, seconds: 5), isFalse);
    });

    test('a loop is kept once, with a mark', () {
      expect(WordsRules.cutLoop('and he knows and he knows and he knows and he knows'), 'and he knows …');
      expect(WordsRules.cutLoop('I bless you amen amen amen amen amen'), 'I bless you amen …');
      expect(WordsRules.cutLoop('amen amen amen'), 'amen …');
    });

    test('a loop is read again more freely; if it still loops, it is kept once with a mark', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final loop = List.filled(8, 'he knows').join(' ');
      final engine = FakeEngine([(1, 3), (3.5, 5), (5.5, 7)], {
        1: ['I bless you.'],
        3.5: [loop, 'he knows you.'],
        5.5: [loop, loop],
      });
      final w = AndroidWords(engine: engine, folder: () async => dir.path);
      final t = await w.transcribe('${dir.path}/a.m4a', SpeechLanguage.english);
      expect(t.text, 'I bless you. he knows you. he knows …');
      expect(engine.asked.where((a) => a.endsWith('/0.4')), hasLength(2), reason: 'two read again');
    });
  });

  group('writing, piece by piece', () {
    test('each stretch is read alone, in order, and the place is not left behind', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final engine = FakeEngine([(1, 3), (3.5, 5), (8, 10)], {1: ['I bless you'], 3.5: ['with peace.'], 8: ['Amen.']});
      final w = AndroidWords(engine: engine, folder: () async => dir.path);
      final seen = <String>[];
      w.progress.addListener(() {
        final x = w.progress.value['${dir.path}/a.m4a'];
        if (x != null) seen.add('${x.done}/${x.total}');
      });
      final t = await w.transcribe('${dir.path}/a.m4a', SpeechLanguage.english);
      expect(t.text, 'I bless you with peace.\n\nAmen.');
      expect(t.engine, 'whisper');
      expect(seen, ['0/3', '1/3', '2/3', '3/3']);
      expect(w.progress.value, isEmpty);
      expect(dir.listSync(), isEmpty, reason: 'its place is removed once the words are written');
    });

    test('closed in the middle: it carries on from the last finished piece, with the same words', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final texts = {1.0: ['I bless you'], 3.5: ['with peace.'], 8.0: ['Amen.']};
      final stretches = [(1.0, 3.0), (3.5, 5.0), (8.0, 10.0)];
      final whole = await AndroidWords(engine: FakeEngine(stretches, texts), folder: () async => dir.path)
          .transcribe('${dir.path}/a.m4a', SpeechLanguage.english);

      // the first run stops while its third piece is being read (the app is closed)
      final first = FakeEngine(stretches, texts)..stopAfter = 2;
      final w1 = AndroidWords(engine: first, folder: () async => dir.path);
      unawaited(w1.transcribe('${dir.path}/b.m4a', SpeechLanguage.english));
      await pumpUntil(() => first.asked.length >= 3);
      final kept = File('${dir.path}/b.m4a.json').readAsStringSync();
      expect(kept, contains('with peace.'));

      // next launch: a new writer, the same place
      final second = FakeEngine(stretches, texts);
      final w2 = AndroidWords(engine: second, folder: () async => dir.path);
      final t = await w2.transcribe('${dir.path}/b.m4a', SpeechLanguage.english);
      expect(second.asked, ['b.m4a@8.0/0.0'], reason: 'only the piece not yet finished');
      expect(t.text, whole.text);
    });

    test('a place kept for another language or another cut is not used', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/c.m4a.json').writeAsStringSync(
          '{"version":1,"language":"es","count":2,"pieces":[{"start":1,"end":3,"text":"Te bendigo"}]}');
      final engine = FakeEngine([(1, 3), (5, 7)], {1: ['I bless you.'], 5: ['Amen.']});
      final t = await AndroidWords(engine: engine, folder: () async => dir.path).transcribe('${dir.path}/c.m4a', SpeechLanguage.english);
      expect(t.text, 'I bless you.\n\nAmen.');
      expect(engine.asked, hasLength(2));
    });

    test('no model yet: the recording waits ("later"); a phone that cannot: "unavailable"', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final engine = FakeEngine(const [], const {})..cannot = 'later';
      final w = AndroidWords(engine: engine, folder: () async => dir.path);
      expect((await w.transcribe('${dir.path}/d.m4a', SpeechLanguage.english)).later, isTrue);
      engine.cannot = 'unavailable';
      expect((await w.transcribe('${dir.path}/d.m4a', SpeechLanguage.english)).unavailable, isTrue);
    });

    test('a new blessing goes before an older recording being written, then that one carries on', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final engine = FakeEngine([(1, 3), (5, 7), (9, 11)], {1: ['One.'], 5: ['Two.'], 9: ['Three.']})..gate = Completer();
      final w = AndroidWords(engine: engine, folder: () async => dir.path);
      final finished = <String>[];
      // an older recording, waiting for its words since before the model came (the home screen
      // gives these one at a time, oldest first)
      final old = w.transcribe('${dir.path}/old.m4a', SpeechLanguage.english).then((t) => finished.add('old'));
      await pumpUntil(() => engine.asked.isNotEmpty);
      // Amen on a new blessing while the old one's first piece is being read
      final fresh = w.transcribe('${dir.path}/new.m4a', SpeechLanguage.english).then((t) => finished.add('new'));
      engine.gate!.complete();
      await Future.wait([old, fresh]);
      expect([for (final a in engine.asked) a.split('@').first],
          ['old.m4a', 'new.m4a', 'new.m4a', 'new.m4a', 'old.m4a', 'old.m4a'],
          reason: 'the piece under way finishes; then the new one whole; then the old one carries on');
      expect(finished, ['new', 'old']);
    });

    test('concurrent transcribe calls on the same file share one run and forget removes its checkpoint', () async {
      final dir = await Directory.systemTemp.createTemp('words');
      addTearDown(() => dir.delete(recursive: true));
      final engine = FakeEngine([(1, 3), (5, 7)], {1: ['I bless you.'], 5: ['Amen.']})..gate = Completer();
      final w = AndroidWords(engine: engine, folder: () async => dir.path);
      final f1 = w.transcribe('${dir.path}/same.m4a', SpeechLanguage.english);
      final f2 = w.transcribe('${dir.path}/same.m4a', SpeechLanguage.english);
      await pumpUntil(() => engine.asked.isNotEmpty);
      engine.gate!.complete();
      final results = await Future.wait([f1, f2]);
      expect(results[0].text, 'I bless you.\n\nAmen.');
      expect(results[1].text, results[0].text);
      expect(engine.prepared, 1, reason: 'prepared and read once, not raced twice');
      expect(engine.asked, hasLength(2));

      File('${dir.path}/left.m4a.json').writeAsStringSync('{"pieces":[]}');
      File('${dir.path}/left.m4a.json.tmp').writeAsStringSync('{"pieces":[');
      await w.forget('left.m4a');
      expect(dir.listSync(), isEmpty);
    });
  });

  group('recordings waiting for the model', () {
    Blessing at(String id, DateTime t) => Blessing(id: id, title: '', from: '', utc: t.toUtc(), utcOffset: Duration.zero, place: const Place(0, 0), draft: true)..wordsStatus = WordsStatus.later;

    test('are written oldest first, whatever order the store lists them in', () {
      final a = at('a', DateTime.utc(2026, 11, 1)), b = at('b', DateTime.utc(2026, 11, 3)), c = at('c', DateTime.utc(2026, 11, 2));
      expect(waitingOrder([b, a, c]).map((x) => x.id), ['a', 'c', 'b']);
      final d = at('d', DateTime.utc(2026, 11, 2));
      expect(waitingOrder([d, b, c, a]).map((x) => x.id), ['a', 'c', 'd', 'b'], reason: 'the same time: by id');
    });

    test('three given within one minute are written in the order they were recorded, not by id', () {
      // the store keeps when a blessing was given to the minute (found on the emulator: three
      // recordings in one minute were written in the order of their random ids)
      final minute = DateTime.utc(2026, 11, 17, 13, 40);
      Blessing rec(String id, int second) => at(id, minute)..created = minute.add(Duration(seconds: second));
      final first = rec('e555', 5), second = rec('a363', 25), third = rec('c24d', 45);
      expect(waitingOrder([second, third, first]).map((x) => x.id), ['e555', 'a363', 'c24d']);
    });

    test('the audio rule: words written from a kept recording; erased only if the review was finished', () {
      final draft = at('a', DateTime.utc(2026, 11, 1));
      expect(takeLaterWords(draft, 'I bless you.'), isFalse, reason: 'still a draft: kept for its review');
      expect(draft.rawText, 'I bless you.');
      expect(draft.firstText, 'I bless you.');
      expect(draft.wordsStatus, WordsStatus.written);
      expect(keepsRecording(draft), isFalse, reason: 'Done now lets it go');

      final done = at('b', DateTime.utc(2026, 11, 1))
        ..draft = false
        ..rawText = 'Typed by hand.';
      expect(takeLaterWords(done, 'I bless you.'), isTrue, reason: 'its review was finished: erased now');
      expect(done.rawText, 'Typed by hand.', reason: 'typed words stand');
      expect(done.firstText, 'I bless you.', reason: "the phone's words beneath them");
    });
  });
}

Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  if (!done()) fail('timed out');
}
