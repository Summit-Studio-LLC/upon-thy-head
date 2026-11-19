// Family members on the simulator, from an upgrade to the lock. Run by tool/family_acceptance.sh,
// which first runs the app as it was at commit 58341dc to write the store (five blessings and a
// draft), then installs this build over it and runs this test once per phase with
// --keep-app-running, terminating the app between phases so each is a real new launch.
//
//   1. The upgrade: everything still "For me", nothing lost or doubled; the menu offers For me and
//      Add. Emma is added with a birth date: her empty ring. A blessing is recorded for her through
//      the real recording (SPEECH_AUDIO), reviewed and finished: its light on her ring and not on
//      mine; both counts right. Switching back and forth; James added; a finished blessing moved
//      from For me to James and back. Locked on Emma's sky (the script sends the app away for more
//      than a minute): no name, no count, the menu does not open; unlocked (Face ID, from the
//      script): back on her sky. Emma renamed, her birth date changed, then removed: the warning
//      names her one blessing; Keep removes nothing; Remove removes her and it, nothing of mine.
//      Ends on James's sky.
//   2. A new launch opens on James's sky, the one last showing.
//   3. The first run's welcome shows the new line.
//   4. The main path in Spanish (the script sets the app's language).
//   5. The main path at the largest text size (the script sets it).
//
// The script answers `ACT away <s>` (the app sent to the background for <s> seconds) and
// `ACT face match`. Screenshots (SIMSHOT): ../design/sim/family/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/people/sky_switch.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('family members: upgrade, add, record, switch, move, lock, change, remove', timeout: const Timeout(Duration(minutes: 12)), (t) async {
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

    var prefix = '';
    Future<void> shot(String name) async {
      await wait(400);
      debugPrint('SIMSHOT family/$prefix$name');
      await wait(1500);
    }

    final docs = (await getApplicationDocumentsDirectory()).path;
    final marker = File('$docs/family_test_phase');
    final phase = marker.existsSync() ? (jsonDecode(marker.readAsStringSync()) as Map)['phase'] as int : 1;
    void next(int n) {
      marker.writeAsStringSync(jsonEncode({'phase': n}));
      debugPrint('NEXT $n');
    }

    debugPrint('FAMILY PHASE $phase');

    expect(audioDir, isNotEmpty, reason: 'build and drive with --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    final store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: await defaultAudioDir());
    bool stage(String name) => t.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    SkyEngine engine() => t.widget<SkyWidget>(find.byKey(const Key('sky'))).engine;
    String? text(Finder f) => f.evaluate().isEmpty ? null : t.widget<Text>(f).data;
    String? capsule() => text(find.byKey(const Key('sky-switch-label')));
    String? count() => text(find.byKey(const Key('count')));
    String? badge() => text(find.byKey(const Key('to-review-text')));
    RecordSession session() => t.widget<RecordLayer>(find.byType(RecordLayer)).session;

    Future<void> launch({bool firstRun = false, BlessingStore? on}) async {
      // the language as main() takes it from the phone (this test starts the app below main())
      Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
      debugPrint('LOCALES ${binding.platformDispatcher.locales} -> ${Strings.language.name}');
      final lock = unlockedLock();
      HomeScreen.debugSkipFirstRun = !firstRun;
      await t.pumpWidget(UponThyHeadApp(store: on ?? store, stats: false, demo: false, lock: lock));
      final ready = firstRun ? find.byKey(const Key('welcome-family')) : find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && ready.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(ready, findsOneWidget, reason: 'the app never got to its first screen');
      await wait(1800);
    }

    Future<void> tap(String key, {int settle = 1200}) async {
      final f = find.byKey(Key(key));
      await until(() => f.evaluate().isNotEmpty, what: key);
      // below the fold (the largest text sizes): scrolled to, as a person would
      final scroll = find.ancestor(of: f, matching: find.byType(Scrollable));
      if (f.hitTestable().evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
        await t.scrollUntilVisible(f, 150, scrollable: scroll.first);
        await wait(400);
      }
      await until(() => f.hitTestable().evaluate().isNotEmpty, what: key);
      await t.tap(f.hitTestable().first);
      await wait(settle);
    }

    Future<void> openMenu() async {
      await tap('sky-switch', settle: 700);
      expect(find.byKey(Key('pull-down-${SkyMenu.me}')), findsOneWidget, reason: 'the menu did not open');
    }

    Future<void> showSky(String ring) async {
      await openMenu();
      await tap('pull-down-${ring.isEmpty ? SkyMenu.me : SkyMenu.person(ring)}', settle: 2200);
      expect(stage('home'), isTrue);
    }

    /// Rows down the birth date's year wheel (the last column), about a year a row.
    Future<void> turnYears(int rows) async {
      await until(() => find.byKey(const Key('born-picker')).hitTestable().evaluate().isNotEmpty, what: 'the date wheel');
      final r = t.getRect(find.byKey(const Key('born-picker')));
      await t.dragFrom(Offset(r.right - r.width / 6, r.center.dy), Offset(0, rows * 32.0));
      await wait(1400);
    }

    Future<Person> add(String name, {int years = 0}) async {
      expect(stage('person'), isTrue);
      // into the field as a person does: a tap on it, then the keys
      await tap('person-name', settle: 900);
      await t.enterText(find.byKey(const Key('person-name')), name);
      await wait(400);
      if (years > 0) {
        await tap('person-born', settle: 900);
        await turnYears(years);
        await tap('born-done', settle: 900);
      }
      final typed = t.widget<CupertinoTextField>(find.byKey(const Key('person-name'))).controller!.text;
      debugPrint('family test: the name field holds "$typed" before Add');
      expect(typed, name, reason: 'what was typed is in the field');
      await tap('person-save', settle: 2400);
      final people = await store.people();
      if (!people.any((p) => p.name == name)) {
        await shot('debug-add-$name');
        fail('Add did not add $name; the store has ${[for (final p in people) p.name]}; stage person: ${stage('person')}');
      }
      final p = people.lastWhere((p) => p.name == name);
      expect(stage('home'), isTrue, reason: 'adding opens their sky');
      expect(capsule(), Strings.forPerson(name));
      return p;
    }

    Future<List<Blessing>> on(String ring) async =>
        Family(await store.people(), await store.list(ownership: Ownership.forMe)).on(ring);

    /// The main path, once per language or size: menu, add with a birth date, the empty ring, a
    /// recording begun for them (closed before it starts), manage, change, remove.
    Future<void> mainPath(String name) async {
      await openMenu();
      await shot('01-menu');
      await tap('pull-down-${SkyMenu.add}');
      await shot('02-adding');
      final p = await add(name, years: 12);
      expect(text(find.byKey(const Key('first-run'))), Strings.emptyRing(name));
      await shot('03-empty-ring');
      await tap('new', settle: 2600);
      expect(stage('record'), isTrue);
      expect(text(find.byKey(const Key('rec-whose'))), Strings.forPerson(name));
      await shot('04-record-for');
      await tap('rec-x', settle: 2200);
      expect(stage('home'), isTrue);
      await openMenu();
      await shot('05-menu-with-them');
      await tap('pull-down-${SkyMenu.manage}');
      expect(stage('family'), isTrue);
      await shot('06-manage');
      await tap('family-row-${p.id}');
      expect(stage('person'), isTrue);
      await shot('07-change');
      await t.scrollUntilVisible(find.byKey(const Key('person-remove')), 120, scrollable: find.descendant(of: find.byKey(const Key('stage-person')), matching: find.byType(Scrollable)).first);
      await tap('person-remove');
      expect(find.text(Strings.removeBody(name, 0)), findsOneWidget);
      await shot('08-remove');
      await tap('remove-confirm', settle: 2000);
      expect((await store.people()).any((q) => q.id == p.id), isFalse);
      expect(stage('family'), isTrue);
      await tap('family-back', settle: 1600);
    }

    switch (phase) {
      // ------------------------------------------------------------------------------------------
      case 1:
        final before = await store.list();
        expect(before, hasLength(6), reason: 'the store as the app at 58341dc left it: five blessings and a draft');
        await launch();
        expect(await store.people(), isEmpty);
        final after = await store.list();
        expect({for (final b in after) b.id}, {for (final b in before) b.id}, reason: 'nothing lost');
        expect(after.length, {for (final b in after) b.id}.length, reason: 'nothing doubled');
        expect(after.every((b) => b.personId.isEmpty), isTrue, reason: 'everything is For me');
        expect(capsule(), Strings.forMe);
        expect(count(), countLine(after));
        expect(badge(), Strings.toReview(1));
        expect(engine().blessings, hasLength(6));
        await shot('01-capsule-for-me');
        await openMenu();
        expect(find.byKey(const Key('pull-down-${SkyMenu.manage}')), findsNothing, reason: 'nothing to manage yet');
        await shot('02-menu-nobody-yet');

        // ---- Emma, with a birth date: her empty ring ----
        await tap('pull-down-${SkyMenu.add}');
        await shot('03-adding');
        final emma = await add('Emma', years: 15);
        expect(emma.born, isNotNull);
        expect(emma.born!.local.isBefore(DateTime.now().subtract(const Duration(days: 365 * 10))), isTrue, reason: '${emma.born}');
        expect(text(find.byKey(const Key('first-run'))), Strings.emptyRing('Emma'));
        expect(engine().blessings, isEmpty);
        expect(badge(), isNull, reason: 'my draft is not hers');
        await shot('04-empty-ring');

        // ---- a blessing for her, by the real recording ----
        await tap('new', settle: 2600);
        expect(stage('record'), isTrue);
        expect(text(find.byKey(const Key('rec-whose'))), 'For Emma');
        await shot('05-record-for-emma');
        await tap('begin', settle: 200);
        expect(session().live, isTrue);
        await until(() => session().elapsed >= 14, seconds: 40, what: '14 seconds of recording');
        final g = await t.startGesture(t.getCenter(find.byKey(const Key('hold'))));
        await wait(1200);
        await g.up();
        await wait(2600);
        expect(stage('after'), isTrue);
        await until(() => session().wordsState != WordsState.writing, seconds: 60, what: 'the words');
        await tap('review-now', settle: 2000);
        expect(stage('review'), isTrue);
        expect(find.byKey(Key('review-person-${emma.id}')), findsOneWidget);
        await shot('06-review-whose');
        await tap('review-done', settle: 1000);
        if (find.byKey(const Key('finish-confirm')).hitTestable().evaluate().isNotEmpty) await tap('finish-confirm', settle: 2500);
        await until(() => stage('home') || stage('read'), what: 'back from review');
        if (stage('read')) await tap('read-back', settle: 2000);
        expect(stage('home'), isTrue);
        final hers = await on(emma.id);
        expect(hers, hasLength(1));
        expect(hers.single.personId, emma.id);
        expect(engine().blessings.map((b) => b.id), [hers.single.id], reason: 'her light is on her ring');
        expect(capsule(), 'For Emma');
        expect(count(), countLine(hers));
        await shot('07-emma-one');

        // ---- back and forth ----
        await showSky('');
        expect(capsule(), Strings.forMe);
        expect(engine().blessings, hasLength(6));
        expect(engine().blessings.any((b) => b.id == hers.single.id), isFalse, reason: 'and not on mine');
        expect(count(), countLine(await on('')));
        await showSky(emma.id);
        expect(engine().blessings, hasLength(1));
        await showSky('');

        // ---- James, and a finished blessing moved to him and back ----
        await openMenu();
        await tap('pull-down-${SkyMenu.add}');
        final james = await add('James');
        await showSky('');
        final moved = (await on('')).firstWhere((b) => !b.draft);
        await tap('list', settle: 1400);
        await t.scrollUntilVisible(find.byKey(Key('row-${moved.id}')), 120, scrollable: find.descendant(of: find.byKey(const Key('stage-list')), matching: find.byType(Scrollable)).first);
        await tap('row-${moved.id}', settle: 2000);
        expect(stage('read'), isTrue);
        await tap('read-edit', settle: 1600);
        expect(stage('review'), isTrue);
        await t.scrollUntilVisible(find.byKey(Key('review-person-${james.id}')), 120, scrollable: find.descendant(of: find.byKey(const Key('stage-review')), matching: find.byType(Scrollable)).first);
        await shot('08-move-choose');
        await tap('review-person-${james.id}', settle: 1800);
        expect((await store.get(moved.id))!.personId, james.id);
        expect(capsule(), 'For James', reason: 'the sky follows it');
        await tap('review-done', settle: 1800);
        if (stage('read')) await tap('read-back', settle: 2000);
        await until(() => stage('home'), what: 'home');
        expect(engine().blessings.map((b) => b.id), [moved.id]);
        expect(await on(''), hasLength(5));
        await shot('09-moved-to-james');
        await tap('list', settle: 1400);
        await tap('row-${moved.id}', settle: 2000);
        await tap('read-edit', settle: 1600);
        await t.scrollUntilVisible(find.byKey(const Key('review-for-me')), 120, scrollable: find.descendant(of: find.byKey(const Key('stage-review')), matching: find.byType(Scrollable)).first);
        await tap('review-for-me', settle: 1800);
        await tap('review-done', settle: 1800);
        if (stage('read')) await tap('read-back', settle: 2000);
        await until(() => stage('home'), what: 'home');
        expect((await store.get(moved.id))!.personId, '');
        expect(capsule(), Strings.forMe);
        expect(await on(''), hasLength(6));
        expect(await on(james.id), isEmpty);

        // ---- locked on Emma's sky ----
        await showSky(emma.id);
        await shot('10-emma-sky');
        debugPrint('ACT away 65');
        await until(() => find.byKey(const Key('locked-head')).evaluate().isNotEmpty, seconds: 120, what: 'the lock');
        await wait(1500);
        expect(find.byType(SkySwitch), findsNothing);
        expect(find.textContaining('Emma'), findsNothing);
        expect(find.textContaining('James'), findsNothing);
        expect(find.text(countLine(hers)), findsNothing);
        expect(text(find.byKey(const Key('locked-line'))), Strings.locked);
        await t.tap(find.byKey(const Key('locked-head')));
        await wait(800);
        expect(find.byKey(Key('pull-down-${SkyMenu.me}')), findsNothing, reason: 'the menu does not open while locked');
        await shot('11-locked');
        debugPrint('ACT face match');
        await until(() => find.byType(SkySwitch).evaluate().isNotEmpty, seconds: 60, what: 'unlocking');
        await wait(2000);
        expect(capsule(), 'For Emma', reason: 'back where they were');
        expect(engine().blessings, hasLength(1));

        // ---- Emma renamed, her birth date changed, then removed ----
        await openMenu();
        await shot('12-menu-two');
        await tap('pull-down-${SkyMenu.manage}');
        expect(stage('family'), isTrue);
        await shot('13-manage');
        await tap('family-row-${emma.id}');
        await tap('person-name', settle: 900);
        await t.enterText(find.byKey(const Key('person-name')), 'Emma Rose');
        await tap('person-born', settle: 900);
        await turnYears(2);
        await tap('born-done', settle: 900);
        await shot('14-change');
        await tap('person-save', settle: 1600);
        final changed = (await store.people()).firstWhere((p) => p.id == emma.id);
        expect(changed.name, 'Emma Rose');
        expect(changed.born, isNot(emma.born));
        expect(stage('family'), isTrue);
        expect(find.descendant(of: find.byKey(const Key('stage-family')), matching: find.text('Emma Rose')), findsOneWidget);
        await tap('family-row-${emma.id}');
        await t.scrollUntilVisible(find.byKey(const Key('person-remove')), 120, scrollable: find.descendant(of: find.byKey(const Key('stage-person')), matching: find.byType(Scrollable)).first);
        await tap('person-remove');
        expect(find.text(Strings.removeBody('Emma Rose', 1)), findsOneWidget, reason: 'the warning names her one blessing');
        await shot('15-remove-warning');
        await tap('remove-keep');
        expect((await store.people()).map((p) => p.id), contains(emma.id));
        expect(await on(emma.id), hasLength(1), reason: 'Keep removes nothing');
        await tap('person-remove');
        await tap('remove-confirm', settle: 2400);
        expect((await store.people()).map((p) => p.id), [james.id]);
        expect(await store.get(hers.single.id), isNull);
        expect(await on(''), hasLength(6), reason: 'nothing of mine');
        expect(stage('family'), isTrue);
        await shot('16-after-remove');
        await tap('family-back', settle: 1600);
        expect(capsule(), Strings.forMe, reason: 'her sky was showing; now mine');
        await showSky(james.id);
        next(2);

      // ------------------------------------------------------------------------------------------
      case 2:
        await launch();
        final james = (await store.people()).single;
        expect(capsule(), Strings.forPerson(james.name), reason: 'reopened on the sky last showing');
        expect(text(find.byKey(const Key('first-run'))), Strings.emptyRing(james.name));
        await shot('17-reopened-on-james');
        await showSky('');
        next(3);

      // ------------------------------------------------------------------------------------------
      case 3:
        // the first run is met only on a phone with nothing kept: shown here on an empty store of
        // its own, the real one left as it is; the first run's state put back after
        final settings = await Settings.open();
        final was = settings.firstRun;
        await settings.setFirstRun(null);
        final empty = SqliteBlessingStore.open('${(await getTemporaryDirectory()).path}/family_first_run.sqlite');
        await launch(firstRun: true, on: empty);
        expect(text(find.byKey(const Key('welcome-family'))), Strings.welcomeFamily);
        await shot('18-welcome');
        await t.pumpWidget(const SizedBox());
        await wait(500);
        await empty.close();
        await (await Settings.open()).setFirstRun(was);
        next(4);

      // ------------------------------------------------------------------------------------------
      case 4:
        await launch();
        expect(Strings.language, UiLanguage.spanish, reason: 'the script sets the app to Spanish for this phase');
        expect(capsule(), Strings.forMe);
        expect(capsule(), 'Para mí');
        prefix = 'es/';
        await shot('00-capsule');
        await mainPath('Lucía');
        next(5);

      // ------------------------------------------------------------------------------------------
      case 5:
        await launch();
        expect(Strings.language, UiLanguage.english);
        final scale = MediaQuery.textScalerOf(t.element(find.byKey(const Key('sky')))).scale(10) / 10;
        expect(scale, greaterThan(2.5), reason: 'the script sets the largest text size for this phase');
        prefix = 'ax/';
        await shot('00-capsule');
        await mainPath('Grace');
        marker.deleteSync();
        debugPrint('ALL DONE');
    }
    await store.close();
  });
}
