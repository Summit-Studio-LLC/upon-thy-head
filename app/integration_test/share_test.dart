// Sharing a blessing as text and as a PDF, replayed on the simulator with the real system share
// sheet. Run by tool/share_acceptance.sh, once per phase with --keep-app-running; each phase is a
// new launch.
//
// The test asks the script for what only the simulator can do with `ACT <n> <what>` lines, and waits
// for its answer in the app's tmp folder (`act_<n>`):
//   apptap <label>|…      press a button in the system share sheet (tool/alerts, a UI test)
//   pbclear               empty the simulator's pasteboard
//   pasteboard            the pasteboard's text, as base64
//   keep <pdf> <json>     copy the PDF the share sheet was given to ../design/sim/share/<lang>/ and
//                         check it on the Mac (tool/pdf_check.swift); answers PASSED or FAILED …
//   switcher <shot>       open the app switcher, screenshot it, open the app again
//   away <seconds>        Home, wait, open the app again
//   face match            Face ID: the enrolled face
//
//   1. English, US Letter: the icon on a finished blessing and not on a draft; text copied from the
//      sheet equals the expected text; PDFs of the sample, a long one, a minimal one and one with a
//      long title with "/" and ":"; the switcher with the sheet up; 70 s away with the sheet up;
//      finally a PDF left prepared when the script kills the app.
//   2. English: the next launch has removed the file.
//   3. Spanish (the app's language set to Spanish): the sample's text and PDF.
//   4. English with a British region: A4.

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
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

/// About 2,500 words in paragraphs of very different lengths, from one line to most of a page.
String longWords() {
  const sentences = [
    'I lay my hands upon your head and bless you with the peace that only the Lord can give.',
    'Your Father in Heaven knows the road you are walking, and He has walked beside you on every step of it.',
    'Remember the mornings when you rose early to help your mother, and know that those small kindnesses are written in heaven.',
    'I bless you with strength in your body and clearness in your mind.',
    'When the days are long and the work is hard, you will find that you are not alone.',
    'Be patient with yourself.',
    'The Lord does not ask you to be finished; He asks you to keep walking toward Him.',
    'I bless your home, that it may be a place of rest for all who enter it, and that the Spirit may stay there.',
    'You will be a light to your brothers and sisters, and they will remember your example long after these years have passed.',
    'Trust the quiet promptings that come to you, for they are from Him.',
    'I bless you that you may learn quickly, and that what you learn may be of use to others.',
    'There will be seasons of waiting, and in them you will grow in ways you cannot yet see.',
  ];
  // words per paragraph: very different lengths, from a few words to most of a page
  const sizes = [9, 160, 45, 330, 6, 95, 240, 28, 420, 60, 14, 270, 120, 5, 190, 300, 38, 150];
  var k = 0;
  final paras = <String>[];
  for (final n in sizes) {
    final words = <String>[];
    while (words.length < n) {
      words.addAll(sentences[k % sentences.length].split(' '));
      k += 5; // a different order each paragraph
    }
    var para = words.take(n).join(' ');
    if (!para.endsWith('.')) para = '${para.replaceFirst(RegExp(r'[,;]$'), '')}.';
    paras.add(para);
  }
  paras.add('I say these things in the name of Jesus Christ, amen.');
  return paras.join('\n\n');
}

Blessing extra(String id, String title, DateTime utc, {String from = '', String recipient = '', String raw = '', bool draft = false}) => Blessing(
      id: id,
      title: title,
      from: from,
      recipient: recipient,
      utc: utc,
      utcOffset: const Duration(hours: -7),
      place: samplePlace,
      rawText: raw,
      firstText: raw,
      draft: draft,
      created: utc,
      updated: utc,
    );

