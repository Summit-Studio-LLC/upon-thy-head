// The iPad pass on the simulator: every main screen in portrait, then landscape. Run by
// tool/ipad_acceptance.sh, once per phase with --keep-app-running (each phase a new launch):
//
//   1. English: the first run (welcome, permissions, the rehearsal's start) on an empty store of
//      its own; then the seeded app: home, the capsule's menu, the list, a family member added and
//      their sky, New blessing to the recording start, a real recording (SPEECH_AUDIO) to Amen,
//      the screen after Amen, review with the keyboard up and words typed, the app rotated with
//      them typed (nothing lost), the finish question, Save, the reading page, Edit, the delete
//      question, the share sheet, text and PDF through the system sheet (it must appear), Settings,
//      Your links, Manage family, the lock and its unlock. Then all of it again in landscape.
//      With `last` 1 in the marker (the 13-inch run) the test ends there.
//   2. Spanish (the script sets the app's language): home, the recording start, review, the
//      reading page and Settings, portrait and landscape.
//   3. The largest text size (the script sets it): the same.
//
// `ACT <n> <what>` lines are answered by the script, in the app's tmp folder (`act_<n>`):
//   orient portrait|landscape   XCUIDevice's orientation (tool/alerts)
//   appdismiss <i>              close the system share sheet
//   unlock                      the simulator's enrolled finger and face both match
// Screenshots: SIMSHOT <name>; the script puts them in design/sim/ipad/ (or 13/).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('iPad: every main screen, portrait and landscape', timeout: const Timeout(Duration(minutes: 28)), (t) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path;
    final marker = File('$docs/ipad_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    final last = (state['last'] as int?) ?? 3;
    var acts = (state['acts'] as int?) ?? 0;
    debugPrint('IPAD PHASE $phase');
    debugPrint('ACTDIR $tmp');
    void next(int n) {
      if (n > last) {
        marker.deleteSync();
        debugPrint('ALL DONE');
        return;
      }
      marker.writeAsStringSync(jsonEncode({...state, 'phase': n, 'acts': acts}), flush: true);
      debugPrint('NEXT $n');
    }

    var prefix = '';
    var orient = 'p';
    final seen = <String>[];
    Future<void> shot(String name, {int settle = 500}) async {
      await wait(settle);
      seen.add(name);
      debugPrint('SIMSHOT $prefix$orient-$name');
      await wait(1400);
    }

    Future<String> act(String what, {int seconds = 90}) async {
      acts++;
      final n = acts;
      final answer = File(p.join(tmp, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      debugPrint('ACT $n $what');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await t.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      debugPrint('ACT $n -> $s');
      return s;
    }

    Size screen() => MediaQuery.sizeOf(t.element(find.byType(HomeScreen)));
    Future<void> rotate(String to) async {
      await act('orient $to');
      orient = to == 'landscape' ? 'l' : 'p';
      await until(() => (screen().width > screen().height) == (to == 'landscape'), seconds: 15, what: 'the turn to $to');
      await wait(1800);
      debugPrint('SCREEN ${screen()}');
    }

    expect(audioDir, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    late BlessingStore store;
    late AppLock lock;
    bool stage(String name) => t.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    SkyEngine engine() => t.widget<SkyWidget>(find.byKey(const Key('sky'))).engine;
    bool here(String key) => find.byKey(Key(key)).hitTestable().evaluate().isNotEmpty;

    Future<void> tap(String key, {int settle = 1200}) async {
      final f = find.byKey(Key(key));
      await until(() => f.evaluate().isNotEmpty, what: key);
      final scroll = find.ancestor(of: f, matching: find.byType(Scrollable));
      if (f.hitTestable().evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
        await t.scrollUntilVisible(f, 150, scrollable: scroll.first);
        await wait(400);
      }
      await until(() => f.hitTestable().evaluate().isNotEmpty, what: key);
      await t.tap(f.hitTestable().first);
      await wait(settle);
    }

    Future<void> launch({bool firstRun = false, BlessingStore? on}) async {
      // as main() does
      Strings.iPad = Strings.detectIPad();
      expect(Strings.iPad, isTrue, reason: 'run on an iPad');
      Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
      lock = unlockedLock();
      HomeScreen.debugSkipFirstRun = !firstRun;
      await t.pumpWidget(UponThyHeadApp(store: on ?? store, stats: false, demo: false, lock: lock));
      final ready = firstRun ? find.byKey(const Key('welcome')) : find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && ready.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(ready, findsOneWidget, reason: 'the app never got to its first screen');
      await until(() => lock.ready, what: 'the lock');
      await wait(2500);
    }

    Future<void> focusOn(String id) async {
      final i = engine().blessings.indexWhere((b) => b.id == id);
      expect(i, greaterThanOrEqualTo(0), reason: 'no blessing $id');
      engine().setFocus(i, instant: true);
      await wait(1400);
    }

    Future<void> closeSystemSheet() async {
      for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
        await act('appdismiss $i');
        await wait(1500);
      }
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (await NativeShareApi.debugShowing()) {
        if (DateTime.now().isAfter(end)) fail('the share sheet did not close');
        await wait(200);
      }
      await wait(800);
    }

    Future<void> systemShare(String kind) async {
      await tap('read-share', settle: 1000);
      if (kind == 'text') await shot('20-share-sheet');
      await tap('share-$kind', settle: 400);
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (!await NativeShareApi.debugShowing()) {
        if (DateTime.now().isAfter(end)) fail('the system share sheet for $kind never appeared');
        await wait(200);
      }
      await wait(1600);
      await shot('21-system-$kind', settle: 300);
      await closeSystemSheet();
      expect(stage('read'), isTrue, reason: 'the reading page is still there after the $kind sheet');
    }

    /// The first run, on an empty store of its own (the real one is left as it is).
    Future<void> firstRun() async {
      final settings = await Settings.open();
      final was = settings.firstRun;
      await settings.setFirstRun(null);
      // a fresh install's store every time (the first pass may have left something in it)
      final emptyPath = '${(await getTemporaryDirectory()).path}/ipad_first_run.sqlite';
      for (final f in [emptyPath, '$emptyPath-wal', '$emptyPath-shm']) {
        if (File(f).existsSync()) File(f).deleteSync();
      }
      final empty = SqliteBlessingStore.open(emptyPath);
      // a new app, not the one already up (the same widget would keep its state)
      await t.pumpWidget(const SizedBox());
      await wait(500);
      await launch(firstRun: true, on: empty);
      await shot('01-welcome');
      await tap('welcome-continue', settle: 2200);
      await shot('02-permissions');
      if (here('permissions-continue')) {
        await tap('permissions-continue', settle: 2600);
        await shot('03-after-permissions');
        if (here('try-it')) {
          await tap('try-it', settle: 2600);
          await shot('04-rehearsal');
        }
      }
      await t.pumpWidget(const SizedBox());
      await wait(500);
      await empty.close();
      await (await Settings.open()).setFirstRun(was);
    }

    /// Typed words must survive a turn of the iPad.
    Future<void> turnWithWordsTyped(String typed) async {
      final field = find.byKey(const Key('review-title'));
      final text = find.descendant(of: field, matching: find.byType(EditableText));
      final controller = t.widget<EditableText>(text.first).controller;
      expect(controller.text, typed);
      final scroll = find.descendant(of: find.byKey(const Key('stage-review')), matching: find.byType(Scrollable)).first;
      final offset = t.state<ScrollableState>(scroll).position.pixels;
      final to = orient == 'p' ? 'landscape' : 'portrait', back = orient == 'p' ? 'portrait' : 'landscape';
      await rotate(to);
      expect(stage('review'), isTrue, reason: 'review is still open after the turn');
      expect(t.widget<EditableText>(text.first).controller.text, typed, reason: 'the typed words survived the turn');
      await shot('16-turned-with-words');
      await rotate(back);
      expect(t.widget<EditableText>(text.first).controller.text, typed, reason: 'the typed words survived the turn back');
      debugPrint('RESULT turned twice with "$typed" typed; scroll ${offset.toStringAsFixed(0)} -> '
          '${t.state<ScrollableState>(scroll).position.pixels.toStringAsFixed(0)}');
    }

    /// The main path, in the orientation the iPad is in now.
    Future<void> walk({bool full = true}) async {
      expect(stage('home'), isTrue);
      await shot('05-home');
      final focus = engine().focus;
      if (full) {
        await tap('sky-switch', settle: 800);
        await shot('06-capsule-menu');
        await tap('pull-down-${SkyMenu.me}', settle: 1200);
        await tap('list', settle: 1200);
        await shot('07-list');
        await tap('list', settle: 1400);
        // a family member: added in portrait, their sky shown; in landscape the menu has them
        final people = await store.people();
        if (people.isEmpty) {
          await tap('sky-switch', settle: 800);
          await tap('pull-down-${SkyMenu.add}', settle: 1400);
          await shot('08-add-family');
          await tap('person-name', settle: 1200);
          await t.enterText(find.byKey(const Key('person-name')), 'Emma');
          await shot('09-add-family-keyboard');
          await tap('person-save', settle: 2600);
        } else {
          await tap('sky-switch', settle: 800);
          await tap('pull-down-${SkyMenu.person(people.first.id)}', settle: 2200);
        }
        expect(stage('home'), isTrue);
        await shot('10-family-sky');
        await tap('sky-switch', settle: 800);
        await shot('11-menu-with-family');
        await tap('pull-down-${SkyMenu.me}', settle: 2200);
      }
      // New blessing to the recording start, Begin, Amen
      await tap('new', settle: 2600);
      expect(stage('record'), isTrue);
      await shot('12-record-start');
      var recorded = false;
      if (full && here('begin')) {
        await tap('begin', settle: 6000);
        if (here('hold')) {
          await shot('13-recording');
          await tap('rec-x', settle: 1200);
          if (here('sheet-keep')) {
            await shot('13b-discard-question');
            await tap('sheet-keep', settle: 1200);
          }
          await wait(4000);
          final g = await t.startGesture(t.getCenter(find.byKey(const Key('hold'))));
          await wait(2600);
          await g.up();
          await wait(3500);
          recorded = stage('after');
          if (recorded) {
            await shot('14-after-amen', settle: 2500);
            await tap('review-now', settle: 2600);
          }
        } else {
          await shot('13-recording-did-not-start');
        }
      }
      if (!recorded) {
        if (stage('record')) await tap('rec-x', settle: 2200);
        // the seeded draft's review
        await focusOn('ipad-draft');
        await tap('read', settle: 2600);
        await tap('read-edit', settle: 2600);
      }
      expect(stage('review'), isTrue);
      await shot('15-review');
      // the keyboard up: words typed into the title
      final typed = 'Typed on the iPad, $orient';
      await tap('review-title', settle: 1500);
      await t.enterText(find.byKey(const Key('review-title')), typed);
      await wait(800);
      await shot('15b-review-keyboard-title');
      final words = find.byKey(const Key('review-words'));
      await t.ensureVisible(words);
      await wait(500);
      final box = t.getRect(words);
      await t.tapAt(Offset(box.left + 80, box.top + 14));
      await wait(1800);
      debugPrint('KEYBOARD ${MediaQuery.viewInsetsOf(t.element(find.byKey(const Key('stage-review')))).bottom}');
      await shot('15c-review-keyboard-words');
      if (full) await turnWithWordsTyped(typed);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(1200);
      if (full && here('review-polish')) {
        await tap('review-polish', settle: 2400);
        if (here('review-polished')) {
          await tap('review-polished', settle: 2400);
          if (stage('changes')) {
            await shot('17-changes');
            if (here('changes-words')) {
              final r = t.getRect(find.byKey(const Key('changes-words')));
              await t.tapAt(r.topLeft + const Offset(40, 12));
              await wait(1200);
              if (here('changes-sheet')) await shot('17b-changes-sheet');
            }
            if (here('changes-done')) await tap('changes-done', settle: 2200);
            if (stage('changes') && here('changes-back')) await tap('changes-back', settle: 2200);
          }
        }
      }
      expect(stage('review'), isTrue);
      await tap('review-done', settle: 1600);
      if (here('finish-confirm')) {
        await shot('18-finish-question');
        await tap('finish-confirm', settle: 3000);
      }
      if (!stage('read')) {
        if (stage('home')) await tap('read', settle: 2600);
      }
      expect(stage('read'), isTrue, reason: 'Save leads to the reading page');
      await shot('19-reading');
      if (full) {
        await tap('read-edit', settle: 2600);
        await shot('19b-edit');
        await tap('review-back', settle: 2200);
        if (!stage('read') && here('read')) await tap('read', settle: 2600);
        await tap('read-delete', settle: 1200);
        await shot('19c-delete-question');
        await tap('delete-keep', settle: 1200);
        await systemShare('text');
        await systemShare('pdf');
      }
      await tap('read-back', settle: 2400);
      expect(stage('home'), isTrue);
      // Settings, Your links, Manage family
      await tap('more', settle: 2400);
      expect(stage('settings'), isTrue);
      await shot('22-settings');
      if (full) {
        final scroll = find.descendant(of: find.byKey(const Key('stage-settings')), matching: find.byType(Scrollable)).first;
        await t.drag(scroll, const Offset(0, -900));
        await wait(1200);
        await shot('23-settings-lower');
        if (find.byKey(const Key('settings-links')).evaluate().isNotEmpty) {
          await tap('settings-links', settle: 2400);
          await shot('24-your-links');
          await tap('links-back', settle: 2400);
        }
      }
      await tap('settings-back', settle: 2400);
      if (full && (await store.people()).isNotEmpty) {
        await tap('sky-switch', settle: 800);
        await tap('pull-down-${SkyMenu.manage}', settle: 2200);
        await shot('25-manage-family');
        final person = (await store.people()).first;
        await tap('family-row-${person.id}', settle: 2200);
        await shot('26-change-person');
        await tap('person-remove', settle: 1200);
        await shot('27-remove-question');
        await tap('remove-keep', settle: 1200);
        await tap('person-back', settle: 2200);
        await tap('family-back', settle: 2200);
      }
      if (full) {
        // the lock: locked home, then the unlock
        lock.lock();
        await wait(2500);
        await shot('28-locked');
        if (here('unlock')) {
          await tap('unlock', settle: 600);
          await act('unlock');
          await until(() => !lock.locked, seconds: 30, what: 'the unlock');
          await wait(2500);
          await shot('29-unlocked');
        }
      }
      expect(stage('home'), isTrue);
      debugPrint('RESULT focus before $focus, now ${engine().focus}');
    }

    switch (phase) {
      case 1:
        await act('orient portrait');
        await firstRun();
        store = await freshSeededStore();
        await store.create(Blessing(
          id: 'ipad-draft',
          title: Strings.wordsFor(Strings.language).untitled,
          from: '',
          utc: DateTime.utc(2026, 11, 2, 3),
          utcOffset: const Duration(hours: -7),
          place: samplePlace,
          rawText: 'I lay my hands upon your head and bless you with peace. Remember that the Lord knows you.',
          firstText: 'I lay my hands upon your head and bless you with peace. Remember that the Lord knows you.',
          language: 'en',
          draft: true,
        ));
        await launch();
        await walk();
        // a turn on the sky keeps the same blessing in focus
        final f = engine().focus;
        await rotate('landscape');
        expect(engine().focus, f, reason: 'the same blessing in focus after the turn');
        await firstRun();
        await launch();
        await walk();
        await rotate('portrait');
        debugPrint('SEEN ${seen.length} screens');
        next(2);
      case 2:
      case 3:
        store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: await defaultAudioDir());
        prefix = phase == 2 ? 'es/' : 'ax/';
        await act('orient portrait');
        await launch();
        // launch() reads the app's language, as main() does
        if (phase == 2) expect(Strings.language, UiLanguage.spanish, reason: 'the script sets Spanish for phase 2');
        await walk(full: false);
        await rotate('landscape');
        await walk(full: false);
        await rotate('portrait');
        next(phase + 1);
    }
    await store.close();
  });
}
