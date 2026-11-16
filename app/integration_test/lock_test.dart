// The app lock, where blessings are given, and the Settings page, replayed on the simulator with real
// restarts. Run by tool/lock_acceptance.sh, which runs this once per phase with --keep-app-running
// and ends each phase with `xcrun simctl terminate`, so each phase is a new launch of the app with the
// real lock (on by default, nothing skipped) and the real location.
//
// The test asks the script for what only the simulator can do with `ACT <n> <what>` lines, and waits
// for its answer in the app's tmp folder (`act_<n>`):
//   face match | face nomatch     Face ID: the enrolled face, or another
//   tap <label>                   press a button in the system's own alert (tool/alerts, a UI test)
//   alert                         the title and text of the system alert on screen, or "none"
//   away <seconds>                Home, wait, open the app again
//   switcher <shot>               open the app switcher, screenshot it, open the app again
// Before each phase the script sets the simulator up for it (permissions, location, Face ID), as the
// NEXT line of the phase before asks. A marker in the documents folder says which phase runs.
//
//   1. Case 1, Mexico City: microphone, speech and location asked in that order; Begin; Amen; Save
//      for later. The place kept is Mexico City to a tenth of a degree; the ring sits on it.
//   2. Case 2, location refused: the Salt Lake Temple, said nowhere; Settings says it.
//   3. Case 3, locked at launch with the five samples: a stranger's face stays locked; a match opens.
//   4. Case 4, recording while locked: Save for later goes back to the locked sky; Review now asks.
//   5. Case 5, away 20 s stays open, 70 s locks, never during a recording.
//   6. Case 6, the app switcher from a reading page; case 7, the switch off (asks).
//   7. Case 7, opens unlocked; the switch back on (does not ask).
//   8. Case 7, locked again at launch; case 9, Español chosen in Settings.
//   9. Case 9, the Begin pull-down starts on Español. The script then removes the Face ID enrolment.
//  10. Case 8, no passcode: opens unlocked; Settings says why. A simulator cannot be without a
//      passcode (with Face ID removed it still answers "passcode"), so here the phone's answer is
//      replaced with "none"; the launch and the Settings page are real.
//
// Screenshots (the simulator's own, 3x): ../design/sim/lock/.

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
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

