// The owner's rulings of 2026-11-15, replayed on the simulator. Run by tool/drafts_acceptance.sh,
// which builds with SPEECH_AUDIO, grants the permissions, runs this twice with --keep-app-running and
// terminates the app between the runs, so the second is a real new launch.
//
//   1. Two drafts waiting (one with a real recording): the home badge reads "2 to review"; the list
//      marks both rows "Not reviewed". The badge opens the oldest. A tag typed "healing" is stored
//      "Healing". The recording plays; the app is sent to the background (the script opens the
//      Settings app) and brought back: the elapsed time kept running meanwhile. Finish; the badge
//      reads "1 to review" and opens the other; Done; the badge is gone.
//      Then a draft is left whose words "could not be written on this phone" (marked so by the test,
//      with the English recording as its audio), and the app is terminated.
//   2. The next launch tries those words again; English can be written here, so they arrive, quietly,
//      without a sheet, and the review page shows them.
//
// Screenshots (SIMSHOT): ../design/sim/polish/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/recovered_sheet.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('drafts: badge, list note, tags, playback in the background, words tried again', timeout: const Timeout(Duration(minutes: 6)),
      (tester) async {
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
      debugPrint('SIMSHOT polish/$name');
      await wait(1500);
    }

    expect(audioDir, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    final docs = (await getApplicationDocumentsDirectory()).path;
    final marker = File('$docs/drafts_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final audio = await defaultAudioDir();
    debugPrint('DRAFTS PHASE $phase');

    late BlessingStore store;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    Player player() => tester.widget<ReviewLayer>(find.byType(ReviewLayer)).player;
    String text(String key) => tester.widget<CupertinoTextField>(find.byKey(Key(key))).controller!.text;
    String? badge() => find.byKey(const Key('to-review-text')).evaluate().isEmpty ? null : tester.widget<Text>(find.byKey(const Key('to-review-text'))).data;

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

    Blessing draft(String id, DateTime utc, {String audioFile = '', String raw = '', WordsStatus status = WordsStatus.written}) => Blessing(
          id: id,
          title: 'Blessing',
          from: '',
          utc: utc,
          utcOffset: const Duration(hours: -7),
          place: samplePlace,
          rawText: raw,
          firstText: raw,
          audio: audioFile,
          language: 'en',
          wordsStatus: status,
          draft: true,
        );

    Future<void> copyAudio(String id) async {
      await Directory(audio).create(recursive: true);
      await File('$audioDir/en.m4a').copy(p.join(audio, '$id.m4a'));
    }

    if (phase == 1) {
      store = await freshSeededStore();
      if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
      // the older draft has the English recording; the newer was typed in later, with no recording
      await copyAudio('d0a0');
      await store.create(draft('d0a0', DateTime.utc(2025, 5, 4, 18), audioFile: 'd0a0.m4a', raw: 'Words heard when it was recorded.'));
      await store.create(draft('d0b0', DateTime.utc(2026, 11, 10, 2), raw: 'A later blessing, not yet reviewed.'));
      await launch(store);

      // ---- the badge, and the list ----
      expect(badge(), '2 to review');
      await shot('01-home-badge');
      await tester.tap(find.byKey(const Key('list')));
      await wait(1200);
      expect(find.byKey(const Key('row-draft-d0a0')), findsOneWidget);
      expect(find.byKey(const Key('row-draft-d0b0')), findsOneWidget);
      expect(find.byKey(const Key('row-draft-surgery')), findsNothing, reason: 'a reviewed blessing carries no note');
      await shot('02-list-not-reviewed');
      await tester.tap(find.byKey(const Key('list')));
      await wait(1200);

      // ---- the badge opens the oldest draft ----
      await tester.tap(find.byKey(const Key('to-review')));
      await wait(2600);
      expect(stage('review'), isTrue);
      expect(tester.widget<ReviewLayer>(find.byType(ReviewLayer)).blessing!.id, 'd0a0', reason: 'the oldest draft');

      // ---- a tag typed "healing" is stored "Healing" ----
      await Scrollable.ensureVisible(tester.element(find.byKey(const Key('review-tag'))), alignment: .5);
      await tester.tap(find.byKey(const Key('review-tag')));
      await wait(600);
      await tester.enterText(find.byKey(const Key('review-tag')), 'healing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await wait(ReviewLayer.saveAfter.inMilliseconds + 600);
      expect(find.byKey(const Key('tag-Healing')), findsOneWidget);
      expect((await store.get('d0a0'))!.tags, ['Healing']);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(800);

      // ---- playback carries on in the background ----
      await until(() => player().loaded, what: 'the recording to load');
      await tester.tap(find.byKey(const Key('listen-play')));
      await wait(1500);
      expect(player().playing, isTrue);
      // the native player's own clock (AVAudioPlayer.currentTime), asked directly
      Future<({double at, bool playing})> native() async {
        final r = (await const MethodChannel('upon_thy_head/player').invokeMapMethod<String, Object?>('position'))!;
        return (at: (r['position'] as num).toDouble(), playing: r['playing'] as bool);
      }

      final n0 = await native();
      final t0 = DateTime.now();
      final samples = <String>[];
      debugPrint('BACKGROUND ${n0.at.toStringAsFixed(2)}');
      // The script opens Settings; the app leaves the screen. No frames are drawn off screen, so
      // from here until it is back the test waits on timers, not on frames.
      Future<void> poll(bool Function() ok, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (!ok()) {
          if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      await poll(() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused, 'the app to go to the background');
      final away = DateTime.now();
      while (DateTime.now().difference(away) < const Duration(seconds: 6)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final n = await native();
        samples.add('${WidgetsBinding.instance.lifecycleState?.name} +${(DateTime.now().difference(t0).inMilliseconds / 1000).toStringAsFixed(2)}s '
            'position ${n.at.toStringAsFixed(2)} playing=${n.playing}');
      }
      debugPrint('FOREGROUND');
      await poll(() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed, 'the app to come back');
      final n1 = await native();
      final elapsed = DateTime.now().difference(t0).inMilliseconds / 1000;
      for (final s in samples) {
        debugPrint('IN BACKGROUND $s');
      }
      debugPrint('RESULT background: native position ${n0.at.toStringAsFixed(2)} -> ${n1.at.toStringAsFixed(2)} s '
          'over ${elapsed.toStringAsFixed(2)} s of wall time; playing=${n1.playing}');
      await wait(800);
      expect(n1.playing, isTrue, reason: 'playback stopped when the app left the screen');
      expect(n1.at - n0.at, closeTo(elapsed, 1.0), reason: 'the recording did not keep playing in the background');
      expect(samples.every((s) => s.startsWith('paused') && s.endsWith('playing=true')), isTrue, reason: 'every sample in the background: playing');
      expect(player().playing, isTrue);
      await shot('03-playing-after-background');
      await tester.tap(find.byKey(const Key('listen-play')));
      await wait(400);

      // ---- finish it; the badge counts one, and opens the other ----
      await tester.tap(find.byKey(const Key('review-done')));
      await wait(900);
      await tester.tap(find.byKey(const Key('finish-confirm')));
      await wait(2600);
      expect(stage('read'), isTrue);
      await tester.tap(find.byKey(const Key('read-back')));
      await wait(2600);
      expect(badge(), '1 to review');
      await shot('04-home-badge-one');
      await tester.tap(find.byKey(const Key('to-review')));
      await wait(2600);
      expect(tester.widget<ReviewLayer>(find.byType(ReviewLayer)).blessing!.id, 'd0b0');
      await tester.tap(find.byKey(const Key('review-done')));
      await wait(2600);
      await tester.tap(find.byKey(const Key('read-back')));
      await wait(2600);
      expect(badge(), isNull, reason: 'no drafts: no badge');
      expect(find.byKey(const Key('to-review')), findsNothing);
      await shot('05-home-no-badge');

      // ---- a draft whose words could not be written, left for the next launch ----
      await copyAudio('d0c0');
      await store.create(draft('d0c0', DateTime.utc(2026, 11, 14, 3), audioFile: 'd0c0.m4a', status: WordsStatus.unavailable));
      marker.writeAsStringSync(jsonEncode({'phase': 2}));
      debugPrint('PHASE 1 DONE');
    } else {
      // ---- the next launch: the words are tried again, quietly ----
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      expect((await store.get('d0c0'))!.wordsStatus, WordsStatus.unavailable);
      final t0 = DateTime.now();
      await launch(store);
      expect(tester.widget<RecoveredSheet>(find.byType(RecoveredSheet)).on, isFalse, reason: 'quietly: no sheet');
      Blessing? got;
      final end = DateTime.now().add(const Duration(seconds: 60));
      while ((got = await store.get('d0c0'))!.rawText.isEmpty) {
        if (DateTime.now().isAfter(end)) fail('the words were not tried again');
        await wait(250);
      }
      debugPrint('RESULT retried: ${got!.wordsStatus.code} after ${DateTime.now().difference(t0).inMilliseconds} ms: <<<${got.rawText}>>>');
      expect(got.wordsStatus, WordsStatus.written);
      expect(got.firstText, got.rawText);
      expect(got.rawText, contains('blessing of comfort'));
      expect(badge(), '1 to review');
      await tester.tap(find.byKey(const Key('to-review')));
      await wait(2600);
      expect(text('review-words'), got.rawText);
      expect(find.byKey(const Key('review-no-words')), findsNothing);
      await shot('06-words-written-on-retry');
      await tester.tap(find.byKey(const Key('review-back')));
      await wait(1500);
      marker.deleteSync();
      debugPrint('ALL DONE');
    }
  });
}