const longTitle = 'Before the move: for the children / their school, their friends, and the long road between the old house and the new one';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('share: text and PDF through the system share sheet', timeout: const Timeout(Duration(minutes: 14)), (tester) async {
    // the app's words follow the phone, as main() sets them
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    final w = Strings.wordsFor(Strings.language);
    final lang = Strings.language == UiLanguage.spanish ? 'es' : 'en';

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

    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path; // <app data>/tmp, where the script answers
    final shareDir = Directory(p.join(tmp, 'share'));
    final expectDir = Directory(p.join(tmp, 'expected'))..createSync(recursive: true);
    final marker = File('$docs/share_test_phase');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    var shots = (state['shots'] as int?) ?? 0;
    var acts = (state['acts'] as int?) ?? 0;
    final results = (state['results'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    debugPrint('SHARE PHASE $phase ($lang, paper ${await NativeShareApi.debugPaper()})');
    debugPrint('ACTDIR $tmp');

    void result(String key, Object? value) {
      results[key] = value;
      debugPrint('RESULT $key = $value');
    }

    void next(int n) {
      marker.writeAsStringSync(jsonEncode({...state, 'phase': n, 'shots': shots, 'acts': acts, 'results': results}), flush: true);
      debugPrint('NEXT $n');
    }

    Future<void> shot(String name, {int settle = 400}) async {
      await wait(settle);
      shots++;
      debugPrint('SIMSHOT share/${shots.toString().padLeft(2, '0')}-$lang-$name');
      await wait(1500);
    }

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
      debugPrint('ACT $n -> ${s.length > 200 ? '${s.substring(0, 200)}…' : s}');
      return s;
    }

    late BlessingStore store;
    late SkyEngine e;
    late AppLock lock;
    final audio = await defaultAudioDir();
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    List<String> shareFiles() => shareDir.existsSync() ? shareDir.listSync().map((f) => p.basename(f.path)).toList() : const [];

    Future<void> launch({bool fresh = false}) async {
      if (fresh) {
        store = await freshSeededStore();
        await store.create(extra('draft', 'A draft not yet reviewed', DateTime.utc(2026, 4, 20, 2), from: 'Dad', raw: 'Words not yet reviewed.', draft: true));
        await store.create(extra('long', 'A long blessing for the new year', DateTime.utc(2026, 1, 4, 3, 15), from: 'Grandpa Ruiz', recipient: 'Lucía', raw: longWords()));
        await store.create(extra('minimal', 'A short one', DateTime.utc(2025, 11, 2, 22), raw: 'Be at peace, and know that you are loved.'));
        await store.create(extra('titled', longTitle, DateTime.utc(2025, 5, 18, 17, 5), from: 'Mom', raw: 'You will find friends there.\n\nThe Lord goes before you.'));
        await store.close();
      }
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
      lock = unlockedLock();
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await until(() async => lock.ready, what: 'the lock');
      await wait(2500);
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

    Future<void> openShare(String kind, {String? sheetShot, String? systemShot}) async {
      await tester.tap(find.byKey(const Key('read-share')));
      await wait(900);
      if (sheetShot != null) await shot(sheetShot);
      await tester.tap(find.byKey(Key('share-$kind')));
      await until(NativeShareApi.debugShowing, what: 'the system share sheet');
      await wait(1500);
      if (systemShot != null) await shot(systemShot, settle: 600);
    }

    Future<void> closeSheet() async {
      // swiped down, as a person closes it (the iOS 26 sheet has no Close button); once more if needed
      for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
        await act('appdismiss $i');
        await wait(1500);
        if (!await NativeShareApi.debugShowing()) result('dismissedBy', ['a tap outside', 'a drag from its top edge', 'a swipe on it'][i]);
      }
      await until(() async => !await NativeShareApi.debugShowing(), what: 'the share sheet to close');
      await wait(800);
    }

    /// Copy from the sheet; the pasteboard must hold exactly the text.
    Future<void> copyText(Blessing b) async {
      expect(await act('pbclear'), 'ok');
      final a = await act('apptap Copy|Copiar');
      expect(a, startsWith('ok'), reason: 'no Copy in the share sheet: $a');
      await until(() async => !await NativeShareApi.debugShowing(), what: 'the sheet to close after Copy');
      final got = utf8.decode(base64.decode(await act('pasteboard')));
      final want = shareText(b, w);
      File(p.join(expectDir.path, 'text-$lang.txt')).writeAsStringSync(want);
      if (got != want) {
        debugPrint('PASTEBOARD GOT:\n$got\n---- WANT:\n$want');
      }
      expect(got, want, reason: 'the pasteboard differs from the expected text');
      result('$lang.text.${b.id}', 'pasteboard equals the expected text, ${want.length} characters');
      expect(shareFiles(), isEmpty, reason: 'text sharing left a file');
    }

    /// Share as PDF; the file the sheet was given is copied out and checked on the Mac.
    Future<void> pdf(String id, {String? sheetShot, String? systemShot, String paper = 'letter', int minPages = 1}) async {
      final b = await read(id);
      await openShare('pdf', sheetShot: sheetShot, systemShot: systemShot);
      final name = shareFileName(b, w);
      expect(shareFiles(), [name], reason: 'the file the sheet was given');
      final m = sharePdf(b, w);
      final want = {
        'fileName': name,
        'title': m['title'],
        'date': m['date'],
        'from': m['from'],
        'recipient': m['recipient'],
        'paragraphs': m['paragraphs'],
        'footer': m['pageOf'],
        'paper': paper,
        'minPages': minPages,
      };
      final json = File(p.join(expectDir.path, '$id-$lang.json'))..writeAsStringSync(jsonEncode(want));
      final a = await act('keep ${base64.encode(utf8.encode(p.join(shareDir.path, name)))} ${base64.encode(utf8.encode(json.path))} ${paper == 'a4' ? 'a4' : lang}', seconds: 180);
      expect(a, startsWith('PASSED'), reason: 'the PDF check: $a');
      result('$lang.pdf.$id', a);
      await closeSheet();
      expect(shareFiles(), isEmpty, reason: 'the file stayed after the sheet closed');
      expect(shareDir.existsSync(), isFalse, reason: 'the share folder stayed');
      result('$lang.pdf.$id.cleaned', 'tmp/share removed when the sheet closed');
    }

    switch (phase) {
      case 1:
        await launch(fresh: true);
        expect(lang, 'en');
        // ---- 1. the icon on a finished blessing, not on a draft ----
        final surgery = await read('surgery');
        expect(find.byKey(const Key('read-share')), findsOneWidget);
        await shot('reading-with-share');
        await read('draft');
        expect(find.byKey(const Key('read-share')), findsNothing, reason: 'a draft offers sharing');
        expect(find.byKey(const Key('read-review')), findsOneWidget);
        await shot('draft-no-share');
        result('icon', 'on "Comfort before surgery"; not on the draft');

        // ---- 2. as text, through Copy ----
        await read('surgery');
        await openShare('text', sheetShot: 'app-sheet', systemShot: 'system-sheet-text');
        // the switcher with the system sheet up: the native cover must be over it
        var covered = false;
        shots++;
        final sw = await act('switcher share/${shots.toString().padLeft(2, '0')}-$lang-switcher-with-sheet', during: () async {
          if (!covered) covered = await NativeLockApi.debugCovered();
        });
        expect(sw, startsWith('ok'));
        expect(covered, isTrue, reason: 'the share sheet was in the switcher without the cover');
        await wait(1500);
        expect(await NativeShareApi.debugShowing(), isTrue, reason: 'the sheet should still be up after a short trip');
        result('switcher', 'covered natively while in the switcher with the system sheet up; sheet still up on return');
        await copyText(surgery);

        // ---- 3-5. PDFs ----
        await pdf('surgery', systemShot: 'system-sheet-pdf');
        await pdf('long', minPages: 3);
        await pdf('minimal');
        await pdf('titled');

        // ---- 8. locked with the sheet up ----
        await read('surgery');
        await openShare('pdf');
        expect(shareFiles(), hasLength(1));
        await act('away 70', seconds: 150);
        await until(() async => lock.locked, seconds: 5, what: 'the lock after 70 s away');
        await wait(600);
        expect(await NativeShareApi.debugShowing(), isFalse, reason: 'the share sheet stayed up over the lock');
        expect(stage('read'), isFalse);
        expect(shareDir.existsSync(), isFalse, reason: 'the file stayed after locking');
        await shot('locked-sheet-gone', settle: 800);
        result('lock', 'away 70 s with the sheet up: locked, sheet dismissed, file removed');
        await until(() async => lock.asking, what: 'the automatic question');
        // the Face ID sheet takes a moment to be up; a face shown before it is not seen
        for (var i = 0; i < 3 && lock.locked; i++) {
          await wait(1500);
          await act('face match');
          await wait(2500);
        }
        await until(() async => !lock.locked, what: 'unlocked');
        await wait(1500);

        // ---- 7. killed with a file prepared ----
        await read('surgery');
        await openShare('pdf');
        expect(shareFiles(), hasLength(1));
        result('kill.before', 'prepared: ${shareFiles()}');
        debugPrint('KILL ${base64.encode(utf8.encode(shareDir.path))}');
        next(2);
        await wait(1000);
        return;

      case 2:
        // ---- 7. the next launch removes it ----
        await launch();
        await until(() async => !shareDir.existsSync(), seconds: 5, what: 'the file left by the killed app to be removed');
        result('kill.after', 'relaunched: tmp/share removed');
        next(3);
        return;

      case 3:
        // ---- Spanish ----
        await launch();
        expect(lang, 'es');
        final surgery = await read('surgery');
        await shot('reading-with-share');
        await openShare('text', sheetShot: 'app-sheet', systemShot: 'system-sheet-text');
        await copyText(surgery);
        await pdf('surgery', systemShot: 'system-sheet-pdf');
        next(4);
        return;

      case 4:
        // ---- 6. A4 ----
        await launch();
        expect(lang, 'en');
        expect(await NativeShareApi.debugPaper(), 'a4');
        await pdf('surgery', paper: 'a4');
        result('a4', 'region with A4: 595 × 842 pt');
        marker.writeAsStringSync(jsonEncode({...state, 'phase': 99, 'results': results}), flush: true);
        debugPrint('RESULTS ${jsonEncode(results)}');
        debugPrint('ALL DONE');
        return;
    }
  });
}
