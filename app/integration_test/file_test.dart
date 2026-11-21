// Sharing a blessing as a `.blessing` file and receiving one, replayed on the simulator with real
// iOS delivery. Run by tool/file_acceptance.sh; read that first.
//
// The files reach the app the way iOS delivers them: tapped in the Files app (by tool/alerts, a UI
// test running alongside), or opened with `simctl openurl file://…`, which takes the same path in
// (the scene's URL contexts, BlessingInbox in ios/Runner/Share.swift). The app's handler is never
// called directly.
//
// Several phases start with iOS launching the app for a file, not with `flutter drive`, so this test
// talks to the script through files only. It runs once per phase; each phase is a new launch, and
// the phase is kept in Documents/file_test_phase. In <app data>/tmp/fileacts it leaves `ask_<n>`
// and waits for `act_<n>`:
//   save <path>            copy the file the share sheet holds out of the simulator
//   fixtures <dir>         copy the test's own files (an edited copy, a newer one, rubbish…) out
//   open <name>            simctl openurl the file <name> from the Mac (the app is in front)
//   bg <seconds> <name>    Home, wait, then open the file (the app was in the background)
//   face match             Face ID: the enrolled face
//   shot <name>            a screenshot into ../design/sim/file/
//   film stop              stop the film of step 2
//   textsize <size>        simctl ui content_size
// Progress goes to Documents/file_test_log.txt, the outcome to Documents/file_test_status
// (`next <n>`, `done`, or `failed …`).
//
//   1. Fresh samples. The share sheet's three choices; "Comfort before surgery" as a file: the
//      system sheet holds one file with the right name and type; saved out. Two more saved out.
//      The test's other files written. The three blessings deleted.
//   2. Launched by a tap on the file in Files, locked: nothing until Face ID; the sheet; Keep;
//      the reading page and the store hold exactly what was sent, the light where it was. The same
//      file again; an edited copy (Keep mine, then Replace mine); the polished words and the changes
//      screen; from the background; locked in the background; the 2,491-word one; newer, rubbish,
//      oversize, no title; Not now; at the first accessibility size; during a recording.
//   3. Spanish, launched by a file: the same, more briefly.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

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
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'share_test.dart' show extra, longWords;
import 'support.dart';

const blessingType = 'dev.summitstudio.uponThyHead.blessing';

/// The 2,491-word blessing, with accents, emoji and paragraphs: a word swapped for a word, so the
/// count stays.
String accentedLongWords() => longWords()
    .replaceAll('mother', 'mamá')
    .replaceAll('home', 'hogar')
    .replaceAll('light', 'light✨')
    .replaceAll('Heaven', 'Heaven🙏')
    .replaceFirst('Be patient', 'Sé paciente');

