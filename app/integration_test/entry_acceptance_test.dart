// Entering a past blessing, on the simulator. Run by tool/entry_acceptance.sh, which first runs the
// app as it was at commit 51932fd to write its store (the five samples), then installs this build
// over it (built with this test as its target) and launches it once per phase, terminating the app
// between phases so each is a real new launch. The script answers ACTs through files in the app's
// tmp/entryacts (shot, pbcopy, allowpaste, appdismiss, web) and reads Documents/entry_test_status
// (`next <n>`, `done`, `failed …`).
//
//   1. The upgrade: every blessing still a full date and "as spoken". The recording start offers
//      "Enter a past blessing"; the entry page; a multi-paragraph blessing put in from the
//      simulator's clipboard (Paste, and the system's Allow Paste), a line typed after it; then no
//      date: the app is killed with the words on the page.
//   2. A new launch: the words survived (exactly), one to review. Year only, 1998: the count line
//      and ruler reach 1998 (before and after shots); the reading page "1998" and the entered line;
//      the share text, the PDF and its name say 1998; a link made against the website running
//      here, opened in Chrome: "1998" and the entered line. A month-and-year entry and a full-date
//      entry, each on home, list and reading page. Edit changes the year-only one to a full date.
//   3. A family member's sky: an entry there lights her ring only.
//   4. The main path in Spanish (the script sets the app's language).
//   5. The main path at the largest text size (the script sets it).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/review/date_sheet.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/share/share_sheet.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

/// What the script puts on the simulator's clipboard: three paragraphs, the second two lines.
const pastedWords = 'Daniel James Carter, by the authority of the holy Melchizedek Priesthood which I hold, I place my hands upon your head.\n'
    '\n'
    'I bless you with a strong body and a clear mind, and with friends who will stand by you.\n'
    'I bless you that you will love to learn, all your life.\n'
    '\n'
    'And I seal these blessings upon you, in the name of Jesus Christ, amen.';
