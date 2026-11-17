// The whole core flow with the app in Spanish, replayed on the simulator with real restarts, a real
// kill and the system's own questions. Run by tool/spanish_acceptance.sh, which sets the app's own
// language (as iOS Settings > Upon Thy Head > Language does, without changing the simulator's) and
// runs this once per phase with --keep-app-running. It builds with SPEECH_AUDIO (the test passages)
// and EXTRA_AUDIO (a silent file and a broken one, for the after-Amen screen's other states).
//
// On every screen, `walk` reads every Text and RichText in the tree and every VoiceOver label, hint
// and value, and fails if any equals (or, for a sentence, contains) an English string whose Spanish
// is different, or reads like one of English's dates, times or counts. The blessings' own words,
// titles, names and tags are taken out first: they are never translated. Run with UI_LANG=en, the
// same walk fails on any Spanish instead, so the English app is replayed through the same screens.
//
//   1. Locked sky; a stranger's face; unlock. Home: sky and list. New blessing: the microphone,
//      speech and location questions (fresh), Begin, the pull-down, the first ten seconds, after,
//      the discard question, Amen: writing, kept. Review now: fields, listen bar, tags, polish, the
//      changes screen, the finish sheet; the reading page to its end; delete and its question.
//      A Spanish recording (cannot be written on this simulator), a silent one, a broken one: the
//      after-Amen screen's other states. The review page of a draft whose words could not be
//      written. Settings, lock on and off. Then Begin and a real kill (`kill -9`).
//   2. The recovered-recording sheet. Settings with no passcode and the Salt Lake Temple.
//
// The script runs the two phases at the normal text size, then again at the first accessibility
// size (no permission questions the second time: they are answered).
// Screenshots (the simulator's own, 3x): ../design/sim/spanish/ and ../design/sim/spanish/ax/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/language_menu.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const speechAudio = String.fromEnvironment('SPEECH_AUDIO');
const extraAudio = String.fromEnvironment('EXTRA_AUDIO');

