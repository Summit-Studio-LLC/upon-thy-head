// The review page, replayed as a person would use it, with real speech through the real
// recogniser and real restarts. Run by tool/review_acceptance.sh, which builds with
// SPEECH_AUDIO, grants the permissions, runs this three times with --keep-app-running, and
// terminates the app between runs (`xcrun simctl terminate`), so each part is a new process
// reading the store and the audio folder from disk. A marker file in the app's documents folder
// says which part runs.
//
//   1. New blessing, Begin, the English test passage (fed in at Amen and written by the phone's
//      own recogniser), Amen. Review now. Play; back ten seconds; the keyboard opens while it
//      plays. Fix the misheard word. Title, From, For, two tags, one removed. Back chevron.
//   2. After a kill and relaunch: still a draft, everything typed is there, the recording plays.
//      Done, Finish: the reading page shows the corrected words; the audio file is gone from the
//      app's folder; the stored first writing still has the misheard word.
//   3. After another relaunch: still finished and correct. Edit: no listen bar; Done saves without
//      asking. Then the Spanish file: no words on this simulator, so the page says so with the
//      listen bar; play; type a sentence; Finish; the typed words are on the reading page.
//
// Screenshots (the simulator's own, taken when the test prints SIMSHOT): ../design/sim/review/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/language_menu.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/widgets/buttons.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'audio/spoken.dart';
import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('review: hear it, fix it, fill it in, finish', timeout: const Timeout(Duration(minutes: 8)), (tester) async {
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

    Future<void> shot(String name) async {
      await wait(300);
      debugPrint('SIMSHOT review/$name');
      await wait(1500);
    }

    expect(audioDir, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a and es.m4a>');
    final docs = (await getApplicationDocumentsDirectory()).path;
    final marker = File('$docs/review_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final audio = await defaultAudioDir();
    debugPrint('REVIEW PHASE $phase');

    late BlessingStore store;
    late SkyEngine e;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    String text(String key) => tester.widget<CupertinoTextField>(find.byKey(Key(key))).controller!.text;
    Player player() => tester.widget<ReviewLayer>(find.byType(ReviewLayer)).player;
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    List<String> filesOf(String id) => Directory(audio).existsSync()
        ? [for (final f in Directory(audio).listSync()) p.basename(f.path)].where((n) => n.startsWith(id)).toList()
        : [];

    Future<void> launch(BlessingStore s) async {
      store = s;
      await tester.pumpWidget(UponThyHeadApp(store: s, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await wait(1500);
    }

    /// New blessing, Begin, [file] fed in at Amen, Amen; waits for the words.
    Future<Blessing> record(String file, {SpeechLanguage? language}) async {
      await tester.tap(find.byKey(const Key('new')));
      await wait(2600);
      expect(stage('record'), isTrue);
      await until(() => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue, reason: 'run tool/sim_permissions.sh grant first');
      if (language != null) {
        tester.state<LanguageControlState>(find.byKey(const Key('language'))).debugPick(language);
        await wait(400);
      }
      await tester.tap(find.byKey(const Key('begin')));
      await wait(200);
      expect(session().live, isTrue, reason: 'Begin did nothing');
      final draft = session().draft!;
      await NativeSpeech.instance.debugFeed('$audioDir/$file');
      await until(() => session().elapsed >= 11, what: 'ten seconds');
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
      await wait(300);
      expect(stage('after'), isTrue);
      await until(() => session().wordsState != WordsState.writing, seconds: 90, what: 'the words');
      await NativeSpeech.instance.debugFeed(null);
      await wait(900);
      return draft;
    }

    /// Touch a field, as a person would, and type [value] into it.
    /// Scroll a short control to the middle of the screen, clear of the top bar and the keyboard.
    Future<void> show(Finder f) => Scrollable.ensureVisible(tester.element(f), alignment: .5);

    Future<void> type(String key, String value) async {
      final f = find.byKey(Key(key));
      await show(f);
      await wait(300);
      await tester.tapAt(tester.getRect(f).topLeft + const Offset(30, 12));
      await wait(500);
      await tester.enterText(f, value);
      await wait(300);
      final fields = {
        for (final k in ['review-title', 'review-from', 'review-for', 'review-tag']) k: text(k),
      };
      expect(text(key), value, reason: 'typing into $key went elsewhere: $fields');
    }

    Future<void> done() async {
      await tester.tap(find.byKey(const Key('review-done')));
      await wait(900);
    }

    if (phase == 1) {
      store = await freshSeededStore();
      if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
      final settings = File(p.join((await getApplicationSupportDirectory()).path, 'settings.json'));
      if (settings.existsSync()) settings.deleteSync();
      await launch(store);
      debugPrint('DEMO START');
      await wait(800);

      // ---- 1. new blessing, Begin, the English passage, Amen ----
      final draft = await record('en.m4a');
      expect(session().wordsState, WordsState.done, reason: 'the English words were not written');
      final heard = session().words;
      debugPrint('HEARD <<<$heard>>>');
      final werr = wordErrors(spokenEnglish, heard);
      debugPrint('WORD ERRORS ${werr.errors} of ${werr.spoken}');
      expect(heard, contains('blessing of comfort'));

      // ---- 2. Review now ----
      await tester.tap(find.byKey(const Key('review-now')));
      await wait(2600);
      expect(stage('review'), isTrue);
      expect(e.fov, closeTo(SkyView.review.fov, 1.5));
      expect(find.byKey(const Key('listen')), findsOneWidget, reason: 'no listen bar while the recording exists');
      expect(text('review-words'), heard);
      expect(text('review-title'), '', reason: 'the title waits under its placeholder');
      expect(tester.widget<Text>(find.byKey(const Key('review-date'))).data, draft.longDate);
      await until(() => player().loaded, what: 'the recording to load');
      final length = player().duration;
      debugPrint('RECORDING ${length.toStringAsFixed(1)} s');
      expect(length, greaterThan(20));
      await shot('01-at-rest');

      // ---- 3. play: the time advances; back ten seconds; the keyboard opens while it plays ----
      await tester.tap(find.byKey(const Key('listen-play')));
      await wait(3000);
      expect(player().playing, isTrue);
      expect(player().position, greaterThan(2), reason: 'elapsed time did not advance');
      expect(tester.widget<Text>(find.byKey(const Key('listen-time'))).data, startsWith('0:0'));
      await shot('02-playing');
      // jump ahead along the line, then back ten
      final bar = tester.getRect(find.byKey(const Key('listen')));
      await tester.tapAt(Offset(bar.left + 100 + (bar.width - 100 - 80) * .6, bar.center.dy));
      await wait(300);
      final before = player().position;
      expect(before, greaterThan(12), reason: 'tapping the line did not move along it');
      await tester.tap(find.byKey(const Key('listen-back')));
      await wait(300);
      final after = player().position;
      debugPrint('BACK $before -> $after');
      expect(after, closeTo(before - 10, 1.5), reason: 'back ten seconds');
      // the words box: the keyboard rises, the bar pins above it, and it keeps playing
      final t0 = player().position;
      // touch the first line of the words, as a person would
      await tester.ensureVisible(find.byKey(const Key('review-words')));
      await wait(500);
      final wordsBox = tester.getRect(find.byKey(const Key('review-words')));
      await tester.tapAt(Offset(wordsBox.left + 120, wordsBox.top + 14));
      await wait(1800);
      expect(
        MediaQuery.of(tester.element(find.byType(ReviewLayer))).viewInsets.bottom,
        greaterThan(200),
        reason: 'the keyboard did not open',
      );
      expect(find.byKey(const Key('listen-pinned')), findsOneWidget, reason: 'the listen bar was not pinned above the keyboard');
      expect(player().playing, isTrue, reason: 'playing stopped when the keyboard opened');
      expect(player().position, greaterThan(t0 + 1));
      await shot('03-keyboard-pinned');

      // ---- 4. fix a misheard word in place ----
      var wrong = 'pieces', right = 'peace';
      final words = text('review-words');
      if (!RegExp(r'\bpieces\b').hasMatch(words)) {
        // the recogniser heard it right this time: change another word instead
        wrong = RegExp(r'\b(worry|patient|surgery|comfort)\b').firstMatch(words)!.group(0)!;
        right = '${wrong}s';
      }
      final at = words.indexOf(RegExp('\\b$wrong\\b'));
      final fixed = words.replaceRange(at, at + wrong.length, right);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: fixed,
          selection: TextSelection.collapsed(offset: at + right.length),
        ),
      );
      await wait(600);
      expect(text('review-words'), fixed);
      await tester.tap(find.byKey(const Key('pinned-play'))); // pause, from the bar above the keyboard
      await wait(300);
      expect(player().playing, isFalse);
      debugPrint('FIXED "$wrong" -> "$right"');

      // ---- 5. title, from, for, two tags, one removed ----
      await type('review-title', 'Peace before surgery');
      await type('review-from', 'Dad');
      await type('review-for', 'Emma');
      expect(text('review-words'), fixed, reason: 'the words were changed by typing elsewhere');
      await show(find.byKey(const Key('review-tag')));
      await tester.tap(find.byKey(const Key('review-tag')));
      await wait(800);
      expect(find.byKey(const Key('tag-suggestions')), findsOneWidget, reason: 'tags from other blessings are offered');
      expect(find.byKey(const Key('suggest-Healing')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('review-tag')), 'Surgery');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await wait(400);
      // a comma also ends a tag
      await tester.enterText(find.byKey(const Key('review-tag')), 'Hope,');
      await wait(400);
      await show(find.byKey(const Key('suggest-Comfort')));
      await wait(400);
      await tester.tap(find.byKey(const Key('suggest-Comfort')));
      await wait(600);
      expect(find.byKey(const Key('tag-Surgery')), findsOneWidget);
      expect(find.byKey(const Key('tag-Hope')), findsOneWidget);
      expect(find.byKey(const Key('tag-Comfort')), findsOneWidget);
      expect(find.byKey(const Key('suggest-Comfort')), findsNothing, reason: 'a tag on the blessing is not offered again');
      await shot('04-tags-suggestions');
      await show(find.byKey(const Key('untag-Hope')));
      await wait(400);
      await tester.tap(find.byKey(const Key('untag-Hope')));
      await wait(600);
      expect(find.byKey(const Key('tag-Hope')), findsNothing);

      // saved as it is typed, before anything is closed
      await wait(ReviewLayer.saveAfter.inMilliseconds + 400);
      var stored = (await store.get(draft.id))!;
      expect(stored.title, 'Peace before surgery');
      expect(stored.tags, ['Surgery', 'Comfort']);
      expect(stored.rawText, fixed);

      // ---- 6. leave with the back chevron: still a draft, everything kept ----
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(800);
      await tester.tap(find.byKey(const Key('review-back')));
      await wait(2600);
      expect(stage('home'), isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('cap-title'))).data, 'Peace before surgery');
      stored = (await store.get(draft.id))!;
      expect(stored.draft, isTrue);
      expect(stored.from, 'Dad');
      expect(stored.recipient, 'Emma');
      expect(stored.firstText, heard);
      expect(filesOf(draft.id), ['${draft.id}.m4a']);
      marker.writeAsStringSync(jsonEncode({'phase': 2, 'id': draft.id, 'heard': heard, 'fixed': fixed, 'wrong': wrong, 'right': right}));
      debugPrint('PHASE 1 DONE');
      return;
    }

    final id = state['id'] as String, heard = state['heard'] as String, fixed = state['fixed'] as String;
    final wrong = state['wrong'] as String, right = state['right'] as String;
    await launch(SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio));

    if (phase == 2) {
      // ---- 6, continued. after a real kill: still a draft, everything there, still plays ----
      expect(tester.widget<Text>(find.byKey(const Key('cap-title'))).data, 'Peace before surgery', reason: 'opens on the newest');
      await tester.tap(find.byKey(const Key('read')));
      await wait(2600);
      expect(stage('read'), isTrue);
      expect(find.byKey(const Key('read-review')), findsOneWidget, reason: 'a draft leads with Review');
      expect(tester.widget<LightTextBtn>(find.byKey(const Key('read-edit'))).label, 'Review');
      await shot('05a-draft-reading');
      await tester.tap(find.byKey(const Key('read-review')));
      await wait(2600);
      expect(stage('review'), isTrue);
      expect(text('review-title'), 'Peace before surgery');
      expect(text('review-from'), 'Dad');
      expect(text('review-for'), 'Emma');
      expect(text('review-words'), fixed);
      expect(find.byKey(const Key('tag-Surgery')), findsOneWidget);
      expect(find.byKey(const Key('tag-Comfort')), findsOneWidget);
      expect(find.byKey(const Key('tag-Hope')), findsNothing);
      await until(() => player().loaded, what: 'the recording to load after the restart');
      await tester.tap(find.byKey(const Key('listen-play')));
      await wait(2500);
      expect(player().playing, isTrue);
      expect(player().position, greaterThan(1.5), reason: 'the recording did not play after the restart');

      // ---- 7. Done, Finish ----
      await done();
      expect(find.text('Finished reviewing?'), findsOneWidget);
      expect(find.text('The recording will be erased from this phone. The words stay.'), findsOneWidget);
      await shot('05-finish-sheet');
      // Not yet: nothing happens
      await tester.tap(find.byKey(const Key('finish-not-yet')));
      await wait(800);
      expect(stage('review'), isTrue);
      expect((await store.get(id))!.draft, isTrue);
      await done();
      await tester.tap(find.byKey(const Key('finish-confirm')));
      await wait(2600);
      expect(stage('read'), isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('read-title'))).data, 'Peace before surgery');
      // the page's own line (the closed share sheet's card, built below the screen, says it too)
      expect(tester.widget<Text>(find.byKey(const Key('read-from'))).data, 'A blessing from Dad');
      expect(find.byKey(const Key('read-review')), findsNothing);
      expect(find.textContaining(right), findsWidgets);
      await shot('06-reading-after');
      final b = (await store.get(id))!;
      expect(b.draft, isFalse);
      expect(b.audio, '');
      expect(b.rawText, fixed);
      expect(b.firstText, heard, reason: 'the first writing must not change');
      expect(RegExp('\\b$wrong\\b').hasMatch(b.firstText), isTrue);
      expect(b.tags, ['Surgery', 'Comfort']);
      expect(b.recipient, 'Emma');
      // the file itself, on disk
      expect(filesOf(id), isEmpty, reason: 'the recording was not erased from the app folder');
      expect(File(p.join(audio, '$id.m4a')).existsSync(), isFalse);
      debugPrint(
        'AUDIO FOLDER ${Directory(audio).existsSync() ? Directory(audio).listSync().map((f) => p.basename(f.path)).toList() : '(none)'}',
      );
      marker.writeAsStringSync(jsonEncode({...state, 'phase': 3}));
      debugPrint('PHASE 2 DONE');
      return;
    }

    // ---- 8. after another relaunch: still finished, still correct ----
    var b = (await store.get(id))!;
    expect(b.draft, isFalse);
    expect(b.rawText, fixed);
    expect(b.firstText, heard);
    expect(b.title, 'Peace before surgery');
    await tester.tap(find.byKey(const Key('read')));
    await wait(2600);
    expect(find.byKey(const Key('read-review')), findsNothing);
    expect(find.textContaining(right), findsWidgets);

    // ---- 9. Edit: no listen bar; Done saves without asking ----
    await tester.tap(find.byKey(const Key('read-edit')));
    await wait(2600);
    expect(stage('review'), isTrue);
    expect(find.byKey(const Key('listen')), findsNothing, reason: 'no recording, no listen bar');
    await type('review-from', 'Dad and Grandpa Ruiz');
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(800);

    // the largest text sizes: the page still fits (an overflow fails the test)
    for (final size in ['accessibility-medium', 'accessibility-extra-extra-extra-large']) {
      debugPrint('CONTENTSIZE $size');
      await wait(2500);
      final scale = MediaQuery.of(tester.element(find.byType(ReviewLayer))).textScaler.scale(17);
      debugPrint('TEXT 17 -> $scale');
      expect(scale, greaterThan(22), reason: 'the text size did not change');
      await shot(size == 'accessibility-medium' ? '08a-text-size-ax1' : '08-text-size-largest');
    }
    debugPrint('CONTENTSIZE large');
    await wait(2500);

    await done();
    await wait(1800);
    expect(stage('read'), isTrue, reason: 'Done asked, with nothing to erase');
    expect(tester.widget<Text>(find.byKey(const Key('read-from'))).data, 'A blessing from Dad and Grandpa Ruiz');
    expect((await store.get(id))!.from, 'Dad and Grandpa Ruiz');
    await tester.tap(find.byKey(const Key('read-back')));
    await wait(2600);

    // ---- 10. Spanish: no words on this simulator; listen, type them, finish ----
    final es = await record('es.m4a', language: SpeechLanguage.spanish);
    final esState = session().wordsState;
    debugPrint('SPANISH $esState <<<${session().words}>>>');
    await tester.tap(find.byKey(const Key('review-now')));
    await wait(2600);
    expect(stage('review'), isTrue);
    expect(find.byKey(const Key('listen')), findsOneWidget);
    if (esState == WordsState.done && session().words.trim().isNotEmpty) {
      debugPrint('NOTE: this simulator wrote Spanish on the device; the no-words state was not shown');
    } else {
      expect(find.byKey(const Key('review-no-words')), findsOneWidget);
      expect(text('review-words'), '');
    }
    await until(() => player().loaded, what: 'the Spanish recording');
    await tester.tap(find.byKey(const Key('listen-play')));
    await wait(2500);
    expect(player().position, greaterThan(1.5));
    await shot('07-no-words');
    const typed = 'Emma, pongo mis manos sobre tu cabeza para darte una bendición de consuelo.';
    await tester.ensureVisible(find.byKey(const Key('review-words')));
    await wait(500);
    await tester.tapAt(tester.getRect(find.byKey(const Key('review-words'))).topLeft + const Offset(60, 14));
    await wait(1200);
    await tester.enterText(find.byKey(const Key('review-words')), typed);
    await wait(600);
    expect(player().playing, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(800);
    await done();
    expect(find.text('Finished reviewing?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-confirm')));
    await wait(2600);
    expect(stage('read'), isTrue);
    expect(find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.text(typed)), findsOneWidget);
    b = (await store.get(es.id))!;
    expect(b.rawText, typed);
    expect(b.firstText, '');
    expect(b.draft, isFalse);
    expect(b.language, 'es');
    expect(filesOf(es.id), isEmpty);
    await wait(1500);
    debugPrint('DEMO END');
    // leave the phone as it was: English, and no marker
    final settings = File(p.join((await getApplicationSupportDirectory()).path, 'settings.json'));
    if (settings.existsSync()) settings.deleteSync();
    marker.deleteSync();
    debugPrint('PHASE 3 DONE');
  });
}