/// Mexico City, as the script sets the simulator's location.
const mexicoCity = (lat: 19.4326, lon: -99.1332);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('lock: the lock, the place, Settings', timeout: const Timeout(Duration(minutes: 9)), (tester) async {
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

    var shots = 0;
    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path; // <app data>/tmp, where the script answers
    final marker = File('$docs/lock_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    shots = (state['shots'] as int?) ?? 0;
    final results = (state['results'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    debugPrint('LOCK PHASE $phase');
    debugPrint('ACTDIR $tmp');

    void result(String key, Object? value) {
      results[key] = value;
      debugPrint('RESULT $key = $value');
    }

    /// The phase after this one, and what the script must set up for it.
    void next(int n, [Map<String, Object?> extra = const {}]) {
      marker.writeAsStringSync(jsonEncode({...state, ...extra, 'phase': n, 'shots': shots, 'results': results}), flush: true);
      debugPrint('NEXT $n');
    }

    Future<void> shot(String name, {int settle = 300}) async {
      await wait(settle);
      shots++;
      debugPrint('SIMSHOT lock/${shots.toString().padLeft(2, '0')}-$name');
      await wait(1500);
    }

    var acts = (state['acts'] as int?) ?? 0;

    /// Ask the script for something only the simulator can do, and wait for its answer. [during] is
    /// called while waiting (the app may be in the switcher or in the background).
    Future<String> act(String what, {int seconds = 120, Future<void> Function()? during}) async {
      acts++;
      final n = acts;
      final answer = File(p.join(tmp, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      debugPrint('ACT $n $what');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await during?.call();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      debugPrint('ACT $n -> $s');
      state['acts'] = acts;
      return s;
    }

    late BlessingStore store;
    late SkyEngine e;
    late AppLock lock;
    final audio = await defaultAudioDir();
    final settingsFile = File(p.join((await getApplicationSupportDirectory()).path, 'settings.json'));

    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    SettingsLayer settings() => tester.widget<SettingsLayer>(find.byType(SettingsLayer));
    String textOf(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
    /// "Salt Lake" is said nowhere on screen: the only mention is the Settings page's, kept in the
    /// tree while it is hidden.
    void templeUnsaid(String where) {
      final all = find.textContaining('Salt Lake');
      final inSettings = find.descendant(of: find.byKey(const Key('stage-settings')), matching: all);
      expect(stage('settings'), isFalse);
      expect(all.evaluate().length, inSettings.evaluate().length, reason: '$where mentions the Salt Lake Temple');
    }

    bool switchOn() => tester.widget<GoldSwitch>(find.byKey(const Key('settings-lock-switch'))).value;
    bool switchEnabled() => tester.widget<GoldSwitch>(find.byKey(const Key('settings-lock-switch'))).onChanged != null;

    /// A real launch: the real lock (on unless turned off, locked if so), the real location.
    Future<void> launch({bool fresh = false, bool samples = true, LockApi? api}) async {
      if (fresh) {
        store = await freshSeededStore(empty: !samples);
        await store.close();
        if (settingsFile.existsSync()) settingsFile.deleteSync();
      }
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      lock = AppLock(api: api ?? NativeLockApi());
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await until(() => lock.ready, what: 'the lock');
      debugPrint('LOCK method ${lock.method.name}, chosen ${lock.chosen}, locked ${lock.locked}');
    }

    /// The Face ID sheet is up (asked by the app); show the enrolled face.
    Future<void> match() async {
      await until(() => lock.asking, what: 'the Face ID sheet');
      await wait(1200);
      await act('face match');
      await until(() => !lock.asking, what: 'the answer');
      await wait(600);
    }

    /// The Face ID sheet is up; show another face, then Cancel on "Face Not Recognized".
    Future<void> stranger({String? shotName}) async {
      await until(() => lock.asking, what: 'the Face ID sheet');
      await wait(1200);
      await act('face nomatch');
      await wait(800);
      if (shotName != null) await shot(shotName, settle: 0);
      final t = await act('tap Cancel');
      expect(t, startsWith('ok Face Not Recognized'), reason: 'no "Face Not Recognized": $t');
      await until(() => !lock.asking, what: 'the answer');
      await wait(600);
    }

    /// Everything private is hidden: the engine has no blessings, the tree has none of the home's
    /// lights, ring, dates, caption, count or list; the header says Locked, Unlock and New blessing.
    Future<void> expectLockedSky() async {
      await wait(300);
      expect(lock.locked, isTrue);
      expect(stage('home'), isTrue);
      expect(e.blessings, isEmpty, reason: 'blessings given to the sky while locked');
      expect(find.byKey(const Key('locked-head')), findsOneWidget);
      expect(textOf('locked-line'), Strings.locked);
      expect(find.byKey(const Key('unlock')), findsOneWidget);
      expect(find.byKey(const Key('new')), findsOneWidget);
      for (final k in ['count', 'to-review', 'more', 'list', 'cap-date', 'cap-title', 'cap-from', 'read', 'ruler', 'older', 'newer', 'stage-list']) {
        expect(find.byKey(Key(k)), findsNothing, reason: '"$k" shown while locked');
      }
      // nothing of a blessing anywhere in the tree
      final words = [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? ''];
      for (final b in await store.list()) {
        if (b.title.isNotEmpty) expect(words.where((w) => w.contains(b.title)), isEmpty, reason: '"${b.title}" in the tree while locked');
      }
      expect(words.where((w) => w.contains('blessings since')), isEmpty);
      expect(find.byKey(const Key('recovered-sheet')).hitTestable(), findsNothing);
    }

    Future<void> hold(int ms) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(ms);
      await g.up();
    }

    /// New blessing, answered permissions (already granted), Begin, [seconds], Amen.
    Future<Blessing> record(double seconds, {bool open = true}) async {
      if (open) {
        await tester.tap(find.byKey(const Key('new')));
        await wait(2600);
      }
      expect(stage('record'), isTrue);
      await until(() => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue, reason: 'the microphone and speech should be allowed by now');
      await tester.tap(find.byKey(const Key('begin')));
      await until(() => session().live, seconds: 3, what: 'Begin');
      await until(() => session().elapsed >= seconds, seconds: seconds.ceil() + 30, what: '$seconds s of recording');
      final d = session().draft!;
      await hold(1100);
      await wait(2600);
      expect(stage('after'), isTrue, reason: 'no after-Amen screen');
      return d;
    }

    Future<void> saveForLater() async {
      await tester.tap(find.byKey(const Key('save-later')));
      await wait(3000);
      expect(stage('home'), isTrue);
    }

    Future<void> openSettings() async {
      await tester.tap(find.byKey(const Key('more')));
      await wait(2000);
      expect(stage('settings'), isTrue);
    }

    switch (phase) {
      case 1:
        // ---- case 1: Mexico City, location allowed ----
        await launch(fresh: true, samples: false);
        expect(lock.method, LockMethod.faceId, reason: 'Face ID should be enrolled');
        expect(lock.locked, isTrue);
        await match();
        expect(lock.locked, isFalse);
        await tester.tap(find.byKey(const Key('new')));
        // the three questions, in order, each answered as it comes
        final mic = await act('tap Allow');
        final speech = await act('tap Allow');
        await until(() => find.byKey(const Key('begin')).evaluate().isNotEmpty, what: 'the record screen');
        await wait(1500);
        await shot('location-prompt', settle: 0);
        final where = await act('tap Allow Once');
        result('case1.prompts', [mic, speech, where]);
        expect(mic, allOf(startsWith('ok'), contains('Microphone')));
        expect(speech, allOf(startsWith('ok'), contains('Speech Recognition')));
        expect(where, allOf(startsWith('ok'), contains('location')));
        expect(where, contains('Used once to place your first blessing'));
        await wait(1000);
        expect(await act('alert'), 'none', reason: 'a fourth question');
        final d = await record(11, open: false);
        await saveForLater();
        final kept = (await store.get(d.id))!;
        result('case1.place', '${kept.place.lat}, ${kept.place.lon}');
        // to a tenth of a degree; the simulator's approximate location may move it by one step
        expect(kept.place.lat, closeTo(19.4, .1001));
        expect(kept.place.lon, closeTo(-99.1, .1001));
        expect((kept.place.lat * 10).roundToDouble() / 10, kept.place.lat, reason: 'kept unrounded');
        expect((kept.place.lon * 10).roundToDouble() / 10, kept.place.lon, reason: 'kept unrounded');
        final stored = jsonDecode(settingsFile.readAsStringSync()) as Map;
        expect(stored['place'], {'lat': kept.place.lat, 'lon': kept.place.lon});
        expect(e.blessings.single.id, d.id);
        expect(e.blessings.single.dec, closeTo(kept.place.lat * deg, 1e-9), reason: 'the ring is not on Mexico City\'s latitude');
        result('case1.ring', 'dec ${(e.blessings.single.dec / deg).toStringAsFixed(4)}°');
        next(2);

      case 2:
        // ---- case 2: location refused ----
        await launch(fresh: true, samples: false);
        await match();
        await tester.tap(find.byKey(const Key('new')));
        await until(() => find.byKey(const Key('begin')).evaluate().isNotEmpty, what: 'the record screen');
        final where = await act('tap Don\'t Allow');
        expect(where, allOf(startsWith('ok'), contains('location')));
        await wait(800);
        final d = await record(11, open: false);
        templeUnsaid('the after-Amen screen');
        await saveForLater();
        templeUnsaid('the sky');
        final kept = (await store.get(d.id))!;
        expect([kept.place.lat, kept.place.lon], [saltLakeTemple.lat, saltLakeTemple.lon]);
        expect(e.blessings.single.dec, closeTo(saltLakeTemple.lat * deg, 1e-9));
        result('case2.place', '${kept.place.lat}, ${kept.place.lon} (Salt Lake Temple)');
        await openSettings();
        expect(textOf('settings-place'), Strings.nearTemple);
        expect(find.text(Strings.useMyLocation), findsOneWidget);
        expect(switchOn(), isTrue);
        expect(textOf('settings-lock-hint'), Strings.lockHint(LockMethod.faceId));
        expect(textOf('settings-version'), startsWith('Version '));
        await shot('settings-lock-on-fallback-place');
        next(3);

      case 3:
        // ---- case 3: locked at launch, the five samples ----
        debugPrint('FILM START');
        await launch(fresh: true);
        expect((await store.list()).length, 5);
        await expectLockedSky();
        await until(() => lock.asking, what: 'the automatic question');
        await wait(1200);
        await shot('face-id-prompt', settle: 0);
        await stranger();
        await expectLockedSky();
        await shot('locked-sky');
        await tester.tap(find.byKey(const Key('unlock')));
        await match();
        expect(lock.locked, isFalse);
        await wait(1500);
        expect(e.blessings.length, 5);
        expect(find.byKey(const Key('count')), findsOneWidget);
        expect(find.byKey(const Key('more')), findsOneWidget);
        expect(find.byKey(const Key('cap-title')), findsOneWidget);
        await shot('home-more');
        result('case3', 'locked: engine empty, no lights/count/list/caption; a stranger stays locked; a match shows 5');
        debugPrint('FILM END');
        next(4);

      case 4:
        // ---- case 4: recording while locked ----
        debugPrint('FILM START');
        await launch();
        await stranger();
        await expectLockedSky();
        final before = (await store.list()).where((b) => b.draft).length;
        final d1 = await record(12);
        expect(lock.locked, isTrue);
        expect(find.byKey(const Key('save-later')), findsOneWidget);
        await shot('after-amen-locked');
        await saveForLater();
        await expectLockedSky();
        final drafts = (await store.list()).where((b) => b.draft).length;
        expect(drafts, before + 1);
        expect((await store.get(d1.id))!.draft, isTrue);
        result('case4.later', 'back on the locked sky; drafts $before -> $drafts; engine ${e.blessings.length}');
        // Review now: a failure stays on the after-Amen screen; a match opens the review page
        await record(11);
        await tester.tap(find.byKey(const Key('review-now')));
        await stranger();
        await wait(600);
        expect(stage('after'), isTrue, reason: 'left the after-Amen screen without unlocking');
        expect(lock.locked, isTrue);
        await tester.tap(find.byKey(const Key('review-now')));
        await match();
        await wait(2600);
        expect(stage('review'), isTrue);
        expect(lock.locked, isFalse);
        result('case4.review', 'a stranger stays on the after-Amen screen; a match opens the review page');
        debugPrint('FILM END');
        next(5);

      case 5:
        // ---- case 5: away 20 s, 70 s, and during a recording ----
        await launch();
        await match();
        await act('away 20', seconds: 90);
        await wait(1500);
        expect(lock.locked, isFalse, reason: 'locked after 20 s away');
        expect(lock.asking, isFalse);
        await act('away 70', seconds: 150);
        await until(() => lock.locked, seconds: 5, what: 'the lock after 70 s away');
        await until(() => lock.asking, what: 'the automatic question');
        await match();
        result('case5.away', '20 s: open; 70 s: locked, asked once, unlocked by a match');
        // during a recording
        await tester.tap(find.byKey(const Key('new')));
        await wait(2600);
        await until(() => session().permissions != null, what: 'permissions');
        await tester.tap(find.byKey(const Key('begin')));
        await until(() => session().live, seconds: 3, what: 'Begin');
        await act('away 70', seconds: 150);
        await wait(1500);
        expect(session().live, isTrue);
        expect(lock.locked, isFalse, reason: 'locked during a recording');
        expect(lock.asking, isFalse);
        result('case5.recording', 'away 70 s while recording: not locked, still recording ${session().elapsed.toStringAsFixed(0)} s');
        await hold(1100);
        await wait(2600);
        await saveForLater();
        next(6);

      case 6:
        // ---- case 6: the app switcher from a reading page ----
        await launch();
        await match();
        await wait(1500);
        await tester.tap(find.byKey(const Key('read')));
        await wait(2600);
        expect(stage('read'), isTrue);
        var covered = false;
        shots++;
        final s = await act('switcher lock/${shots.toString().padLeft(2, '0')}-app-switcher', during: () async {
          if (!covered) covered = await NativeLockApi.debugCovered();
        });
        expect(s, startsWith('ok'));
        expect(covered, isTrue, reason: 'the app was in the switcher without its cover');
        await wait(1500);
        expect(await NativeLockApi.debugCovered(), isFalse, reason: 'the cover stayed up');
        result('case6', 'covered while in the switcher (native), lifted on return');
        await tester.tap(find.byKey(const Key('read-back')));
        await wait(2600);
        expect(stage('home'), isTrue);
        // ---- case 7: the switch off asks first ----
        await openSettings();
        await tester.tap(find.byKey(const Key('settings-lock-switch')));
        await stranger();
        expect(switchOn(), isTrue, reason: 'turned off without proving it is them');
        await tester.tap(find.byKey(const Key('settings-lock-switch')));
        await match();
        expect(switchOn(), isFalse);
        expect(lock.chosen, isFalse);
        await shot('settings-lock-off');
        next(7);

      case 7:
        // ---- case 7: opens unlocked; the switch back on does not ask ----
        await launch();
        expect(lock.chosen, isFalse);
        expect(lock.locked, isFalse);
        await wait(2500);
        expect(lock.asking, isFalse);
        expect(await act('alert'), 'none', reason: 'asked at launch with the lock off');
        expect(e.blessings, isNotEmpty);
        await openSettings();
        await tester.tap(find.byKey(const Key('settings-lock-switch')));
        await wait(1200);
        expect(lock.asking, isFalse);
        expect(await act('alert'), 'none', reason: 'turning the lock on asked');
        expect(switchOn(), isTrue);
        result('case7', 'off after a match (a stranger could not); relaunch unlocked; on without asking');
        next(8);

      case 8:
        // ---- case 7: locked at launch again; case 9: Español in Settings ----
        await launch();
        expect(lock.locked, isTrue);
        await match();
        await openSettings();
        expect(tester.widget<SettingsLanguageControl>(find.byType(SettingsLanguageControl)).code, isNull);
        tester.state<SettingsLanguageControlState>(find.byType(SettingsLanguageControl)).debugPick('es');
        await wait(800);
        expect(settings().language, 'es');
        expect(textOf('settings-language-label'), 'Español');
        result('case7.again', 'locked at launch again');
        next(9);

      case 9:
        // ---- case 9: the Begin pull-down starts on Español ----
        await launch();
        await stranger(); // recording does not wait for the lock
        await tester.tap(find.byKey(const Key('new')));
        await wait(2600);
        await until(() => session().permissions != null, what: 'permissions');
        expect(session().language.code, 'es');
        expect(textOf('language-label'), 'Español');
        await shot('begin-espanol');
        result('case9', 'the pull-down on Begin starts on ${textOf('language-label')}');
        await tester.tap(find.byKey(const Key('rec-x')));
        await wait(2000);
        next(10);

      case 10:
        // ---- case 8: no passcode ----
        // A simulator always has a passcode in iOS's eyes: with Face ID removed it still answers
        // "passcode", and it cannot be removed. So the phone's answer is replaced with "none" here;
        // the launch, the settings on disk and the Settings page are the real ones.
        final real = await NativeLockApi().method();
        result('case8.simulator', 'Face ID removed: the simulator answers ${real.name}');
        expect(real, isNot(LockMethod.faceId));
        await launch(api: _NoPasscode());
        expect(lock.method, LockMethod.none);
        expect(lock.chosen, isTrue, reason: 'the choice is kept');
        expect(lock.locked, isFalse);
        await wait(2000);
        expect(lock.asking, isFalse);
        expect(await act('alert'), 'none');
        expect(e.blessings, isNotEmpty);
        await openSettings();
        expect(switchOn(), isFalse);
        expect(switchEnabled(), isFalse);
        expect(textOf('settings-lock-hint'), Strings.noPasscode);
        await shot('settings-no-passcode');
        result('case8', 'opens unlocked; switch off and disabled; "${Strings.noPasscode}"');
        for (final r in results.entries) {
          debugPrint('SUMMARY ${r.key}: ${r.value}');
        }
        marker.deleteSync();
        debugPrint('ALL DONE');
    }
  });
}

/// The phone as iOS describes one with no passcode; everything else (the cover, the version) real.
class _NoPasscode extends NativeLockApi {
  @override
  Future<LockMethod> method() async => LockMethod.none;
  @override
  Future<bool> authenticate(String reason) async => fail('asked to authenticate with no passcode');
}