/// The language this run expects the app to be in: "es" (default) or "en".
const uiLang = String.fromEnvironment('UI_LANG', defaultValue: 'es');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('spanish: the core flow, nothing English left', timeout: const Timeout(Duration(minutes: 14)), (tester) async {
    final semantics = tester.ensureSemantics();
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // ---- the language, as main() sets it ----
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    debugPrint('LOCALES ${binding.platformDispatcher.locales} -> ${Strings.language.name}');
    expect(Strings.language, uiLang == 'es' ? UiLanguage.spanish : UiLanguage.english,
        reason: 'the app is not in the language the script set (${binding.platformDispatcher.locales})');
    final spanish = Strings.language == UiLanguage.spanish;

    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path;
    final marker = File('$docs/spanish_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final dir = (state['dir'] as String?) ?? 'spanish';
    final prompts = (state['prompts'] as bool?) ?? true;
    var shots = (state['shots'] as int?) ?? 0;
    var acts = (state['acts'] as int?) ?? 0;
    final walked = ((state['walked'] as List?) ?? []).cast<String>();
    debugPrint('SPANISH PHASE $phase ($dir, prompts $prompts)');
    debugPrint('ACTDIR $tmp');

    void next(int n) {
      marker.writeAsStringSync(
          jsonEncode({...state, 'phase': n, 'shots': shots, 'acts': acts, 'walked': walked}),
          flush: true);
      debugPrint('NEXT $n');
    }

    Future<void> shot(String name, {int settle = 400}) async {
      await wait(settle);
      shots++;
      debugPrint('SIMSHOT $dir/${shots.toString().padLeft(2, '0')}-$name');
      await wait(1500);
    }

    Future<String> act(String what, {int seconds = 120}) async {
      acts++;
      final n = acts;
      final answer = File(p.join(tmp, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      debugPrint('ACT $n $what');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      debugPrint('ACT $n -> $s');
      return s;
    }

    late BlessingStore store;
    late AppLock lock;
    final audio = await defaultAudioDir();
    final settingsFile = File(p.join((await getApplicationSupportDirectory()).path, 'settings.json'));
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    Player player() => tester.widget<ReviewLayer>(find.byType(ReviewLayer)).player;

    // ---- the walk ----
    final en = Strings.wordsFor(UiLanguage.english).catalogue, es = Strings.wordsFor(UiLanguage.spanish).catalogue;
    // in a Spanish run: the English strings whose Spanish differs; in an English run, the reverse
    final wrong = <String>{
      for (final k in en.keys)
        if (en[k] != es[k]) (spanish ? en[k]! : es[k]!),
    };
    final english = Strings.wordsFor(UiLanguage.english);
    final wrongPatterns = spanish
        ? [
            RegExp('\\b(${english.months.join('|')}|${english.days.join('|')})\\b'),
            RegExp(r'\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d'),
            RegExp(r'\bin the (morning|afternoon|evening)\b|\bat night\b'),
            RegExp(r'\bblessings? (since|to review)\b|\b\d+ to review\b'),
            RegExp(r'\b\d+ changes?\b|\b\d+ of \d+\b|\bsmall changes?\b'),
            RegExp(r'^(From|For|Version|Near) '),
            RegExp(r'A blessing from|Remove tag|Add tag|Asks for|recordings? (was|were) kept|The app closed|Polished from|'
                r'Language of the blessing|turned off for|Original words restored|Polished words in use|Polished: '),
          ]
        : [
            RegExp(r'bendici|grabaci|\bde la (mañana|tarde|noche)\b|\bpor revisar\b|\bcambios?\b|Para mí|Configuración'),
            RegExp('\\b(${Strings.wordsFor(UiLanguage.spanish).months.join('|')})\\b'),
          ];
    // never translated: the app's name, language names, Apple's names
    const always = ['Upon Thy Head', 'English', 'Español', 'Face ID', 'Touch ID', 'Optic ID', 'iPhone'];

    Future<void> walk(String where) async {
      await wait(250);
      final exempt = <String>{...always};
      for (final b in await store.list()) {
        exempt.addAll([b.title, b.from, b.recipient, b.rawText, b.firstText, b.polishedText, ...b.tags]);
        for (final c in b.changes) {
          exempt.addAll([c.was.trim(), c.now.trim()]);
        }
      }
      // what is being typed on the review page and not saved yet
      for (final e in find.byType(EditableText).evaluate()) {
        exempt.add((e.widget as EditableText).controller.text);
      }
      final sorted = exempt.where((s) => s.trim().length > 1).toList()..sort((a, b) => b.length.compareTo(a.length));

      final seen = <(String, String)>[];
      for (final e in find.byType(Text).evaluate()) {
        final t = e.widget as Text;
        seen.add(('text', t.data ?? t.textSpan?.toPlainText() ?? ''));
      }
      for (final e in find.byType(RichText).evaluate()) {
        seen.add(('rich', (e.widget as RichText).text.toPlainText()));
      }
      final root = RendererBinding.instance.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
      var nodes = 0;
      void visit(SemanticsNode n) {
        nodes++;
        for (final s in [n.label, n.hint, n.value, n.tooltip]) {
          if (s.isNotEmpty) seen.add(('voiceover', s));
        }
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      if (root != null) visit(root);
      final bad = <String>[];
      for (final (kind, raw) in seen) {
        var s = raw;
        for (final x in sorted) {
          s = s.replaceAll(x, ' ');
        }
        s = s.trim();
        if (s.isEmpty) continue;
        final parts = s.split(RegExp(r'\s*[\n·]\s*|\.\s+')).map((x) => x.trim().replaceAll(RegExp(r'[.]$'), '')).toList();
        String? hit;
        for (final w in wrong) {
          final bare = w.replaceAll(RegExp(r'[.]$'), '');
          if (s == w || parts.contains(bare) || (w.length >= 14 && s.contains(w))) {
            hit = w;
            break;
          }
        }
        hit ??= wrongPatterns.where((r) => r.hasMatch(s)).map((r) => r.firstMatch(s)!.group(0)).firstOrNull;
        if (hit != null) bad.add('$kind "$raw" ← "$hit"');
      }
      debugPrint('WALK $where: ${seen.length} strings (${seen.where((s) => s.$1 == 'voiceover').length} VoiceOver, $nodes nodes), '
          '${bad.isEmpty ? 'none left in the other language' : '${bad.length} WRONG'}');
      for (final b in bad) {
        debugPrint('  WRONG $b');
      }
      expect(bad, isEmpty, reason: '$where shows words in the other language:\n${bad.join('\n')}');
      walked.add(where);
    }

    Future<void> launch({LockApi? api}) async {
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      lock = AppLock(api: api ?? NativeLockApi());
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      await until(() => lock.ready, what: 'the lock');
    }

    Future<void> match() async {
      await until(() => lock.asking, what: 'the Face ID sheet');
      await wait(1200);
      await act('face match');
      await until(() => !lock.asking, what: 'the answer');
      await wait(800);
    }

    Future<void> tap(String key, {int after = 900}) async {
      await tester.tap(find.byKey(Key(key)));
      await wait(after);
    }

    Future<void> show(Finder f) async {
      await Scrollable.ensureVisible(tester.element(f), alignment: .5);
      await wait(400);
    }

    Future<void> hold(int ms) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(ms);
      await g.up();
    }

    /// New blessing (already allowed), in [language], with [file] fed in at Amen; Amen after 11 s.
    Future<Blessing> record(SpeechLanguage language, String? file, {bool open = true, Future<void> Function()? during}) async {
      if (open) await tap('new', after: 2600);
      expect(stage('record'), isTrue);
      await until(() => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue);
      tester.state<LanguageControlState>(find.byKey(const Key('language'))).debugPick(language);
      await wait(500);
      await tester.tap(find.byKey(const Key('begin')));
      await until(() => session().live, seconds: 3, what: 'Begin');
      final d = session().draft!;
      await NativeSpeech.instance.debugFeed(file);
      await during?.call();
      await until(() => session().elapsed >= 11, seconds: 60, what: 'eleven seconds');
      await hold(1100);
      await wait(400);
      expect(stage('after'), isTrue, reason: 'no after-Amen screen');
      return d;
    }

    Future<void> wordsSettled() async {
      await until(() => session().wordsState != WordsState.writing, seconds: 90, what: 'the words');
      await NativeSpeech.instance.debugFeed(null);
      await wait(1200);
    }

    switch (phase) {
      case 1:
        expect(speechAudio, isNotEmpty);
        expect(extraAudio, isNotEmpty);
        store = await freshSeededStore();
        await store.close();
        if (settingsFile.existsSync()) settingsFile.deleteSync();
        if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
        debugPrint('FILM START');
        await launch();
        expect(lock.locked, isTrue);

        // ---- the locked sky: a stranger's face, then the person's ----
        await until(() => lock.asking, what: 'the automatic question');
        await wait(1200);
        await act('face nomatch');
        await wait(800);
        final cancel = await act('tap Cancel');
        expect(cancel, startsWith('ok'), reason: cancel);
        await until(() => !lock.asking, what: 'the answer');
        await shot('locked-sky');
        await walk('the locked sky');
        await tap('unlock', after: 200);
        await match();
        expect(lock.locked, isFalse);

        // ---- home: the sky, the list ----
        await wait(1500);
        await shot('home-sky');
        await walk('home, the sky');
        await tap('list', after: 1600);
        expect(stage('list'), isTrue);
        await shot('home-list');
        await walk('home, the list');
        await tap('list', after: 1600);

        // ---- New blessing: the three questions ----
        await tap('new', after: 300);
        if (prompts) {
          for (final (name, line) in [
            ('permission-microphone', ['Upon Thy Head escucha solo mientras grabas', 'Upon Thy Head listens only']),
            ('permission-speech', ['La voz se convierte en texto', 'Speech is turned into text']),
          ]) {
            await wait(1500);
            await shot(name, settle: 0);
            final a = await act('alert');
            debugPrint('PROMPT $name: $a');
            // iOS picks the line by the phone's own language, not the app's (a per-app language
            // leaves the system questions in the phone's); tool/spanish_prompts.sh shows them on a
            // simulator set to Spanish
            expect(a, anyOf(contains(line[0]), contains(line[1])), reason: 'the system question does not carry the app\'s own line');
            expect(await act('tap Allow'), startsWith('ok'));
          }
          await until(() => find.byKey(const Key('begin')).evaluate().isNotEmpty, what: 'the record screen');
          await wait(1500);
          await shot('permission-location', settle: 0);
          final a = await act('alert');
          debugPrint('PROMPT location: $a');
          expect(a, anyOf(contains('Se usa una vez para poner la luz'), contains('Used once to place')));
          expect(await act('tap Allow Once'), startsWith('ok'));
          await wait(800);
        }
        await wait(2000);
        expect(stage('record'), isTrue);
        await until(() => session().permissions != null, what: 'permissions');
        await shot('begin');
        await walk('the Begin screen');
        tester.state<LanguageControlState>(find.byKey(const Key('language'))).debugOpen();
        await wait(1200);
        await shot('begin-language-menu', settle: 0);
        tester.state<LanguageControlState>(find.byKey(const Key('language'))).debugClose();
        await wait(800);

        // ---- the recording: the first ten seconds, after, the discard question, Amen ----
        RecordSession.debugWordsDelay = const Duration(seconds: 8);
        final first = await record(SpeechLanguage.english, '$speechAudio/en.m4a', open: false, during: () async {
          await until(() => session().elapsed >= 3, what: 'three seconds');
          await shot('recording-first-ten-seconds', settle: 0);
          await walk('recording, the first ten seconds');
          await until(() => session().elapsed >= 10.6, what: 'ten seconds');
          await shot('recording-after-ten-seconds', settle: 0);
          await walk('recording, after ten seconds');
          await tap('rec-x', after: 1200);
          await shot('recording-discard-question', settle: 0);
          await walk('the discard question');
          await tap('sheet-keep', after: 1200);
          expect(session().live, isTrue);
        });
        await until(() => find.byKey(const Key('after-writing')).evaluate().isNotEmpty, what: 'writing the words');
        await wait(800);
        await shot('after-amen-writing', settle: 0);
        await walk('after Amen, writing');
        await wordsSettled();
        RecordSession.debugWordsDelay = Duration.zero;
        expect(session().wordsState, WordsState.done, reason: 'the English words were not written');
        await shot('after-amen-words-kept');
        await walk('after Amen, the words kept');

        // ---- Review now: the page, the listen bar, tags, polish, the changes screen ----
        await tap('review-now', after: 2600);
        expect(stage('review'), isTrue);
        await until(() => player().loaded, what: 'the recording');
        await shot('review');
        await walk('the review page');
        // at the larger text size the "whose blessing" row pushes the player below the fold
        await show(find.byKey(const Key('listen-play')));
        await tap('listen-play', after: 2500);
        expect(player().playing, isTrue);
        await shot('review-listening', settle: 0);
        await walk('the review page, playing');
        await tap('listen-play', after: 500);
        Future<void> type(String key, String value) async {
          await show(find.byKey(Key(key)));
          await tester.tap(find.byKey(Key(key)));
          await wait(500);
          await tester.enterText(find.byKey(Key(key)), value);
          await wait(400);
        }

        await type('review-title', 'Peace before surgery');
        await type('review-from', 'Dad');
        await type('review-for', 'Emma');
        await show(find.byKey(const Key('review-tag')));
        await tester.tap(find.byKey(const Key('review-tag')));
        await wait(800);
        await tester.enterText(find.byKey(const Key('review-tag')), 'Surgery,');
        await wait(800);
        await shot('review-tags', settle: 0);
        await walk('the review page, tags');
        // a filler the rules will find
        final words = tester.widget<CupertinoTextField>(find.byKey(const Key('review-words'))).controller!.text;
        final at = RegExp(r'\b\w+').allMatches(words).elementAt(8).start;
        await type('review-words', '${words.substring(0, at)}um, ${words.substring(at)}');
        FocusManager.instance.primaryFocus?.unfocus();
        await wait(ReviewLayer.saveAfter.inMilliseconds + 900);
        await show(find.byKey(const Key('review-polish')));
        await shot('review-polish-action');
        await walk('the review page, polish');
        await tap('review-polish', after: 2000);
        expect(stage('changes'), isTrue);
        await shot('changes');
        await walk('the changes screen');
        await tap('sheet-restore', after: 1400);
        await shot('changes-one-restored');
        await walk('the changes screen, one restored');
        await tap('sheet-restore', after: 1200);
        await tap('changes-done', after: 2000);
        expect(stage('review'), isTrue);
        await show(find.byKey(const Key('review-polished')));
        await shot('review-polished-row');
        await walk('the review page, polished');
        await tap('review-done', after: 1200);
        await shot('finish-sheet');
        await walk('the finish sheet');
        await tap('finish-confirm', after: 2600);

        // ---- the reading page to its end ----
        expect(stage('read'), isTrue);
        await shot('reading');
        await walk('the reading page');
        await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -6000));
        await wait(1500);
        await shot('reading-end');
        await walk('the reading page, the end');

        // ---- delete, and its question ----
        await tap('read-delete', after: 1200);
        await shot('delete-question');
        await walk('the delete question');
        await tap('delete-confirm', after: 2600);
        expect(await store.get(first.id), isNull);
        expect(stage('home'), isTrue);

        // ---- the after-Amen screen's other states ----
        await record(SpeechLanguage.spanish, '$speechAudio/es.m4a');
        await wordsSettled();
        debugPrint('SPANISH WORDS ${session().wordsState}');
        await shot('after-amen-not-written-yet');
        await walk('after Amen, the words not written yet');
        await tap('save-later', after: 2600);
        await record(SpeechLanguage.english, '$extraAudio/silence.m4a');
        await wordsSettled();
        debugPrint('SILENT WORDS ${session().wordsState}');
        await shot('after-amen-no-words');
        await walk('after Amen, no words heard');
        await tap('save-later', after: 2600);
        await record(SpeechLanguage.english, '$extraAudio/broken.m4a');
        await wordsSettled();
        debugPrint('BROKEN WORDS ${session().wordsState}');
        await shot('after-amen-not-written');
        await walk('after Amen, the words could not be written');
        await tap('save-later', after: 2600);

        // ---- home with drafts; the review page of one whose words could not be written ----
        expect(stage('home'), isTrue);
        await shot('home-drafts');
        await walk('home with drafts');
        await tap('to-review', after: 2600);
        expect(stage('review'), isTrue);
        await shot('review-no-words');
        await walk('the review page, no words');
        await tap('review-back', after: 2600);

        // ---- Settings: the lock on, then off ----
        await tap('more', after: 2000);
        expect(stage('settings'), isTrue);
        await shot('settings-lock-on');
        await walk('Settings, the lock on');
        await tap('settings-lock-switch', after: 200);
        await match();
        expect(tester.widget<SettingsLanguageControl>(find.byType(SettingsLanguageControl)).code, 'en');
        await shot('settings-lock-off');
        await walk('Settings, the lock off');
        await tap('settings-lock-switch', after: 1500);
        await tap('settings-back', after: 2000);

        // ---- a recording cut short by a real kill ----
        await tap('new', after: 2600);
        await tester.tap(find.byKey(const Key('begin')));
        await until(() => session().live, seconds: 3, what: 'Begin');
        await until(() => session().elapsed >= 9, what: 'nine seconds');
        debugPrint('FILM END');
        next(2);
        debugPrint('KILL');
        await wait(60000);
        fail('not killed');

      case 2:
        await launch();
        expect(lock.locked, isTrue);
        await match();
        await until(() => find.byKey(const Key('recovered-sheet')).hitTestable().evaluate().isNotEmpty, what: 'the recovered sheet');
        await wait(1500);
        await shot('recovered-sheet');
        await walk('the recovered-recording sheet');
        await tap('recovered-later', after: 2000);

        // ---- Settings with no passcode and the Salt Lake Temple ----
        final stored = jsonDecode(settingsFile.readAsStringSync()) as Map<String, Object?>..remove('place');
        settingsFile.writeAsStringSync(jsonEncode(stored));
        await tester.pumpWidget(const SizedBox());
        await store.close();
        await launch(api: _NoPasscode());
        expect(lock.locked, isFalse);
        await tap('more', after: 2000);
        await shot('settings-no-passcode');
        await walk('Settings, no passcode, the temple');
        await tap('settings-back', after: 1500);
        debugPrint('WALKED ${walked.length}: ${walked.join('; ')}');
        debugPrint('ALL DONE');
        marker.deleteSync();
    }
    semantics.dispose();
  });
}

class _NoPasscode extends NativeLockApi {
  @override
  Future<LockMethod> method() async => LockMethod.none;
  @override
  Future<bool> authenticate(String reason) async => fail('asked to authenticate with no passcode');
}
