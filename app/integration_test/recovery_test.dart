// Recovery of a blessing whose recording was cut short by the app being killed, replayed for real.
// Run by tool/recovery_acceptance.sh, which builds with SPEECH_AUDIO, grants the permissions, and
// runs this once per phase with --keep-app-running. When a phase prints `KILL`, the script kills the
// app's process with `kill -9` (no warning, no chance to close a file); otherwise it ends the app
// with `xcrun simctl terminate`. Each phase is a new process reading the store and the audio folder
// from disk. A marker file in the documents folder says which phase runs and carries what earlier
// phases measured.
//
//   1. Begin, about 40 s of the room's sound, kill.
//   2. The sheet, with the right day and time; the draft in the sky at its true time; its audio plays
//      on the review page and is within 5 s of what was recorded.
//   3. Launched again: no sheet, one blessing for case 1, no stray files. Then case 2: Begin, 20 s,
//      an interruption (as speech_test.dart makes one), 20 s more, kill.
//   4. Case 2: one blessing whose audio holds both stretches. Case 3: Begin, 4 s, kill.
//   5. Case 3 kept. For the plural sheet only, a copy of case 3's note and part is put beside them
//      under another id before the app starts (the copy is deleted afterwards). Case 4: Begin with
//      the English test passage fed in at Amen, 15 s, Amen, kill as soon as the blessing is in the
//      store; the words are held back 10 s in this phase so the kill lands before them.
//   6. No sheet; case 4's words written from its audio. Case 5: Begin, 5 s, hold Discard, kill.
//   7. Nothing recovered, no audio that belongs to no blessing. Case 6: Begin, kill within a second.
//   8. The app starts normally. The reading page of a sample shows "For Emma" and its tags.
//
// Screenshots (the simulator's own, on SIMSHOT lines): ../design/sim/recovery/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/recovered_sheet.dart';
import 'package:upon_thy_head/record/recovery.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'audio/spoken.dart';
import 'support.dart';