int wordCount(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Everything the reading page and the changes screen show, to compare before and after.
Map<String, Object?> snapshot(Blessing b) => {
      'title': b.title,
      'utc': b.utc.toIso8601String(),
      'offset': b.utcOffset.inMinutes,
      'longDate': b.longDate,
      'from': b.from,
      'recipient': b.recipient,
      'tags': b.tags,
      'language': b.language,
      'rawText': b.rawText,
      'words': b.words,
      'keptChanges': b.keptChanges,
      'changes': [for (final c in b.changes) '${c.toString()} kept=${c.kept}'],
    };

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('file: a .blessing file sent and received through iOS', timeout: const Timeout(Duration(minutes: 25)), (tester) async {
    Strings.use(UiLanguage.forLocales(PlatformDispatcher.instance.locales));
    final w = Strings.wordsFor(Strings.language);
    final lang = Strings.language == UiLanguage.spanish ? 'es' : 'en';

    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path;
    final acts = Directory(p.join(tmp, 'fileacts'))..createSync(recursive: true);
    final shareDir = Directory(p.join(tmp, 'share'));
    final logFile = File('$docs/file_test_log.txt');
    final status = File('$docs/file_test_status');
    final marker = File('$docs/file_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    var shots = (state['shots'] as int?) ?? 0;
    var actN = (state['acts'] as int?) ?? 0;
    final results = (state['results'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final before = (state['before'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

    void log(String s) {
      debugPrint(s);
      logFile.writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
    }

    void result(String key, Object? value) {
      results[key] = value;
      log('RESULT $key = $value');
    }

    void save(int nextPhase) => marker.writeAsStringSync(
        jsonEncode({...state, 'phase': nextPhase, 'shots': shots, 'acts': actN, 'results': results, 'before': before}),
        flush: true);

    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(Future<bool> Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!await ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<String> act(String what, {int seconds = 120, Future<void> Function()? during}) async {
      actN++;
      final n = actN;
      final answer = File(p.join(acts.path, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      File(p.join(acts.path, 'ask_$n.tmp'))
        ..writeAsStringSync(what, flush: true)
        ..renameSync(p.join(acts.path, 'ask_$n'));
      log('ACT $n $what');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await during?.call();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      log('ACT $n -> ${s.length > 200 ? '${s.substring(0, 200)}…' : s}');
      return s;
    }

    Future<void> shot(String name, {int settle = 500}) async {
      await wait(settle);
      shots++;
      await act('shot ${shots.toString().padLeft(2, '0')}-$lang-$name');
      await wait(300);
    }

    late BlessingStore store;
    late SkyEngine e;
    late AppLock lock;
    final audio = await defaultAudioDir();
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    ReceiveSheet sheet() => tester.widget<ReceiveSheet>(find.byType(ReceiveSheet));
    bool sheetOn() => sheet().on;
    bool noticeOn() => tester.widget<ReceiveNotice>(find.byType(ReceiveNotice)).on;
    Finder inSheet(String t) => find.descendant(of: find.byType(ReceiveSheet), matching: find.text(t));
    String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? '';
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;

    Future<void> launch({bool fresh = false, bool locked = false}) async {
      if (fresh) {
        store = await freshSeededStore();
        await store.create(extra('long', 'Para Lucía, al empezar el año ✨', DateTime.utc(2026, 1, 4, 3, 15), from: 'Abuelo Ruiz', recipient: 'Lucía', raw: accentedLongWords()));
        await store.create(extra('minimal', 'A short one', DateTime.utc(2025, 11, 2, 22), raw: 'Be at peace, and know that you are loved.'));
        await store.close();
      }
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      // a launch for a file meets the lock as a person does; the others start unlocked
      lock = locked ? AppLock(api: NativeLockApi()) : unlockedLock();
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await until(() async => lock.ready, what: 'the lock');
    }

    Future<void> unlock() async {
      await until(() async => lock.asking || !lock.locked, what: 'the Face ID question');
      for (var i = 0; i < 4 && lock.locked; i++) {
        await wait(1500);
        await act('face match');
        await wait(2500);
      }
      await until(() async => !lock.locked, what: 'unlocked');
    }

    /// While locked: the sheet, the blessing's title and the notice are nowhere, for [ms].
    Future<void> nothingWhileLocked(String title, {int ms = 2500}) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        expect(lock.locked, isTrue);
        expect(sheetOn(), isFalse, reason: 'the sheet was up while locked');
        expect(sheet().arrival, isNull, reason: 'the arrival was built while locked');
        expect(find.text(title), findsNothing, reason: 'the title was on screen while locked');
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<Blessing> read(String id) async {
      if (stage('read')) {
        await tester.tap(find.byKey(const Key('read-back')));
        await wait(2000);
      }
      final i = e.blessings.indexWhere((b) => b.id == id);
      expect(i, greaterThanOrEqualTo(0), reason: 'no blessing $id');
      e.setFocus(i, instant: true);
      await wait(1200);
      await tester.tap(find.byKey(const Key('read')));
      await wait(2600);
      expect(stage('read'), isTrue);
      return e.blessings[i];
    }

    Future<void> closeSystemSheet() async {
      for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
        await act('appdismiss $i');
        await wait(1500);
      }
      await until(() async => !await NativeShareApi.debugShowing(), what: 'the share sheet to close');
      await wait(800);
    }

    /// Share [id] as a file; check what the system sheet was handed; save it out of the simulator.
    Future<String> sendFile(String id, {bool shots = false}) async {
      final b = await read(id);
      await tester.tap(find.byKey(const Key('read-share')));
      await wait(900);
      // the link first; the file is offered only when no link can be made (this build's service is
      // a closed port on this Mac, tool/file_acceptance.sh, so: no internet)
      expect(find.byKey(const Key('share-send')), findsOneWidget);
      expect(find.byKey(const Key('share-file')), findsNothing, reason: 'the file offered before a link was tried');
      expect(find.byKey(const Key('share-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('share-send')));
      await until(() async => find.byKey(const Key('share-file')).evaluate().isNotEmpty, what: 'no internet, and the file');
      await wait(700);
      expect(find.text(Strings.offLine), findsOneWidget);
      expect(find.text(Strings.sendFile), findsOneWidget);
      if (shots) await shot('share-no-internet-file');
      await tester.tap(find.byKey(const Key('share-file')));
      await until(NativeShareApi.debugShowing, what: 'the system share sheet');
      await wait(1500);
      if (shots) await shot('system-sheet-file', settle: 600);
      final items = await NativeShareApi.debugItems();
      final name = blessingFileName(shareFileName(b, w));
      expect(items, hasLength(1), reason: 'the sheet was handed $items');
      final it = items.single;
      expect(it['kind'], 'file');
      expect(it['name'], name);
      expect((it['type']! as String).toLowerCase(), blessingType.toLowerCase(), reason: 'UTIs compare without case');
      expect(it['json'], isFalse, reason: 'claims to be JSON');
      expect(it['text'], isFalse, reason: 'claims to be text');
      final bytes = File(it['path']! as String).readAsBytesSync();
      expect(bytes, BlessingRecord.of(b).toFileBytes(), reason: 'the bytes handed over are not the record');
      result('$lang.send.$id', 'one file "$name", type ${it['type']}, ${it['bytes']} bytes; not JSON, not text');
      final a = await act('save ${base64.encode(utf8.encode(it['path']! as String))}');
      expect(a, startsWith('ok'), reason: a);
      await closeSystemSheet();
      expect(shareDir.existsSync(), isFalse, reason: 'the file stayed after the sheet closed');
      return name;
    }

    Future<void> leftNothing(String what) async {
      final left = await NativeShareApi.debugReceivedLeft();
      expect(left, isEmpty, reason: '$what left $left');
    }

    /// The file arrives; wait for the sheet (or the notice).
    Future<void> sheetFor(String what, {int seconds = 20}) async {
      await until(() async => sheetOn() || noticeOn(), seconds: seconds, what: 'the sheet for $what');
      await wait(900); // risen fully, so a tap lands on its buttons and not on the sky behind
    }

    Future<void> tapKey(String key, {int after = 1200}) async {
      await tester.tap(find.byKey(Key(key)));
      await wait(after);
    }

    /// The reading page for [id] and the store both hold what [want] says.
    Future<void> same(String id, Map<String, Object?> want, String what) async {
      await until(() async => stage('read'), what: 'the reading page of $id');
      await wait(1500);
      final got = (await store.get(id))!;
      final g = snapshot(got);
      for (final k in want.keys.where((k) => g.containsKey(k))) {
        expect(jsonEncode(g[k]), jsonEncode(want[k]), reason: '$what: $k differs');
      }
      expect(got.ownership, Ownership.forMe);
      expect(got.draft, isFalse);
      expect(got.audio, '');
      // the page shows it
      expect(text('read-title'), got.shownTitle);
      expect(text('read-date'), want['longDate']);
      if ((want['from'] as String).isNotEmpty) expect(text('read-from'), Strings.blessingFrom(want['from'] as String));
      if ((want['recipient'] as String).isNotEmpty) expect(text('read-for'), Strings.forName(want['recipient'] as String));
      if ((want['tags'] as List).isNotEmpty) expect(text('read-tags'), (want['tags'] as List).join('  ·  '));
      final paras = (want['words'] as String).split(RegExp(r'\n\s*\n'));
      expect(find.text(paras.first), findsOneWidget, reason: '$what: the first paragraph is not on the page');
      expect(find.text(paras.last), findsOneWidget, reason: '$what: the last paragraph is not on the page');
      // its light, where it was
      final i = e.blessings.indexWhere((b) => b.id == id);
      expect(e.focus, i, reason: 'the sky is not on it');
      final was = (want['ra'] as num?)?.toDouble();
      if (was != null) {
        final dRa = (e.blessings[i].ra - was).abs();
        final dDec = (e.blessings[i].dec - (want['dec'] as num).toDouble()).abs();
        expect(dRa < 1e-4 && dDec < 1e-9, isTrue, reason: 'the light moved: ra by $dRa, dec by $dDec');
        result('$lang.light.$id', 'ra within ${dRa.toStringAsExponential(1)} rad, dec within ${dDec.toStringAsExponential(1)}; position ${e.blessings.indexWhere((b) => b.id == id) + 1} of ${e.blessings.length} on the ring, as before');
      }
    }

    Future<int> count() async => (await store.list()).length;

    String nameOf(String id) => (before['names']! as Map)[id]! as String;

    Map<String, Object?> record(String id) => before['$id.json']! as Map<String, Object?>;

    /// The test's own files: an edited copy, newer, rubbish, oversize, no title, one for a recording,
    /// and Spanish ones; written here, copied out by the script.
    Future<void> fixtures() async {
      final dir = Directory(p.join(tmp, 'fixtures'))..createSync(recursive: true);
      void write(String name, List<int> bytes) => File(p.join(dir.path, name)).writeAsBytesSync(bytes, flush: true);
      List<int> json(Map<String, Object?> m) => utf8.encode('${const JsonEncoder.withIndent('  ').convert(m)}\n');
      final surgery = record('surgery');
      // an edited word, the changes after it moved with it
      final words = surgery['words']! as String;
      final at = words.indexOf('comfort.');
      final changes = [for (final c in surgery['changes']! as List) (c as Map).cast<String, Object?>()];
      expect(changes.every((c) => (c['at']! as int) + (c['was']! as String).length <= at || (c['at']! as int) > at + 7), isTrue);
      const delta = 'peace'.length - 'comfort'.length;
      final edited = {
        ...surgery,
        'words': words.replaceRange(at, at + 7, 'peace'),
        'changes': [for (final c in changes) {...c, 'at': (c['at']! as int) > at ? (c['at']! as int) + delta : c['at']}],
      };
      expect(readBlessingFile(json(edited)), isA<BlessingReadOk>());
      write('Comfort before surgery (edited).blessing', json(edited));
      write('Newer.blessing', json({...surgery, 'version': blessingFormatVersion + 1, 'id': 'newer', 'voice': 'something new'}));
      write('Rubbish.blessing', [...utf8.encode('This is not a blessing at all.\n'), 0, 255, 254, 1, 2, 3]);
      final big = {...surgery, 'id': 'big', 'words': List.filled(60000, 'Long words. ').join(), 'changes': []};
      final bigBytes = json(big);
      expect(bigBytes.length, greaterThan(blessingFileMaxBytes));
      write('Oversize.blessing', bigBytes);
      write('No title.blessing', json({...surgery, 'id': 'notitle', 'changes': []}..remove('title')));
      write('During a recording.blessing',
          json({...surgery, 'id': 'during', 'title': 'Arrived during a recording', 'words': 'Be still, and know.', 'changes': []}));
      write('Para Sofía.blessing', json({
        ...surgery,
        'id': 'sofia',
        'title': 'Para Sofía, antes del viaje',
        'from': 'Papá',
        'for': 'Sofía',
        'given': '2026-06-14T01:30Z',
        'offset': -360,
        'tags': ['Viaje', 'Familia'],
        'language': 'es',
        'words': 'Sofía, pongo mis manos sobre tu cabeza.\n\nTe bendigo con paz en el camino 🙏 y con amigos que te cuiden.\n\nEn el nombre de Jesucristo, amén.',
        'changes': [],
      }));
      write('Para Sofía (cambiada).blessing', json({
        ...surgery,
        'id': 'sofia',
        'title': 'Para Sofía, antes del viaje',
        'from': 'Papá',
        'for': 'Sofía',
        'given': '2026-06-14T01:30Z',
        'offset': -360,
        'tags': ['Viaje', 'Familia'],
        'language': 'es',
        'words': 'Sofía, pongo mis manos sobre tu cabeza.\n\nTe bendigo con calma en el camino 🙏 y con amigos que te cuiden.\n\nEn el nombre de Jesucristo, amén.',
        'changes': [],
      }));
      final a = await act('fixtures ${base64.encode(utf8.encode(dir.path))}');
      expect(a, startsWith('ok'), reason: a);
      dir.deleteSync(recursive: true);
    }

    Future<void> run() async {
      switch (phase) {
        case 1:
          await launch(fresh: true);
          await wait(2500);
          expect(lang, 'en');
          // ---- 1. sending ----
          for (final id in ['surgery', 'long', 'minimal']) {
            final b = (await store.get(id))!;
            final i = e.blessings.indexWhere((x) => x.id == id);
            before[id] = {...snapshot(b), 'ra': e.blessings[i].ra, 'dec': e.blessings[i].dec};
            before['$id.json'] = BlessingRecord.of(b).toJson();
          }
          expect(wordCount(accentedLongWords()), 2491);
          final name = await sendFile('surgery', shots: true);
          expect(name, 'Comfort before surgery, March 3, 2026.blessing');
          before['names'] = {'surgery': name, 'long': await sendFile('long'), 'minimal': await sendFile('minimal')};
          await fixtures();
          // ---- 2. deleted on this phone ----
          for (final id in ['surgery', 'long', 'minimal']) {
            await store.delete(id);
          }
          result('deleted', 'surgery, long, minimal; ${await count()} left');
          save(2);
          status.writeAsStringSync('next 2', flush: true);
          return;

        case 2:
          // ---- 2 and 3. launched by a tap on the file in Files, while closed; the lock first ----
          await launch(locked: true);
          final s = before['surgery']! as Map<String, Object?>;
          expect(lock.locked, isTrue, reason: 'a launch for a file skipped the lock');
          await nothingWhileLocked(s['title']! as String);
          await shot('locked-nothing-shown');
          await unlock();
          await sheetFor('the tapped file');
          expect(sheet().arrival, isA<ArrivalNew>());
          expect(text('receive-title'), 'Comfort before surgery');
          expect(text('receive-from'), 'A blessing from Dad');
          expect(text('receive-date'), s['longDate']);
          expect(text('receive-body'), 'Keep it with your blessings?');
          expect(inSheet('Keep'), findsOneWidget);
          expect(inSheet('Not now'), findsOneWidget);
          await shot('receive-sheet');
          await tapKey('receive-keep', after: 600);
          await same('surgery', s, 'kept from Files');
          await shot('kept-reading-page', settle: 300);
          await act('film stop');
          await leftNothing('Keep');
          result('closed', 'tapped in Files with the app closed: Face ID first, nothing shown before; Keep; identical');

          // ---- 4. the same file again ----
          final n0 = await count();
          await tester.tap(find.byKey(const Key('read-back')));
          await wait(2000);
          await act('open ${nameOf('surgery')}');
          await sheetFor('the same file');
          expect(sheetOn(), isFalse, reason: 'the same file asked a question');
          expect(noticeOn(), isTrue);
          expect(find.text('You already have this blessing.'), findsOneWidget);
          await until(() async => stage('read'), what: 'its reading page');
          await shot('already-have-same', settle: 900);
          expect(await count(), n0, reason: 'a second copy was saved');
          expect((await store.list()).where((b) => b.id == 'surgery'), hasLength(1));
          await leftNothing('the same file');
          result('same', '"You already have this blessing." over its reading page; still one; nothing left');

          // ---- 5. an edited copy: Keep mine, then Replace mine ----
          await wait(3000);
          await act('open Comfort before surgery (edited).blessing');
          await sheetFor('the edited copy');
          expect(sheet().arrival, isA<ArrivalDifferent>());
          expect(text('receive-title'), 'Comfort before surgery');
          expect(text('receive-body'), 'You already have this blessing, and this copy is different.');
          expect(inSheet('Replace mine'), findsOneWidget);
          expect(inSheet('Keep mine'), findsOneWidget);
          await shot('already-have-different');
          await tapKey('receive-keep-mine');
          expect(sheetOn(), isFalse);
          expect((await store.get('surgery'))!.rawText, s['rawText'], reason: 'Keep mine changed it');
          await act('open Comfort before surgery (edited).blessing');
          await sheetFor('the edited copy, again');
          await tapKey('receive-replace', after: 600);
          final edited = Map<String, Object?>.of(s)
            ..['rawText'] = (s['rawText']! as String).replaceFirst('comfort.', 'peace.')
            ..['words'] = (s['words']! as String).replaceFirst('comfort.', 'peace.')
            ..remove('changes');
          await same('surgery', edited, 'replaced');
          expect(await count(), n0);
          await leftNothing('the edited copy');
          result('different', 'Keep mine: unchanged; Replace mine: the edited word, the changes kept as sent');

          // ---- 6. the polished words, the changes screen, a change restored ----
          final b = (await store.get('surgery'))!;
          expect(b.keptChanges, greaterThan(0));
          expect(text('read-as-spoken'), Strings.polishedFrom(b.keptChanges));
          expect(b.words, b.polishedText);
          expect(find.text(b.words.split('\n\n').first), findsOneWidget, reason: 'the polished words are not shown');
          final c0 = b.changes.first;
          expect(b.words.contains(c0.was), isFalse);
          await Scrollable.ensureVisible(tester.element(find.byKey(const Key('read-review-changes'))), alignment: .5);
          await wait(600);
          await tapKey('read-review-changes', after: 1800);
          expect(stage('changes'), isTrue);
          await shot('received-changes-screen');
          await tapKey('sheet-restore');
          await tapKey('changes-done', after: 1800);
          final r = (await store.get('surgery'))!;
          expect(r.changes.first.kept, isFalse);
          expect(r.words.contains(c0.was), isTrue, reason: 'the spoken word did not come back');
          if (stage('review')) {
            await tapKey('review-done', after: 900);
            if (find.byKey(const Key('finish-confirm')).evaluate().isNotEmpty) await tapKey('finish-confirm', after: 2600);
          }
          result('polished', '${b.keptChanges} changes kept as sent; restoring "${c0.now}" brought back "${c0.was}"');
          if (stage('read')) {
            await tester.tap(find.byKey(const Key('read-back')));
            await wait(2000);
          }

          // ---- 3 and 7. from the background: the 2,491-word one ----
          await act('bg 4 ${nameOf('long')}', seconds: 60);
          expect(lock.locked, isFalse, reason: 'four seconds away locked');
          await sheetFor('the long one');
          expect(sheet().arrival, isA<ArrivalNew>());
          expect(text('receive-from'), 'A blessing from Abuelo Ruiz');
          await tapKey('receive-keep', after: 600);
          final l = before['long']! as Map<String, Object?>;
          await same('long', l, 'the long one');
          expect((await store.get('long'))!.rawText, accentedLongWords());
          expect(wordCount((await store.get('long'))!.rawText), 2491);
          await leftNothing('the long one');
          result('background', 'opened with the app in the background: the sheet; Keep');
          result('long', '2,491 words, accents, emoji and ${l['words'].toString().split('\n\n').length} paragraphs: exact');
          await tester.tap(find.byKey(const Key('read-back')));
          await wait(2000);

          // ---- 3. locked in the background ----
          final m = before['minimal']! as Map<String, Object?>;
          await act('bg 70 ${nameOf('minimal')}', seconds: 150);
          await until(() async => lock.locked, seconds: 10, what: 'the lock after 70 s away');
          await nothingWhileLocked(m['title']! as String);
          await shot('locked-background-nothing');
          await unlock();
          await sheetFor('the short one');
          expect(text('receive-title'), 'A short one');
          expect(text('receive-from'), 'A blessing', reason: 'no giver');
          await tapKey('receive-keep', after: 600);
          await same('minimal', m, 'the short one');
          await leftNothing('the short one');
          result('locked', '70 s in the background, then the file: Face ID first, nothing shown before; Keep');
          await tester.tap(find.byKey(const Key('read-back')));
          await wait(2000);

          // ---- 8. refusals ----
          final n1 = await count();
          await act('open Newer.blessing');
          await sheetFor('the newer file');
          expect(sheet().arrival, isA<ArrivalNewer>());
          expect(text('receive-title'), 'This blessing was made with a newer version of Upon Thy Head. Update the app to open it.');
          expect(inSheet('OK'), findsOneWidget);
          await shot('refused-newer');
          await tapKey('receive-ok');
          await act('open Rubbish.blessing');
          await sheetFor('rubbish');
          expect(sheet().arrival, isA<ArrivalUnreadable>());
          expect(text('receive-title'), 'This file could not be read.');
          await shot('refused-unreadable');
          await tapKey('receive-ok');
          await act('open Oversize.blessing');
          await sheetFor('the oversize file');
          expect(sheet().arrival, isA<ArrivalUnreadable>());
          await tapKey('receive-ok');
          expect(await count(), n1);
          await leftNothing('the refusals');
          result('refused', 'newer: the update line; rubbish and 600 KB: "could not be read"; nothing saved or left');

          // ---- 8 and 11. no title; Not now ----
          await act('open No title.blessing');
          await sheetFor('the file with no title');
          expect(text('receive-title'), Strings.untitled);
          await shot('no-title-sheet');
          await tapKey('receive-not-now');
          expect(sheetOn(), isFalse);
          expect(await store.get('notitle'), isNull, reason: 'Not now saved it');
          expect(await count(), n1);
          await leftNothing('Not now');
          result('notNow', 'no title: "${Strings.untitled}"; Not now: nothing saved, no file left');

          // ---- the first accessibility text size ----
          await act('textsize accessibility-medium');
          await wait(2500);
          await act('open No title.blessing');
          await sheetFor('the sheet at the first accessibility size');
          await wait(800);
          expect(tester.takeException(), isNull, reason: 'overflow at the first accessibility size');
          final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
          for (final k in ['receive-title', 'receive-from', 'receive-date', 'receive-body', 'receive-keep', 'receive-not-now']) {
            final rect = tester.getRect(find.byKey(Key(k)));
            expect(rect.bottom <= screen.height && rect.right <= screen.width, isTrue, reason: '$k off screen: $rect');
          }
          await shot('sheet-first-accessibility-size');
          await tapKey('receive-not-now');
          await act('textsize large');
          await wait(1500);
          result('textSize', 'accessibility-medium: nothing clipped or off screen');

          // ---- 9. during a recording: after Amen ----
          await tapKey('new', after: 2500);
          expect(stage('record'), isTrue);
          await tapKey('begin', after: 2000);
          expect(session().live, isTrue);
          await act('open During a recording.blessing');
          await wait(4000);
          expect(sheetOn(), isFalse, reason: 'the sheet came during the recording');
          expect(session().live, isTrue, reason: 'the recording was interrupted');
          await shot('recording-file-waits');
          // holding the ring in the first ten seconds discards; past them it is Amen
          while (session().elapsed < 12) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(sheetOn(), isFalse, reason: 'the sheet came during the recording');
          final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
          await wait(1100);
          await g.up();
          await wait(2600);
          expect(stage('after'), isTrue);
          for (var i = 0; i < 300 && session().wordsState == WordsState.writing; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(sheetOn(), isFalse, reason: 'the sheet came over the page after Amen');
          await tapKey('save-later', after: 1500);
          await sheetFor('the file that came during the recording');
          expect(stage('home'), isTrue);
          expect(text('receive-title'), 'Arrived during a recording');
          await shot('after-amen-sheet');
          await tapKey('receive-keep', after: 2500);
          expect(await store.get('during'), isNotNull);
          await leftNothing('during a recording');
          // the recording's draft is not part of the samples
          for (final d in (await store.list()).where((b) => b.draft && !['surgery', 'long', 'minimal'].contains(b.id))) {
            await store.delete(d.id);
          }
          result('recording', 'the file waited through the recording and the page after Amen; the sheet on the sky after Save for later');
          save(3);
          status.writeAsStringSync('next 3', flush: true);
          return;

        case 3:
          // ---- 10. Spanish, launched by a file ----
          expect(lang, 'es');
          await launch(locked: true);
          expect(lock.locked, isTrue);
          await nothingWhileLocked('Para Sofía, antes del viaje');
          await unlock();
          await sheetFor('el archivo');
          expect(text('receive-title'), 'Para Sofía, antes del viaje');
          expect(text('receive-from'), Strings.blessingFrom('Papá'));
          expect(text('receive-body'), '¿Guardarla con tus bendiciones?');
          expect(inSheet('Guardar'), findsOneWidget);
          expect(inSheet('Ahora no'), findsOneWidget);
          await shot('receive-sheet');
          await tapKey('receive-keep', after: 600);
          await until(() async => stage('read'), what: 'la página');
          await wait(1500);
          final sofia = (await store.get('sofia'))!;
          expect(sofia.rawText, contains('🙏'));
          expect(text('read-title'), 'Para Sofía, antes del viaje');
          await leftNothing('Guardar');
          await sendFile('sofia', shots: true);
          await act('open Para Sofía.blessing');
          await sheetFor('el mismo archivo');
          expect(find.text('Ya tienes esta bendición.'), findsOneWidget);
          await shot('already-have-same', settle: 900);
          await wait(3000);
          await act('open Para Sofía (cambiada).blessing');
          await sheetFor('la copia cambiada');
          expect(text('receive-body'), 'Ya tienes esta bendición, y esta copia es diferente.');
          expect(inSheet('Reemplazar la mía'), findsOneWidget);
          expect(inSheet('Conservar la mía'), findsOneWidget);
          await shot('already-have-different');
          await tapKey('receive-replace', after: 2500);
          expect((await store.get('sofia'))!.rawText, contains('calma'));
          await act('open Newer.blessing');
          await sheetFor('la versión más nueva');
          expect(text('receive-title'), 'Esta bendición se hizo con una versión más reciente de Upon Thy Head. Actualiza la app para abrirla.');
          await shot('refused-newer');
          await tapKey('receive-ok');
          await act('open Rubbish.blessing');
          await sheetFor('basura');
          expect(text('receive-title'), 'No se pudo leer este archivo.');
          await shot('refused-unreadable');
          await tapKey('receive-ok');
          final n = await count();
          await act('open No title.blessing');
          await sheetFor('sin título');
          expect(text('receive-title'), Strings.untitled);
          await tapKey('receive-not-now');
          expect(await count(), n);
          await leftNothing('Ahora no');
          result('spanish', 'launched by a file, Face ID first; Guardar; ya la tienes; diferente, Reemplazar la mía; más nueva; no se pudo leer; Ahora no');
          // the received ones are not part of the samples a later run starts from
          for (final id in ['sofia', 'during']) {
            await store.delete(id);
          }
          save(99);
          log('RESULTS ${jsonEncode(results)}');
          status.writeAsStringSync('done', flush: true);
          return;
      }
    }

    log('FILE PHASE $phase ($lang)');
    try {
      await run();
    } catch (err, st) {
      log('FAILED $err\n${st.toString().split('\n').take(12).join('\n')}');
      status.writeAsStringSync('failed ${'$err'.split('\n').take(3).join(' ')}', flush: true);
      rethrow;
    }
  });
}
