// Polish and the changes screen, replayed with real speech through the real recogniser and a real
// kill. Run by tool/polish_acceptance.sh, which builds with SPEECH_AUDIO, grants the permissions,
// films the screen, and runs this twice with --keep-app-running: the first part ends when the
// script kills the app with SIGKILL; the second is a new launch reading the store from disk.
//
//   1. New blessing, Begin, the English passage, Amen, Review now. If the recogniser wrote no
//      repeated word, one is typed in ("the the"); "um, " is typed into a sentence by hand.
//      Polish the words: the changes screen opens with at least those two. Next and previous;
//      restore one ("1 of 2 kept"); Restore all ("Original words", "Use polished"); Use polished
//      ("2 changes"); restore one again. Done: the review page shows "Polished for reading ·
//      1 of 2 kept" and labels the box "The spoken words". A different word is corrected by hand:
//      the changes survive with their state. Done, Finish: the reading page shows the polished
//      words and "Polished from the spoken words, with 1 small change. ..."; "Review changes"
//      opens the screen. Then the app is killed.
//   2. After the relaunch, all of it is still there. A blessing with nothing to polish says
//      "Nothing to polish." and its reading page "The words as they were spoken." The sample,
//      "Comfort before surgery", on the changes screen with its last change selected, for the
//      side-by-side with design/prototype/shots/05-review-changes.png.
//
// Screenshots (SIMSHOT): ../design/sim/polish/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/polish/changes_screen.dart';
import 'package:upon_thy_head/polish/polish.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('polish: the spoken words, the changes, kept and restored', timeout: const Timeout(Duration(minutes: 8)), (tester) async {
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
      await wait(400);
      debugPrint('SIMSHOT polish/$name');
      await wait(1500);
    }

    expect(audioDir, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    final docs = (await getApplicationDocumentsDirectory()).path;
    final marker = File('$docs/polish_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final audio = await defaultAudioDir();
    debugPrint('POLISH PHASE $phase');

    late BlessingStore store;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    String label(String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? tester.widget<Text>(find.byKey(Key(key))).textSpan!.toPlainText();
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    ChangesLayerState changes() => tester.state<ChangesLayerState>(find.byType(ChangesLayer));
    Blessing? reviewing() => tester.widget<ReviewLayer>(find.byType(ReviewLayer)).blessing;
    Future<void> show(Finder f) => Scrollable.ensureVisible(tester.element(f), alignment: .5);

    Future<void> tap(String key, {int after = 900}) async {
      await tester.tap(find.byKey(Key(key)));
      await wait(after);
    }

    Future<void> launch(BlessingStore s) async {
      store = s;
      await tester.pumpWidget(UponThyHeadApp(store: s, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      await wait(1500);
    }

    /// From the home screen, by the list: the reading page of [id].
    Future<void> openFromList(String id) async {
      await tap('list', after: 1200);
      final row = find.byKey(Key('row-$id'));
      await tester.scrollUntilVisible(row, 200, scrollable: find.descendant(of: find.byKey(const Key('stage-list')), matching: find.byType(Scrollable)).first);
      await wait(400);
      await tester.tap(row);
      await wait(2600);
      expect(stage('read'), isTrue);
    }

    Future<void> toReadEnd() async {
      final s = find.byKey(const Key('read-scroll'));
      final pos = tester.state<ScrollableState>(find.descendant(of: s, matching: find.byType(Scrollable)).first).position;
      await pos.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 900), curve: Curves.easeInOut);
      await wait(600);
    }

    void expectHeader(String count, String all) {
      expect(label('changes-count'), count);
      expect(label('changes-all-text'), all);
    }

    if (phase == 1) {
      store = await freshSeededStore();
      if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
      await launch(store);
      debugPrint('FILM START');
      await wait(800);

      // ---- 1. record the English file, Amen, Review now ----
      await tap('new', after: 2600);
      await until(() => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue, reason: 'run tool/sim_permissions.sh grant first');
      await tap('begin', after: 200);
      expect(session().live, isTrue, reason: 'Begin did nothing');
      final id = session().draft!.id;
      await NativeSpeech.instance.debugFeed('$audioDir/en.m4a');
      await until(() => session().elapsed >= 11, what: 'ten seconds');
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
      await wait(300);
      await until(() => session().wordsState != WordsState.writing, seconds: 90, what: 'the words');
      await NativeSpeech.instance.debugFeed(null);
      expect(session().wordsState, WordsState.done);
      final heard = session().words;
      debugPrint('HEARD <<<$heard>>>');
      await wait(900);
      await tap('review-now', after: 2600);
      expect(stage('review'), isTrue);
      expect(find.byKey(const Key('review-spoken-label')), findsNothing, reason: 'no label before polish');

      // ---- 2. a repeat (if the recogniser wrote none) and "um, " typed in by hand ----
      var words = heard;
      final found = Polish.find(words, 'en');
      final hadRepeat = found.any((c) => c.kind == ChangeKind.repeat);
      debugPrint('RECOGNISER: ${found.length} changes of its own: $found');
      if (!hadRepeat) {
        final at = RegExp(r'\bthe (?!the\b)', caseSensitive: false).allMatches(words).last.start;
        words = '${words.substring(0, at)}the ${words.substring(at)}';
        debugPrint('TYPED A REPEAT: "the the" at $at');
      }
      final um = RegExp(r'\bthe worry\b', caseSensitive: false).firstMatch(words)?.start ??
          RegExp(r'\b\w+').allMatches(words).elementAt(8).start;
      words = '${words.substring(0, um)}um, ${words.substring(um)}';
      await show(find.byKey(const Key('review-words')));
      await wait(400);
      await tester.tap(find.byKey(const Key('review-words')));
      await wait(800);
      await tester.enterText(find.byKey(const Key('review-words')), words);
      await wait(600);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(ReviewLayer.saveAfter.inMilliseconds + 800);
      expect((await store.get(id))!.rawText, words);
      await show(find.byKey(const Key('review-polish')));
      await wait(600);
      await shot('07-review-polish-action');

      // ---- 3. Polish: the changes screen, with at least those two ----
      await tap('review-polish', after: 1800);
      expect(stage('changes'), isTrue);
      final b = reviewing()!;
      debugPrint('CHANGES ${b.changes}');
      expect(b.changes.where((c) => c.kind == ChangeKind.filler && c.was.trim().startsWith('um')), isNotEmpty);
      expect(b.changes.where((c) => c.kind == ChangeKind.repeat), isNotEmpty);
      final n = b.changes.length;
      expect(n, greaterThanOrEqualTo(2));
      expectHeader(Strings.changes(n), Strings.restoreAll);
      expect(label('sheet-step'), '1 of $n');
      await shot('08-changes-first');

      // ---- 4. next and previous; restore one; Restore all; Use polished ----
      await tap('sheet-next', after: 1000);
      expect(changes().selected, 1);
      expect(label('sheet-step'), '2 of $n');
      await tap('sheet-prev', after: 1000);
      expect(changes().selected, 0);
      await tap('sheet-restore', after: 1200);
      expect(b.changes[0].kept, isFalse);
      expectHeader(Strings.keptOf(n - 1, n), Strings.restoreAll);
      await shot('09-changes-one-restored');
      await tap('changes-all', after: 1200);
      expect(b.changes.every((c) => !c.kept), isTrue);
      expectHeader(Strings.originalWords, Strings.usePolished);
      await shot('10-changes-original-words');
      await tap('changes-all', after: 1200);
      expect(b.changes.every((c) => c.kept), isTrue);
      expectHeader(Strings.changes(n), Strings.restoreAll);
      // the repeat restored, the rest kept
      final r = b.changes.indexWhere((c) => c.kind == ChangeKind.repeat);
      changes().select(r);
      await wait(900);
      await tap('sheet-restore', after: 1200);
      expectHeader(Strings.keptOf(n - 1, n), Strings.restoreAll);
      final states = [for (final c in b.changes) (c.was, c.kept)];
      expect((await store.get(id))!.changes.map((c) => (c.was, c.kept)).toList(), states, reason: 'saved as chosen');

      // ---- 5. Done: the row with its count; a different word corrected by hand ----
      await tap('changes-done', after: 1800);
      expect(stage('review'), isTrue);
      expect(find.byKey(const Key('review-spoken-label')), findsOneWidget);
      expect(label('review-polished-text'), '${Strings.polishedForReading}  ·  ${Strings.keptOf(n - 1, n)}');
      final fix = RegExp(r'\bcomfort\b', caseSensitive: false).firstMatch(words) ?? RegExp(r'\bEmma\b').firstMatch(words)!;
      expect(b.changes.any((c) => c.start < fix.end && fix.start < c.end), isFalse, reason: 'the corrected word is in no change');
      final corrected = '${words.substring(0, fix.start)}${fix.group(0) == 'Emma' ? 'Emily' : 'peace'}${words.substring(fix.end)}';
      await show(find.byKey(const Key('review-words')));
      await tester.tap(find.byKey(const Key('review-words')));
      await wait(600);
      await tester.enterText(find.byKey(const Key('review-words')), corrected);
      await wait(600);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(ReviewLayer.saveAfter.inMilliseconds + 800);
      final saved = (await store.get(id))!;
      expect(saved.rawText, corrected);
      expect([for (final c in saved.changes) (c.was, c.kept)], states, reason: 'the changes survive the correction, each as it was');
      for (final c in saved.changes) {
        expect(corrected.substring(c.start, c.end), c.was);
      }
      await show(find.byKey(const Key('review-polished')));
      await wait(600);
      await shot('11-review-polished-row');

      // ---- 6. Finish: the reading page ----
      await tap('review-done', after: 900);
      await tap('finish-confirm', after: 2600);
      expect(stage('read'), isTrue);
      final fin = (await store.get(id))!;
      expect(fin.draft, isFalse);
      expect(fin.keptChanges, n - 1);
      expect(fin.words, fin.polishedText);
      expect(fin.words, isNot(contains('um, ')));
      expect(fin.rawText, contains('um, '));
      expect(label('read-as-spoken'), Strings.polishedFrom(n - 1));
      await toReadEnd();
      await shot('12-read-end-polished');
      await tap('read-review-changes', after: 1800);
      expect(stage('changes'), isTrue);
      expectHeader(Strings.keptOf(n - 1, n), Strings.restoreAll);
      await tap('changes-done', after: 1800);
      expect(stage('read'), isTrue);

      // ---- 7. a real kill ----
      state
        ..['phase'] = 2
        ..['id'] = id
        ..['n'] = n
        ..['states'] = [for (final (w, k) in states) [w, k]]
        ..['raw'] = corrected;
      marker.writeAsStringSync(jsonEncode(state));
      debugPrint('KILL ${DateTime.now().millisecondsSinceEpoch}');
      await wait(60000);
      fail('the app was not killed');
    } else {
      final id = state['id'] as String, n = state['n'] as int;
      final states = [for (final s in state['states'] as List) ((s as List)[0] as String, s[1] as bool)];
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      // a blessing with nothing to polish, written in later
      await store.create(Blessing(
        id: 'plain',
        title: 'Before the long drive',
        from: 'Mom',
        utc: DateTime.utc(2026, 11, 12, 15),
        utcOffset: const Duration(hours: -7),
        place: samplePlace,
        rawText: 'Be at peace. I bless you with strength for the road ahead, and with rest when you arrive.\n\n'
            'In the name of Jesus Christ, amen.',
        firstText: 'Be at peace.',
        language: 'en',
        draft: false,
      ));
      await launch(store);
      debugPrint('FILM START');
      await wait(600);

      // ---- 7. after the kill: everything kept ----
      final b = (await store.get(id))!;
      expect(b.rawText, state['raw']);
      expect([for (final c in b.changes) (c.was, c.kept)], states);
      expect(b.polishAsked, isTrue);
      await openFromList(id);
      expect(label('read-as-spoken'), Strings.polishedFrom(n - 1));
      await toReadEnd();
      await tap('read-review-changes', after: 1800);
      expectHeader(Strings.keptOf(n - 1, n), Strings.restoreAll);
      await shot('13-changes-after-relaunch');
      await tap('changes-done', after: 1800);
      await tap('read-back', after: 2600);

      // ---- 8. nothing to polish ----
      await openFromList('plain');
      await tap('read-edit', after: 2600);
      expect(stage('review'), isTrue);
      await show(find.byKey(const Key('review-polish')));
      await wait(500);
      await tap('review-polish', after: 1200);
      expect(stage('review'), isTrue, reason: 'nothing found: the changes screen does not open');
      expect(find.byKey(const Key('review-nothing')), findsOneWidget);
      expect(find.byKey(const Key('review-polish')), findsNothing);
      await shot('14-nothing-to-polish');
      await tap('review-done', after: 2600);
      expect(stage('read'), isTrue);
      expect(label('read-as-spoken'), Strings.asSpoken);
      expect(find.byKey(const Key('read-review-changes')), findsNothing);
      await toReadEnd();
      await shot('15-read-end-as-spoken');
      await tap('read-back', after: 2600);

      // ---- 9. the sample, its last change selected ----
      await openFromList('surgery');
      await toReadEnd();
      await tap('read-review-changes', after: 1800);
      expect(stage('changes'), isTrue);
      expectHeader(Strings.changes(5), Strings.restoreAll);
      await tap('sheet-prev', after: 1400);
      expect(changes().selected, 4);
      expect(label('sheet-step'), '5 of 5');
      await shot('16-sample-last-change');
      debugPrint('FILM END');
      await tap('changes-done', after: 1500);
      marker.deleteSync();
      debugPrint('ALL DONE');
    }
  });
}