const audioFeed = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('recovery: a recording cut short by a kill is kept', timeout: const Timeout(Duration(minutes: 6)), (tester) async {
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

    Future<void> untilAsync(Future<bool> Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!await ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await wait(300);
      debugPrint('SIMSHOT recovery/$name');
      await wait(1500);
    }

    expect(audioFeed, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    final docs = (await getApplicationDocumentsDirectory()).path;
    final marker = File('$docs/recovery_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final results = (state['results'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final audio = await defaultAudioDir();
    debugPrint('RECOVERY PHASE $phase');

    void save(int next, [Map<String, Object?> extra = const {}]) =>
        marker.writeAsStringSync(jsonEncode({...state, ...extra, 'phase': next, 'results': results}), flush: true);
    void result(String key, Object? value) {
      results[key] = value;
      debugPrint('RESULT $key = $value');
    }

    List<String> files() => Directory(audio).existsSync() ? ([for (final f in Directory(audio).listSync()) p.basename(f.path)]..sort()) : [];

    late BlessingStore store;
    late SkyEngine e;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    Player player() => tester.widget<ReviewLayer>(find.byType(ReviewLayer)).player;
    bool sheetOn() => tester.widget<RecoveredSheet>(find.byType(RecoveredSheet)).on;
    String textOf(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    Future<void> launch() async {
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await wait(1500);
    }

    /// New blessing and Begin; the draft.
    Future<Blessing> begin() async {
      await tester.tap(find.byKey(const Key('new')));
      await wait(2600);
      expect(stage('record'), isTrue);
      await until(() => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue, reason: 'run tool/sim_permissions.sh grant first');
      await tester.tap(find.byKey(const Key('begin')));
      await until(() => session().live, seconds: 3, what: 'Begin');
      final d = session().draft!;
      await until(() => File(RecordingNote.pathFor(audio, d.id)).existsSync(), seconds: 3, what: 'the note written at Begin');
      return d;
    }

    Future<void> recordUntil(double s) => until(() => session().elapsed >= s, seconds: (s + 30).ceil(), what: '$s s of recording');

    Future<void> hold() async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
    }

    /// Ask the script to kill the app now, with what was recorded; it never returns.
    Future<Never> kill(String key, Map<String, Object?> about, {required int next}) async {
      state[key] = about;
      save(next);
      debugPrint('KILL ${DateTime.now().millisecondsSinceEpoch} ${about['elapsed'] ?? ''}');
      await wait(60000);
      fail('the app was not killed');
    }

    Future<double> seconds(Blessing b) => NativeSpeech.instance.seconds(store.audioPath(b)!);

    /// The sheet's day and time, as the brief asks for it.
    String expectedBody(Map<String, Object?> c) =>
        Strings.recoveredBody([DateTime.fromMillisecondsSinceEpoch(c['began_utc_ms'] as int, isUtc: true).add(Duration(minutes: c['offset'] as int))]);
    Map<String, Object?> about(Blessing d, double elapsed) =>
        {'id': d.id, 'elapsed': elapsed, 'began_utc_ms': d.utc.millisecondsSinceEpoch, 'offset': d.utcOffset.inMinutes};
    Map<String, Object?> c(String key) => (state[key] as Map).cast<String, Object?>();

    /// Every file in the audio folder is some blessing's recording; nothing else is left.
    Future<void> noStrays(String when) async {
      final kept = {for (final b in await store.list()) b.audio}..remove('');
      final stray = files().where((f) => !kept.contains(f)).toList();
      expect(stray, isEmpty, reason: 'files that belong to no blessing $when');
    }

    Future<void> wordsWritten(String id) =>
        untilAsync(() async => (await store.get(id))!.wordsStatus != WordsStatus.pending, seconds: 120, what: 'the words of $id');

    switch (phase) {
      case 1:
        // ---- case 1: Begin, about 40 seconds, kill ----
        store = await freshSeededStore();
        await store.close();
        if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
        await launch();
        debugPrint('FILM START');
        await wait(800);
        final d = await begin();
        await recordUntil(40);
        debugPrint('AUDIO FOLDER ${files()}');
        await kill('c1', about(d, session().elapsed), next: 2);

      case 2:
        // ---- case 1, relaunched: the sheet, the sky, the review page ----
        final c1 = c('c1');
        final id = c1['id'] as String;
        debugPrint('FILM START');
        await launch();
        expect(sheetOn(), isTrue, reason: 'no sheet after the kill');
        expect(textOf('recovered-title'), 'A recording was kept');
        expect(textOf('recovered-body'), expectedBody(c1));
        debugPrint('SHEET ${textOf('recovered-body')}');
        final b = (await store.get(id))!;
        expect(b.draft, isTrue);
        expect(b.utc.millisecondsSinceEpoch, (c1['began_utc_ms'] as int) ~/ 60000 * 60000, reason: 'given the minute Begin was pressed');
        expect(e.blessings.any((x) => x.id == id), isTrue, reason: 'not in the sky');
        expect(e.blessings[e.focus].id, id, reason: 'the sky opens on it');
        expect(e.blessings.last.id, id, reason: 'at its true time: the newest');
        final got = await seconds(b);
        result('case1', 'recorded ${(c1['elapsed'] as num).toStringAsFixed(1)} s, recovered ${got.toStringAsFixed(1)} s');
        expect((c1['elapsed'] as num) - got, lessThanOrEqualTo(5), reason: 'more than 5 s lost');
        expect(got, lessThanOrEqualTo((c1['elapsed'] as num) + 1));
        await shot('01-sheet');
        await tester.tap(find.byKey(const Key('recovered-review')));
        await wait(2600);
        expect(stage('review'), isTrue);
        expect(sheetOn(), isFalse);
        await until(() => player().loaded, what: 'the recording to load');
        expect(((c1['elapsed'] as num) - player().duration).abs(), lessThanOrEqualTo(5), reason: 'the review page plays a different length');
        await tester.tap(find.byKey(const Key('listen-play')));
        await wait(2500);
        expect(player().playing, isTrue);
        expect(player().position, greaterThan(1), reason: 'it does not play');
        result('case1.review', 'plays, ${player().duration.toStringAsFixed(1)} s long');
        await shot('03-review');
        await tester.tap(find.byKey(const Key('listen-play')));
        await wordsWritten(id);
        await wait(600);
        await tester.tap(find.byKey(const Key('review-back')));
        await wait(2600);
        expect(stage('home'), isTrue);
        expect(textOf('cap-date'), b.longDate);
        await shot('02-sky');
        debugPrint('FILM END');
        expect(files(), ['$id.m4a'], reason: 'working files left after recovery');
        save(3);

      case 3:
        // ---- case 1, launched again: no sheet, one blessing, no stray files ----
        final c1 = c('c1');
        await launch();
        await wait(1000);
        expect(sheetOn(), isFalse, reason: 'case 1 told twice');
        final all = await store.list();
        expect(all.where((b) => b.id == c1['id']).length, 1, reason: 'case 1 made twice');
        expect(all.length, 6, reason: 'the five samples and case 1');
        expect(files(), ['${c1['id']}.m4a'], reason: 'stray files');
        result('case1.again', 'no sheet; ${all.length} blessings (5 samples + 1); audio folder ${files()}');

        // ---- case 2: 20 s, an interruption, 20 s more, kill ----
        final d = await begin();
        await recordUntil(20);
        await NativeSpeech.instance.debugInterrupt(true);
        await until(() => session().paused, what: 'the pause');
        await wait(2000);
        await NativeSpeech.instance.debugInterrupt(false);
        await until(() => !session().paused, what: 'listening again');
        await recordUntil(40);
        debugPrint('AUDIO FOLDER ${files()}');
        expect(files().where((f) => f.startsWith('${d.id}.part')).length, 2, reason: 'two parts');
        await kill('c2', about(d, session().elapsed), next: 4);

      case 4:
        // ---- case 2: one blessing, both stretches ----
        final c2 = c('c2');
        await launch();
        expect(sheetOn(), isTrue, reason: 'no sheet for case 2');
        expect(textOf('recovered-title'), 'A recording was kept');
        expect((await store.list()).length, 7);
        final b = (await store.get(c2['id'] as String))!;
        final got = await seconds(b);
        result('case2', 'recorded ${(c2['elapsed'] as num).toStringAsFixed(1)} s in two stretches, recovered ${got.toStringAsFixed(1)} s');
        expect((c2['elapsed'] as num) - got, lessThanOrEqualTo(5), reason: 'a stretch is missing');
        expect(got, greaterThan(25), reason: 'only one stretch');
        await tester.tap(find.byKey(const Key('recovered-later')));
        await wait(1200);
        expect(sheetOn(), isFalse);
        await wordsWritten(b.id);
        await noStrays('after case 2');
        expect(files().where((f) => !f.endsWith('.m4a')), isEmpty);

        // ---- case 3: 4 s, kill ----
        final d = await begin();
        await recordUntil(4);
        debugPrint('AUDIO FOLDER ${files()}');
        await kill('c3', about(d, session().elapsed), next: 5);

      case 5:
        // ---- case 3: kept however short ----
        final c3 = c('c3');
        final id3 = c3['id'] as String;
        // for the plural sheet only: a copy of case 3's note and part under another id, two minutes earlier
        final planted = 'aa${id3.substring(2)}';
        final note = RecordingNote.fromJson(jsonDecode(File(RecordingNote.pathFor(audio, id3)).readAsStringSync()))!;
        await RecordingNote(
          id: planted,
          began: note.began.subtract(const Duration(minutes: 2)),
          utcOffset: note.utcOffset,
          place: note.place,
          language: note.language,
        ).write(audio);
        for (final part in partsOf(audio, id3)) {
          part.copySync(p.join(audio, p.basename(part.path).replaceFirst(id3, planted)));
        }
        await launch();
        expect(sheetOn(), isTrue);
        expect(textOf('recovered-title'), 'Two recordings were kept');
        final b = (await store.get(id3))!;
        final got = await seconds(b);
        result('case3', 'recorded ${(c3['elapsed'] as num).toStringAsFixed(1)} s, recovered ${got.toStringAsFixed(1)} s');
        expect(got, greaterThan(0), reason: 'a short recording was not kept');
        await shot('04-plural');
        await tester.tap(find.byKey(const Key('recovered-later')));
        await wait(1200);
        await wordsWritten(id3);
        await wordsWritten(planted);
        await store.delete(planted);

        // ---- case 4: 15 s with the English passage fed in at Amen, Amen, kill before the words ----
        RecordSession.debugWordsDelay = const Duration(seconds: 10);
        final d = await begin();
        await NativeSpeech.instance.debugFeed('$audioFeed/en.m4a');
        await recordUntil(15);
        final elapsed = session().elapsed;
        await hold();
        await untilAsync(() async => await store.get(d.id) != null, seconds: 10, what: 'the blessing in the store after Amen');
        final saved = (await store.get(d.id))!;
        expect(saved.wordsStatus, WordsStatus.pending, reason: 'the words were written before the kill');
        expect(saved.rawText, isEmpty);
        await kill('c4', about(d, elapsed), next: 6);

      case 6:
        // ---- case 4: no sheet, the words written from the audio ----
        await NativeSpeech.instance.debugFeed(null);
        final c4 = c('c4');
        final id4 = c4['id'] as String;
        await launch();
        expect(sheetOn(), isFalse, reason: 'a sheet after a kill that came after Amen');
        expect(await store.get(id4), isNotNull);
        await wordsWritten(id4);
        final b = (await store.get(id4))!;
        expect(b.wordsStatus, WordsStatus.written);
        final werr = wordErrors(spokenEnglish, b.rawText);
        result('case4', 'recorded ${(c4['elapsed'] as num).toStringAsFixed(1)} s, then the ${(await seconds(b)).toStringAsFixed(1)} s English passage '
            'fed in at Amen; words written at the next launch, ${werr.errors} of ${werr.spoken} wrong');
        expect(b.rawText, contains('blessing of comfort'));
        expect(b.firstText, b.rawText);
        expect(File(RecordingNote.pathFor(audio, id4)).existsSync(), isFalse);

        // ---- case 5: 5 s, hold Discard, kill ----
        final d = await begin();
        await recordUntil(5);
        await hold();
        await wait(300);
        expect(session().live, isFalse, reason: 'Discard did nothing');
        expect(files().where((f) => f.startsWith(d.id)), isEmpty, reason: 'a discarded recording left files');
        await kill('c5', about(d, 5), next: 7);

      case 7:
        // ---- case 5: nothing recovered, nothing stray ----
        final c5 = c('c5');
        await launch();
        expect(sheetOn(), isFalse, reason: 'a discarded recording was recovered');
        expect(await store.get(c5['id'] as String), isNull);
        await noStrays('after a discard and a kill');
        result('case5', 'nothing recovered; audio folder: ${files().length} files, each a blessing\'s recording');

        // ---- case 6: kill within the first second ----
        final d = await begin();
        await wait(300);
        debugPrint('AUDIO FOLDER ${files()}');
        await kill('c6', about(d, session().elapsed), next: 8);

      case 8:
        // ---- case 6: starts normally whatever it finds ----
        final c6 = c('c6');
        await launch();
        expect(stage('home'), isTrue);
        final kept = await store.get(c6['id'] as String);
        result('case6', 'killed ${(c6['elapsed'] as num).toStringAsFixed(1)} s after Begin; started normally; '
            '${kept == null ? 'nothing had been recorded, nothing kept' : 'kept ${(await seconds(kept)).toStringAsFixed(1)} s'}');
        if (sheetOn()) {
          await tester.tap(find.byKey(const Key('recovered-later')));
          await wait(1200);
        }
        expect(files().where((f) => f.endsWith(RecordingNote.suffix)), isEmpty);
        await noStrays('after a kill in the first second');

        // ---- the reading page: For and the tags, above the last line ----
        final i = e.blessings.indexWhere((b) => b.id == 'surgery');
        expect(i, greaterThanOrEqualTo(0));
        e.setFocus(i, instant: true);
        await wait(1500);
        await tester.tap(find.byKey(const Key('read')));
        await wait(2600);
        expect(stage('read'), isTrue);
        expect(find.text('For Emma'), findsOneWidget);
        expect(find.text('Comfort  ·  Healing'), findsOneWidget);
        await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -6000));
        await wait(1500);
        expect(tester.getRect(find.byKey(const Key('read-for'))).top, lessThan(tester.getRect(find.byKey(const Key('read-sky'))).top));
        await shot('05-read-end');
        for (final r in results.entries) {
          debugPrint('SUMMARY ${r.key}: ${r.value}');
        }
        marker.deleteSync();
        debugPrint('ALL DONE');
    }
    debugPrint('PHASE $phase DONE');
  });
}