const typedAfter = '\n\nWritten down by Mom the same evening.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('entering a past blessing', timeout: const Timeout(Duration(minutes: 20)), (t) async {
    Strings.use(UiLanguage.forLocales(PlatformDispatcher.instance.locales));
    final docs = (await getApplicationDocumentsDirectory()).path;
    final acts = Directory(p.join(Directory.systemTemp.path, 'entryacts'))..createSync(recursive: true);
    final status = File('$docs/entry_test_status');
    final marker = File('$docs/entry_test_phase');
    final logFile = File('$docs/entry_test_log.txt');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    var actN = (state['acts'] as int?) ?? 0;
    final ids = (state['ids'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final prefix = switch (phase) { 4 => 'es/', 5 => 'ax/', _ => '' };
    var shots = (state['shots'] as int?) ?? 0;

    void log(String s) {
      debugPrint(s);
      logFile.writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
    }

    void save(int next) {
      marker.writeAsStringSync(jsonEncode({'phase': next, 'acts': actN, 'ids': ids, 'shots': shots}), flush: true);
      status.writeAsStringSync('next $next', flush: true);
      log('NEXT $next');
    }

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

    Future<String> act(String what, {int seconds = 120}) async {
      final n = ++actN;
      final answer = File(p.join(acts.path, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      File(p.join(acts.path, 'ask_$n.tmp'))
        ..writeAsStringSync(what, flush: true)
        ..renameSync(p.join(acts.path, 'ask_$n'));
      log('ACT $n ${what.length > 120 ? '${what.substring(0, 120)}…' : what}');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await t.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      log('ACT $n -> ${s.length > 300 ? '${s.substring(0, 300)}…' : s}');
      return s;
    }

    Future<void> shot(String name) async {
      await wait(700);
      shots++;
      await act('shot $prefix${shots.toString().padLeft(2, '0')}-$name');
      await wait(200);
    }

    final store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: await defaultAudioDir());
    // the ruler's value is read from the semantics tree, which is only built while semantics is on
    final semantics = t.ensureSemantics();
    bool stage(String name) => t.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    SkyEngine engine() => t.widget<SkyWidget>(find.byKey(const Key('sky'))).engine;
    String? text(String key) {
      final f = find.byKey(Key(key));
      return f.evaluate().isEmpty ? null : t.widget<Text>(f.first).data;
    }

    bool shown(String key) => find.byKey(Key(key)).hitTestable().evaluate().isNotEmpty;
    String rulerValue() => t.getSemantics(find.descendant(of: find.byKey(const Key('ruler')), matching: find.byType(Semantics)).first).getSemanticsData().value;

    Future<void> launch() async {
      final lock = unlockedLock();
      await t.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      final ready = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && ready.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(ready, findsOneWidget, reason: 'the app never got to its first screen');
      await wait(2200);
    }

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

    Finder words() => find.descendant(of: find.byKey(const Key('review-words')), matching: find.byType(EditableText));
    String wordsOnPage() => t.widget<EditableText>(words()).controller.text;

    /// The recording start, then its "Enter a past blessing": the entry page.
    Future<Blessing> startEntry({bool shots = false}) async {
      expect(stage('home'), isTrue);
      await tap('new', settle: 1800);
      expect(stage('record'), isTrue);
      await until(() => shown('enter-past'), what: 'Enter a past blessing on the recording start');
      if (shots) await shot('recording-start');
      await tap('enter-past', settle: 1800);
      expect(stage('review'), isTrue, reason: 'the entry page opens');
      expect(text('review-given'), Strings.whenGiven);
      expect(find.byKey(const Key('listen')), findsNothing, reason: 'no listen bar');
      expect(find.byKey(const Key('review-polish')), findsNothing, reason: 'polish never runs on entered words');
      final draft = (await store.list()).where((b) => b.entered && b.draft).toList()..sort((a, b) => b.created.compareTo(a.created));
      expect(draft, isNotEmpty, reason: 'the entry is kept from the moment it opens');
      return draft.first;
    }

    Future<void> type(String s) async {
      await tap('review-words', settle: 500);
      await t.enterText(words(), s);
      await wait(1200);
    }

    DateSheetState sheet() => t.state<DateSheetState>(find.byType(DateSheet));

    /// Turns [wheel] until [now] reads [target]: a person's drags, a row at a time from where it is.
    Future<void> turn(String wheel, int Function() now, int target) async {
      for (var i = 0; i < 8 && now() != target; i++) {
        final extent = t.widget<CupertinoPicker>(find.byKey(Key(wheel))).itemExtent;
        final rows = now() - target;
        final step = rows.clamp(-12, 12);
        // slowly enough not to fling (under 50 px/s), so it stops where the finger does
        await t.timedDrag(find.byKey(Key(wheel)), Offset(0, step * extent), Duration(milliseconds: (step.abs() * extent * 25).round()));
        await wait(900);
      }
      expect(now(), target, reason: 'the $wheel wheel turned to $target');
    }

    /// Given: the date sheet, the kind, the wheels, Done.
    Future<void> setDate(DatePrecision kind, int year, {int month = 1, int day = 1, String? shotName}) async {
      await tap('review-given-row', settle: 900);
      expect(find.byKey(const Key('date-sheet')), findsOneWidget);
      await tap('precision-${kind.code}', settle: 600);
      await turn('wheel-year', () => sheet().choice.year, year);
      if (kind != DatePrecision.year) await turn('wheel-month', () => sheet().choice.month, month);
      if (kind == DatePrecision.day) await turn('wheel-day', () => sheet().choice.day, day);
      expect(sheet().choice, (precision: kind, year: year, month: kind == DatePrecision.year ? 1 : month, day: kind == DatePrecision.day ? day : 1));
      if (shotName != null) await shot(shotName);
      await tap('date-done', settle: 1500);
    }

    /// Done on the entry page; back on home, the new light in focus.
    Future<Blessing> finish(String id) async {
      await tap('review-done', settle: 3200);
      expect(stage('home'), isTrue, reason: 'Done goes home');
      final b = (await store.get(id))!;
      expect(b.draft, isFalse);
      final bs = engine().blessings;
      expect(bs[engine().focus].id, id, reason: 'the sky turns to the new light');
      return b;
    }

    /// The reading page scrolled down to [f], as a person scrolls to read on.
    Future<void> scrollRead(Finder f) async {
      if (f.evaluate().isNotEmpty && f.hitTestable().evaluate().isNotEmpty) return;
      final sc = find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(f, 250, scrollable: sc, maxScrolls: 80);
      await wait(500);
    }

    Future<void> checkRead(Blessing b, {String? shotName}) async {
      await tap('read', settle: 1800);
      expect(stage('read'), isTrue);
      expect(text('read-date'), b.longDate);
      await scrollRead(find.byKey(const Key('read-entered')));
      expect(find.byKey(const Key('read-entered')), findsOneWidget, reason: 'the entered line');
      expect(find.descendant(of: find.byKey(const Key('read-entered')), matching: find.text(Strings.enteredNote)), findsOneWidget);
      expect(find.byKey(const Key('read-as-spoken')), findsNothing);
      if (shotName != null) await shot(shotName);
    }

    Future<void> checkList(Blessing b, String rowDate, {String? shotName}) async {
      await tap('list', settle: 1500);
      expect(stage('list'), isTrue);
      final row = find.byKey(Key('row-${b.id}'));
      final listScroll = find.byKey(const Key('list-scroll'));
      if (row.evaluate().isEmpty || row.hitTestable().evaluate().isEmpty) {
        await t.scrollUntilVisible(row, 200, scrollable: find.descendant(of: listScroll, matching: find.byType(Scrollable)).first);
        await wait(500);
      }
      expect(find.descendant(of: row, matching: find.text(rowDate)), findsOneWidget, reason: 'the list row reads $rowDate');
      if (shotName != null) await shot(shotName);
      await tap('list', settle: 1500);
    }

    Future<void> backHome() async {
      if (stage('read')) await tap('read-back', settle: 1500);
      expect(stage('home'), isTrue);
    }

    Future<void> run() async {
      switch (phase) {
        case 1:
          // ---- the upgrade from 51932fd ----
          final db = sqlite3.open(await SqliteBlessingStore.defaultPath());
          final version = db.userVersion;
          db.close();
          final before = await store.list();
          log('UPGRADE: store version $version, ${before.length} blessings');
          expect(before, hasLength(5));
          expect(version, SqliteBlessingStore.schemaVersion);
          for (final b in before) {
            expect(b.precision, DatePrecision.day, reason: '${b.id} is still a full date');
            expect(b.entered, isFalse, reason: '${b.id} is still as spoken');
          }
          await launch();
          expect(text('count'), Strings.countLine(5, before.map((b) => b.local).reduce((a, b) => a.isBefore(b) ? a : b)));
          await shot('upgrade-home');
          // one with words: the surgery sample
          engine().setFocus(engine().blessings.indexWhere((x) => x.id == 'surgery'), instant: true);
          await wait(1500);
          await tap('read', settle: 1800);
          expect(stage('read'), isTrue);
          await scrollRead(find.byKey(const Key('read-as-spoken')));
          expect(find.byKey(const Key('read-as-spoken')), findsOneWidget, reason: 'an old blessing still reads "as spoken"');
          expect(find.byKey(const Key('read-entered')), findsNothing);
          final focused = engine().blessings[engine().focus];
          expect(text('read-date'), focused.longDate, reason: 'the date, still on the page');
          expect(text('read-date'), contains(', 20'), reason: 'a full date');
          await shot('upgrade-read');
          await backHome();

          // ---- the entry page; Paste from the simulator's clipboard ----
          final b = await startEntry(shots: true);
          ids['year'] = b.id;
          await shot('entry-page');
          expect(await act('pbcopy ${base64.encode(utf8.encode(pastedWords))}'), 'ok');
          await tap('review-paste', settle: 300);
          final allowed = await act('allowpaste', seconds: 60);
          log('PASTE: $allowed');
          await until(() => wordsOnPage().isNotEmpty, seconds: 20, what: 'the pasted words');
          await wait(1200);
          expect(wordsOnPage(), pastedWords, reason: 'pasted exactly, the paragraphs kept');
          await shot('pasted');
          // a line typed after it, and no date
          await type(pastedWords + typedAfter);
          await wait(800);
          final kept = (await store.get(b.id))!;
          expect(kept.rawText, pastedWords + typedAfter, reason: 'on disk before the kill');
          expect(kept.placed, isFalse);
          // Done stays dim without a date
          expect(t.getSemantics(find.byKey(const Key('review-done'))).getSemanticsData().flagsCollection.isEnabled.toString(), contains('isFalse'));
          await shot('typed-no-date');
          save(2);
          // the script kills the app here, on the entry page with the words typed
          await wait(120000);
          return;

        case 2:
          // ---- after the kill: the words survived ----
          final id = (ids['year'] as String?) ?? ((await store.list()).firstWhere((b) => b.entered && b.draft && !b.placed)).id;
          ids['year'] = id;
          final survived = (await store.get(id))!;
          log('SURVIVED: ${survived.rawText.length} characters, draft ${survived.draft}, placed ${survived.placed}');
          expect(survived.rawText, pastedWords + typedAfter, reason: 'nothing typed is lost');
          await launch();
          expect(text('to-review-text'), isNotNull, reason: 'one to review');
          final countBefore = text('count')!;
          final rulerBefore = rulerValue();
          log('BEFORE: count "$countBefore", ruler "$rulerBefore"');
          await shot('before-1998');
          await tap('to-review', settle: 1800);
          expect(stage('review'), isTrue);
          expect(wordsOnPage(), pastedWords + typedAfter);
          await shot('reopened');
          // year only, 1998
          await setDate(DatePrecision.year, 1998, shotName: 'date-year-only');
          expect(text('review-given'), '1998');
          await shot('given-1998');
          final b = await finish(id);
          expect(b.precision, DatePrecision.year);
          expect(b.local, DateTime.utc(1998, 7, 2, 12));
          expect(b.paragraphs, hasLength(5), reason: 'each line break a paragraph');
          await wait(1500);
          expect(text('count'), Strings.countLine(6, b.local, yearOnly: true));
          expect(text('count'), endsWith('since 1998'));
          expect(text('cap-date'), '1998');
          expect(rulerValue(), '1998. ${b.shownTitle}');
          expect(engine().blessings.first.id, id, reason: 'the ring starts at 1998');
          log('AFTER: count "${text('count')}", ruler "${rulerValue()}"');
          await shot('after-1998');
          await checkRead(b, shotName: 'read-1998');
          // on the reading page only: the review page's words are still built behind it
          final learn = find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.textContaining('I bless you that you will love to learn'));
          await scrollRead(learn);
          expect(learn, findsOneWidget);
          await backHome();
          await checkList(b, '1998', shotName: 'list-1998');

          // ---- the share text, the PDF and its name ----
          await tap('read', settle: 1800);
          await tap('read-share', settle: 1200);
          await tap('share-text', settle: 2500);
          var items = await NativeShareApi.debugItems();
          log('TEXT ITEMS ${jsonEncode(items)}');
          expect(jsonEncode(items), contains('"kind":"text"')); // the native side names only the kind of a text item
          expect(shareText(b, Strings.wordsFor(Strings.language)).split('\n')[1], '1998');
          for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
            await act('appdismiss $i');
            await wait(1500);
          }
          await tap('read-share', settle: 1200);
          await tap('share-pdf', settle: 3500);
          items = await NativeShareApi.debugItems();
          log('PDF ITEMS ${jsonEncode(items)}');
          expect(jsonEncode(items), contains('1998.pdf'));
          expect(sharePdf(b, Strings.wordsFor(Strings.language))['date'], '1998');
          await shot('pdf-sheet');
          for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
            await act('appdismiss $i');
            await wait(1500);
          }

          // ---- a link, against the website running here, in Chrome ----
          await tap('read-share', settle: 1200);
          await until(() => shown('share-choose'), what: 'the share sheet');
          await tap('share-send', settle: 600);
          await until(() => shown('share-made'), seconds: 40, what: 'the link to be made');
          final url = t.state<ShareSheetState>(find.byType(ShareSheet)).debugUrl!;
          expect(url, startsWith('http://127.0.0.1'), reason: 'never the live service');
          final page = jsonDecode(await act('web $url ${prefix}web-1998', seconds: 90)) as Map;
          expect(page['state'], 'open');
          expect(page['given'], '1998');
          expect(page['notes'], contains('Entered from a written copy, not recorded.'));
          expect((page['words'] as List).length, 5);
          // the sheet closed by a tap above it
          await t.tapAt(const Offset(200, 120));
          await wait(1500);
          await backHome();
          // the owner's cut (2026-11-18): the walk ends here unless ENTRY_FULL is set
          if (!const bool.fromEnvironment('ENTRY_FULL')) {
            marker.writeAsStringSync(jsonEncode({'phase': 99, 'acts': actN, 'ids': ids, 'shots': shots}), flush: true);
            status.writeAsStringSync('done', flush: true);
            log('ALL DONE (steps 2 to 5)');
            return;
          }

          // ---- month and year; a full date ----
          final m = await startEntry();
          await type('Sarah, I bless you with comfort in this season of change.\nYour Father in Heaven knows you.');
          await setDate(DatePrecision.month, 2003, month: 8, shotName: 'date-month');
          final mb = await finish(m.id);
          expect(text('cap-date'), 'August 2003');
          await shot('home-month');
          await checkList(mb, Strings.givenShort(mb.local, DatePrecision.month).split(' ').first, shotName: 'list-month');
          await checkRead(mb, shotName: 'read-month');
          expect(text('read-date'), 'August 2003');
          await backHome();
          final d = await startEntry();
          await type('Michael, I bless you as you leave to serve.\nGo with courage.');
          await setDate(DatePrecision.day, 2010, month: 3, day: 14, shotName: 'date-full');
          final db2 = await finish(d.id);
          expect(text('cap-date'), 'Sunday, March 14, 2010');
          await shot('home-full');
          await checkList(db2, Strings.dayMonth(db2.local), shotName: 'list-full');
          await checkRead(db2, shotName: 'read-full');
          await backHome();
          ids['month'] = m.id;
          ids['day'] = d.id;

          // ---- Edit: the year-only one to a full date ----
          final at = engine().blessings.indexWhere((x) => x.id == id);
          engine().setFocus(at, instant: true);
          await wait(1500);
          await tap('read', settle: 1800);
          await tap('read-edit', settle: 1800);
          expect(stage('review'), isTrue);
          await setDate(DatePrecision.day, 1998, month: 5, day: 10, shotName: 'edit-date');
          expect(text('review-given'), 'Sunday, May 10, 1998');
          await tap('review-done', settle: 2500);
          expect(stage('read'), isTrue, reason: 'Done after Edit goes back to the reading page');
          expect(text('read-date'), 'Sunday, May 10, 1998');
          final edited = (await store.get(id))!;
          expect(edited.precision, DatePrecision.day);
          await shot('edited-full-date');
          await backHome();
          expect(text('count'), endsWith('since May 1998'));
          save(3);
          return;

        case 3:
          // ---- a family member's sky ----
          final mine = (await store.list()).where((b) => b.personId.isEmpty && !b.draft).length;
          final emma = Person(id: 'emma-entry', name: 'Emma', born: Day(2008, 8, 3));
          if (!(await store.people()).any((x) => x.id == emma.id)) await store.addPerson(emma);
          await launch();
          await tap('sky-switch', settle: 700);
          await tap('pull-down-${SkyMenu.person(emma.id)}', settle: 2200);
          expect(text('sky-switch-label'), Strings.forPerson('Emma'));
          await shot('emma-before');
          final e = await startEntry();
          expect(e.personId, emma.id, reason: 'entered for the person whose sky it is');
          await type('Emma, I bless you on your baptism day.\nYou are His.');
          await setDate(DatePrecision.year, 2016);
          final eb = await finish(e.id);
          expect(eb.personId, emma.id);
          expect(text('sky-switch-label'), Strings.forPerson('Emma'));
          expect(text('count'), Strings.countLine(1, eb.local, yearOnly: true));
          expect(engine().blessings.map((x) => x.id), [e.id]);
          await shot('emma-after');
          await tap('sky-switch', settle: 700);
          await tap('pull-down-${SkyMenu.me}', settle: 2200);
          expect(engine().blessings.any((x) => x.id == e.id), isFalse, reason: 'not on my ring');
          expect(engine().blessings.length, mine);
          await shot('mine-unchanged');
          save(4);
          return;

        case 4:
        case 5:
          // ---- the main path in Spanish; at the largest text ----
          log('LOCALES ${PlatformDispatcher.instance.locales} -> ${Strings.language.name}, text ${PlatformDispatcher.instance.textScaleFactor}');
          if (phase == 4) expect(Strings.language, UiLanguage.spanish);
          await launch();
          await shot('home');
          final b = await startEntry(shots: true);
          await shot('entry-page');
          await type(phase == 4 ? 'Lucía, te bendigo con paz.\nQue sientas Su amor.' : 'Ruth, I bless you with peace.\nFeel His love.');
          await setDate(DatePrecision.year, phase == 4 ? 1990 : 1985, shotName: 'date-sheet');
          await shot('given');
          final fb = await finish(b.id);
          expect(text('count'), endsWith(phase == 4 ? 'desde 1990' : 'since 1985'));
          await shot('after');
          await checkRead(fb, shotName: 'read');
          expect(text('read-date'), phase == 4 ? '1990' : '1985');
          await backHome();
          if (phase == 4) {
            save(5);
          } else {
            marker.writeAsStringSync(jsonEncode({'phase': 99, 'acts': actN, 'ids': ids, 'shots': shots}), flush: true);
            status.writeAsStringSync('done', flush: true);
            log('ALL DONE');
          }
          return;
      }
    }

    log('ENTRY PHASE $phase (${Strings.language.name})');
    try {
      await run();
    } catch (err, st) {
      log('FAILED $err\n${st.toString().split('\n').take(12).join('\n')}');
      status.writeAsStringSync('failed ${'$err'.split('\n').take(3).join(' ')}', flush: true);
      rethrow;
    } finally {
      semantics.dispose();
    }
  });
}
