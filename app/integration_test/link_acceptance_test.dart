// Sending a blessing by link, receiving one, and passing a blessing along, replayed on the simulator
// against the website running on this Mac. Run by tool/link_acceptance.sh; read that first.
//
// The app is built with LINK_SERVICE pointing at tool/link_proxy.py, which hands every request on to
// the local website (`pnpm start`) and writes it down, so the script can show at the end that no key,
// and no stop token outside its own header, ever left the phone. Links reach the app the way iOS
// delivers them: `simctl openurl` with the debug scheme `uponthyhead-test://b/<id>#<key>` (the
// simulator cannot hand an app a universal link for a site that is not live); the app's handler is
// never called directly. The web page is opened in Chrome on the Mac (tool/link_web.mjs).
//
// Like file_test.dart it is built into the app and talks to the script through files only. In
// <app data>/tmp/fileacts it leaves `ask_<n>` and waits for `act_<n>`:
//   link <link>            simctl openurl the link (as uponthyhead-test://), the app in front or not running
//   bg <seconds> <link>    Home, wait, then open the link (the app was in the background)
//   web <link> <shot>      open the link in Chrome on the Mac; answers what the page shows, as JSON
//   plant <id> <base64>    put a locked copy in the website's folder under <id> (the refusals)
//   server stop|start      stop or start the website (no internet: the proxy then answers 502)
//   save <path>            copy a file the share sheet holds out of the simulator
//   file <name>            simctl openurl a file saved by `save`
//   apptap <label>|…       a button in the system share sheet (Copy completes it)
//   appdismiss <n>         close the system share sheet without choosing
//   pbclear, pbinfo        empty the simulator's pasteboard; what types it holds
//   face match             Face ID: the enrolled face
//   shot <name>            a screenshot into ../design/sim/link/
//   textsize <size>        simctl ui content_size
// Each link made is written to Documents/link_test_secrets.jsonl (id, key, stop token) for the
// script's check of what was sent. Progress goes to Documents/link_test_log.txt, the outcome to
// Documents/link_test_status (`next <n>`, `done`, or `failed …`).
//
//   1. Fresh samples, and a 2,5xx-word blessing with accents, an emoji and a polished change.
//      "Comfort before surgery" by link: the S3 sheet, the link, its length, the system sheet with
//      one URL, Copy; the web page shows the words, character for character. The long one and a
//      short one too. Then the three are deleted from the store (this phone becomes the receiver).
//   2. Launched by the link, locked: nothing until Face ID; the keep sheet; Keep; the page and the
//      light exactly as before. The long one in front, with its changes screen; from the
//      background; locked in the background; during a recording. "Your links", Stop: the web page
//      and the app both say it stopped. Delete a blessing with a live link: stopped. Every refusal.
//      No internet: one line, "Send as a file"; the file opens as before.
//   3. Passing it along: recorded, marked on review, finished: no light, not counted, in "To pass
//      along". Sent: the Sent sheet, Keep; a second, Delete (its link still opens on the web). One
//      moved back to "For me": its light appears.
//   4. Spanish: the share sheet, "Your links", "To pass along", a stopped link.
//   5. English at the first accessibility text size: the same screens, nothing off screen.
//   6. (iPad only, after 1) launched by the link: the keep sheet, the page, "Your links".

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/sent_link.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/link_crypto.dart';
import 'package:upon_thy_head/share/link_format.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/share/share_sheet.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'file_test.dart' show accentedLongWords, snapshot, wordCount;
import 'protocol_vectors.dart';
import 'share_test.dart' show extra;
import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

/// A link as the simulator can hand it to the app.
String testLink(String url) {
  final parts = linkPartsOf(url)!;
  return 'uponthyhead-test://b/${parts.id}#${parts.fragment}';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('link: a blessing sent by link, received, and passed along', timeout: const Timeout(Duration(minutes: 30)), (tester) async {
    Strings.use(UiLanguage.forLocales(PlatformDispatcher.instance.locales));
    final lang = Strings.language == UiLanguage.spanish ? 'es' : 'en';

    final docs = (await getApplicationDocumentsDirectory()).path;
    final tmp = Directory.systemTemp.path;
    final acts = Directory(p.join(tmp, 'fileacts'))..createSync(recursive: true);
    final logFile = File('$docs/link_test_log.txt');
    final status = File('$docs/link_test_status');
    final marker = File('$docs/link_test_phase');
    final secretsFile = File('$docs/link_test_secrets.jsonl');
    final state = marker.existsSync() ? jsonDecode(marker.readAsStringSync()) as Map<String, Object?> : <String, Object?>{'phase': 1};
    final phase = state['phase'] as int;
    var shots = (state['shots'] as int?) ?? 0;
    var actN = (state['acts'] as int?) ?? 0;
    final results = (state['results'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final before = (state['before'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final urls = (state['urls'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    var prefix = (state['prefix'] as String?) ?? '';

    void log(String s) {
      debugPrint(s);
      logFile.writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
    }

    void result(String key, Object? value) {
      results[key] = value;
      log('RESULT $key = $value');
    }

    void save(int nextPhase) => marker.writeAsStringSync(
        jsonEncode({...state, 'phase': nextPhase, 'shots': shots, 'acts': actN, 'results': results, 'before': before, 'urls': urls}),
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

    Future<String> act(String what, {int seconds = 120}) async {
      actN++;
      final n = actN;
      final answer = File(p.join(acts.path, 'act_$n'));
      if (answer.existsSync()) answer.deleteSync();
      File(p.join(acts.path, 'ask_$n.tmp'))
        ..writeAsStringSync(what, flush: true)
        ..renameSync(p.join(acts.path, 'ask_$n'));
      // the log never holds a key: a link is written as its id only
      log('ACT $n ${what.replaceAll(RegExp(r'#[A-Za-z0-9_=+/-]*'), '#…')}');
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!answer.existsSync()) {
        if (DateTime.now().isAfter(end)) fail('the script did not answer: $what');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(100);
      final s = answer.readAsStringSync().trim();
      log('ACT $n -> ${s.length > 300 ? '${s.substring(0, 300)}…' : s}');
      return s;
    }

    Future<void> shot(String name, {int settle = 500}) async {
      await wait(settle);
      shots++;
      await act('shot ${shots.toString().padLeft(2, '0')}-$prefix$lang-$name');
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
    String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data ?? '';
    bool shown(String key) => find.byKey(Key(key)).hitTestable().evaluate().isNotEmpty;
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    const crypto = NativeLinkCrypto();

    Future<void> launch({bool fresh = false, bool locked = false}) async {
      if (fresh) {
        store = await freshSeededStore();
        // links and stop tokens left by an earlier run would crowd "Your links"
        for (final l in await store.links()) {
          await store.removeLink(l.id);
        }
        for (final n in await crypto.names()) {
          await crypto.delete(n);
        }
        // the long one: the surgery sample's words, its polished changes kept, and then 2,491 words
        // with accents and emoji, so the changes are at the start and still stand on the words
        final surgery = BlessingRecord.of((await store.get('surgery'))!).toJson();
        final longJson = {
          ...surgery,
          'id': 'long',
          'title': 'Para Lucía, al empezar el año ✨',
          'given': '2026-01-04T03:15Z',
          'from': 'Abuelo Ruiz',
          'for': 'Lucía',
          'tags': ['Familia', 'Año nuevo'],
          'words': '${surgery['words']}\n\n${accentedLongWords()}',
        };
        final r = readBlessingFile(utf8.encode(jsonEncode(longJson)));
        expect(r, isA<BlessingReadOk>(), reason: '$r');
        await store.create((r as BlessingReadOk).record.toBlessing(place: samplePlace));
        await store.create(extra('minimal', 'A short one', DateTime.utc(2025, 11, 2, 22), raw: 'Be at peace, and know that you are loved.'));
        await store.close();
      }
      store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
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

    Future<void> tapKey(String key, {int after = 1200}) async {
      final f = find.byKey(Key(key));
      await Scrollable.ensureVisible(tester.element(f), alignment: .5);
      await wait(200);
      await tester.tap(f);
      await wait(after);
    }

    Future<void> home() async {
      for (var i = 0; i < 6 && !stage('home'); i++) {
        for (final k in ['read-back', 'links-back', 'pass-back', 'settings-back', 'review-back']) {
          if (shown(k)) {
            await tester.tap(find.byKey(Key(k)));
            await wait(1800);
            break;
          }
        }
      }
      expect(stage('home'), isTrue, reason: 'could not get home');
    }

    Future<Blessing> read(String id) async {
      await home();
      final i = e.blessings.indexWhere((b) => b.id == id);
      expect(i, greaterThanOrEqualTo(0), reason: 'no blessing $id');
      e.setFocus(i, instant: true);
      await wait(1200);
      await tester.tap(find.byKey(const Key('read')));
      await wait(2600);
      expect(stage('read'), isTrue);
      return e.blessings[i];
    }

    Future<void> settings() async {
      await home();
      await tester.tap(find.byKey(const Key('more')));
      await wait(1800);
      expect(stage('settings'), isTrue);
    }

    Future<void> yourLinks() async {
      await settings();
      await tapKey('settings-links', after: 1800);
      expect(stage('links'), isTrue);
    }

    Future<void> sheetFor(String what, {int seconds = 30}) async {
      await until(() async => sheetOn() || noticeOn(), seconds: seconds, what: 'the sheet for $what');
      await wait(900);
    }

    Future<void> closeSheet() async {
      for (final k in ['receive-ok', 'receive-not-now', 'receive-keep-mine']) {
        if (shown(k)) {
          await tapKey(k, after: 1500);
          return;
        }
      }
      fail('no way to close the sheet');
    }

    Future<Map<String, Object?>> web(String url, String name) async {
      shots++;
      final a = await act('web $url ${shots.toString().padLeft(2, '0')}-$prefix$lang-web-$name', seconds: 90);
      expect(a.startsWith('{'), isTrue, reason: 'the web page: $a');
      return (jsonDecode(a) as Map).cast<String, Object?>();
    }

    /// The web page shows [b]'s words, title and giver, character for character.
    Future<void> webShows(String url, Blessing b, String name) async {
      final page = await web(url, name);
      expect(page['state'], 'open', reason: '$page');
      expect(page['title'], b.shownTitle);
      if (b.from.isNotEmpty) expect(page['from'], Strings.blessingFrom(b.from));
      final want = b.words.split(RegExp(r'\n\s*\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final got = (page['words']! as List).cast<String>();
      expect(got.length, want.length, reason: 'paragraphs on the web page');
      for (var i = 0; i < want.length; i++) {
        expect(got[i], want[i], reason: 'paragraph ${i + 1} differs on the web page');
      }
      result('$lang.web.${b.id}', '${want.length} paragraphs, ${wordCount(b.words)} words, identical on the web page');
    }

    Future<void> keepSecrets(String url) async {
      final parts = linkPartsOf(url)!;
      final stop = await crypto.get('link.${parts.id}');
      expect(stop, isNotNull, reason: 'no stop token kept for ${parts.id}');
      secretsFile.writeAsStringSync('${jsonEncode({'id': parts.id, 'key': parts.fragment, 'stop': stop})}\n', mode: FileMode.append, flush: true);
    }

    /// The share sheet is open on [b]: make the link, hand it to the system sheet, Copy (completes).
    Future<String> makeAndSend(Blessing b, {bool shots = false, bool copy = true}) async {
      await until(() async => shown('share-choose'), what: 'the share sheet');
      await wait(600);
      // (the reading page of one passed along has a pill with the same words, under the sheet)
      final choose = find.byKey(const Key('share-choose'));
      expect(find.descendant(of: choose, matching: find.text(Strings.sendBlessing)), findsOneWidget);
      expect(find.descendant(of: choose, matching: find.text(Strings.keepNote)), findsOneWidget);
      expect(text('share-card-title'), b.shownTitle);
      expect(find.byKey(const Key('share-file')), findsNothing, reason: 'the file was offered before a link was tried');
      if (shots) await shot('share-s3');
      await tester.tap(find.byKey(const Key('share-send')));
      await until(() async => shown('share-made'), seconds: 40, what: 'the link to be made');
      await wait(700);
      final url = tester.state<ShareSheetState>(find.byType(ShareSheet)).debugUrl!;
      expect(text('share-made-line'), Strings.linkMade);
      if (shots) await shot('share-link-made');
      await keepSecrets(url);
      final parts = linkPartsOf(url)!;
      final key = keyOfFragment(parts.fragment);
      expect(key, isNotNull, reason: 'the link holds no key');
      expect(url, startsWith('$linkService/b/'));
      final real = linkOf(parts.id, key!, site: 'https://uponthyhead.app');
      expect(real.length, 92);
      result('$lang.link.${b.id}', 'made: id ${parts.id.length} characters, key ${parts.fragment.length}; ${url.length} characters here, ${real.length} as https://uponthyhead.app/b/…');
      await tester.tap(find.byKey(const Key('share-send-link')));
      await until(NativeShareApi.debugShowing, what: 'the system share sheet');
      await wait(1500);
      if (shots) await shot('system-sheet-link', settle: 600);
      final items = await NativeShareApi.debugItems();
      expect(items, hasLength(1), reason: 'the sheet was handed $items');
      expect(items.single['kind'], 'url');
      expect(items.single['url'], url);
      result('$lang.system.${b.id}', 'one item, a URL of ${items.single['length']} characters, the link itself');
      if (copy) {
        expect(await act('pbclear'), 'ok');
        var a = await act('apptap Copy|Copiar');
        // the sheet may still be rising: Copy is there but not yet tappable
        if (!a.startsWith('ok')) {
          await wait(2000);
          a = await act('apptap Copy|Copiar');
        }
        expect(a, startsWith('ok'), reason: a);
        await until(() async => !await NativeShareApi.debugShowing(), what: 'the system sheet to close');
        await wait(900);
        // Copy puts a URL on the pasteboard (public.url), which simctl cannot print; the sheet was
        // handed exactly the link (above)
        final info = await act('pbinfo');
        expect(info, contains('public.url'), reason: 'the pasteboard: $info');
      } else {
        for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
          await act('appdismiss $i');
          await wait(1500);
        }
        await until(() async => !await NativeShareApi.debugShowing(), what: 'the system sheet to close');
        await wait(900);
      }
      return url;
    }

    Future<String> sendLink(String id, {bool shots = false}) async {
      final b = await read(id);
      await tester.tap(find.byKey(const Key('read-share')));
      await wait(900);
      return makeAndSend(b, shots: shots);
    }

    /// The reading page for [id] and the store hold what [want] says, its light where it was.
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
      expect(text('read-title'), got.shownTitle);
      expect(text('read-date'), want['longDate']);
      final paras = (want['words'] as String).split(RegExp(r'\n\s*\n'));
      expect(find.text(paras.first), findsWidgets, reason: '$what: the first paragraph is not on the page');
      expect(find.text(paras.last), findsWidgets, reason: '$what: the last paragraph is not on the page');
      final i = e.blessings.indexWhere((b) => b.id == id);
      expect(e.focus, i, reason: 'the sky is not on it');
      final dRa = (e.blessings[i].ra - (want['ra']! as num).toDouble()).abs();
      final dDec = (e.blessings[i].dec - (want['dec']! as num).toDouble()).abs();
      expect(dRa < 1e-4 && dDec < 1e-9, isTrue, reason: 'the light moved: ra by $dRa, dec by $dDec');
      final place = got.place;
      result('$lang.kept.$id', '$what: every field as sent; ra within ${dRa.toStringAsExponential(1)} rad, dec within ${dDec.toStringAsExponential(1)}; place ${place.lat}, ${place.lon}');
    }

    /// New blessing, Begin, the prepared English passage fed in, Amen after twelve seconds.
    Future<Blessing> record({Future<void> Function()? during}) async {
      await home();
      await tester.tap(find.byKey(const Key('new')));
      await wait(2600);
      expect(stage('record'), isTrue);
      await until(() async => session().permissions != null, what: 'permissions');
      expect(session().permissions!.allGranted, isTrue, reason: 'run tool/sim_permissions.sh grant first');
      await tester.tap(find.byKey(const Key('begin')));
      await wait(300);
      expect(session().live, isTrue, reason: 'Begin did nothing');
      final draft = session().draft!;
      if (audioDir.isNotEmpty) await NativeSpeech.instance.debugFeed('$audioDir/en.m4a');
      await during?.call();
      while (session().elapsed < 12) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sheetOn(), isFalse, reason: 'the sheet came during the recording');
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
      await wait(2600);
      expect(stage('after'), isTrue);
      await until(() async => session().wordsState != WordsState.writing, seconds: 90, what: 'the words');
      if (audioDir.isNotEmpty) await NativeSpeech.instance.debugFeed(null);
      await wait(900);
      return draft;
    }

    /// Done on the review page, and Finish when it asks (there was a recording).
    Future<void> finish() async {
      await tapKey('review-done', after: 1200);
      if (shown('finish-confirm')) await tapKey('finish-confirm', after: 2600);
      await until(() async => stage('read'), what: 'the reading page after Done');
      await wait(1200);
    }

    Future<void> beforeOf(String id) async {
      final b = (await store.get(id))!;
      final i = e.blessings.indexWhere((x) => x.id == id);
      before[id] = {...snapshot(b), 'ra': e.blessings[i].ra, 'dec': e.blessings[i].dec};
    }

    Map<String, Object?> was(String id) => (before[id]! as Map).cast<String, Object?>();
    String url(String id) => urls[id]! as String;
    String idOf(String id) => linkPartsOf(url(id))!.id;
    Future<SentLink> sentLink(String linkId) async => (await store.links()).firstWhere((l) => l.id == linkId);

    Future<void> run() async {
      switch (phase) {
        case 1:
          await launch(fresh: true);
          await wait(2500);
          expect(lang, 'en');
          for (final id in ['surgery', 'long', 'minimal']) {
            await beforeOf(id);
          }
          final long = (await store.get('long'))!;
          expect(long.changes, isNotEmpty);
          result('long', '${wordCount(long.rawText)} words, ${long.changes.length} polished changes, accents and emoji');
          // ---- 1. sending by link ----
          urls['surgery'] = await sendLink('surgery', shots: prefix.isEmpty || prefix == 'ipad-');
          await webShows(url('surgery'), (await store.get('surgery'))!, 'surgery');
          if (prefix == 'ipad-') {
            await store.delete('surgery');
            save(6);
            status.writeAsStringSync('next 6', flush: true);
            return;
          }
          urls['long'] = await sendLink('long');
          await webShows(url('long'), long, 'long');
          urls['minimal'] = await sendLink('minimal');
          // ---- this phone becomes the one that receives: the three are not here ----
          for (final id in ['surgery', 'long', 'minimal']) {
            await store.delete(id);
          }
          save(2);
          status.writeAsStringSync('next 2', flush: true);
          return;

        case 2:
          // ---- 3/4. launched by the link, the app closed, locked ----
          await launch(locked: true);
          expect(lock.locked, isTrue);
          await nothingWhileLocked('Comfort before surgery');
          await unlock();
          await sheetFor('the link that launched the app');
          expect(text('receive-title'), 'Comfort before surgery');
          expect(text('receive-from'), Strings.blessingFrom('Dad'));
          await shot('keep-sheet');
          await tapKey('receive-keep', after: 600);
          await same('surgery', was('surgery'), 'launched by the link, locked');
          await shot('kept-reading-page', settle: 1200);
          // in front: the long one, with its changes screen
          await act('link ${testLink(url('long'))}');
          await sheetFor('the long one');
          expect(text('receive-title'), 'Para Lucía, al empezar el año ✨');
          await tapKey('receive-keep', after: 600);
          await same('long', was('long'), 'in front, 2,5xx words');
          final long = (await store.get('long'))!;
          expect(long.rawText, contains('🙏'));
          expect(long.rawText, contains('mamá'));
          await tapKey('read-review-changes', after: 2000);
          expect(stage('changes'), isTrue, reason: 'the changes screen');
          await shot('long-changes');
          await tester.tap(find.byKey(const Key('changes-back')));
          await wait(1800);
          expect(stage('read'), isTrue);
          result('long.changes', '${long.changes.length} changes, the screen opens over the page');
          // from the background
          await home();
          await act('bg 4 ${testLink(url('surgery'))}', seconds: 60);
          expect(lock.locked, isFalse, reason: 'four seconds away locked');
          // one already here: no question, its page opens, saying so
          await until(() async => noticeOn(), what: 'the notice, from the background');
          expect(find.text(Strings.alreadyHave), findsOneWidget);
          await until(() async => stage('read'), what: 'its page');
          expect(text('read-title'), 'Comfort before surgery');
          await shot('already-have-from-background', settle: 200);
          // locked in the background
          await act('bg 70 ${testLink(url('long'))}', seconds: 150);
          await until(() async => lock.locked, seconds: 10, what: 'the lock after 70 s away');
          await nothingWhileLocked('Para Lucía, al empezar el año ✨');
          await unlock();
          await until(() async => noticeOn() || stage('read'), what: 'the notice, locked in the background');
          await until(() async => stage('read'), what: 'its page');
          expect(text('read-title'), 'Para Lucía, al empezar el año ✨');
          result('ways', 'app closed and locked; in front; from the background; locked in the background');
          // during a recording: it waits until after Amen
          await record(during: () async {
            await act('link ${testLink(url('minimal'))}');
            await wait(4000);
            expect(sheetOn(), isFalse, reason: 'the sheet came during the recording');
            expect(session().live, isTrue, reason: 'the recording was interrupted');
            await shot('recording-link-waits');
          });
          expect(sheetOn(), isFalse, reason: 'the sheet came over the page after Amen');
          await tapKey('save-later', after: 1500);
          await sheetFor('the link that came during the recording');
          expect(text('receive-title'), 'A short one');
          await tapKey('receive-keep', after: 2500);
          expect(await store.get('minimal'), isNotNull);
          for (final d in (await store.list()).where((b) => b.draft)) {
            await store.delete(d.id);
          }
          result('recording', 'the link waited through the recording and the page after Amen');
          // ---- 5. Your links: listed; Stop ----
          await yourLinks();
          final sid = idOf('surgery');
          expect(find.byKey(Key('link-row-$sid')), findsOneWidget);
          expect(find.byKey(Key('link-row-${idOf('long')}')), findsOneWidget);
          expect(find.byKey(Key('link-row-${idOf('minimal')}')), findsOneWidget);
          await shot('your-links');
          await tapKey('link-stop-$sid');
          expect(shown('stop-confirm'), isTrue);
          expect(find.text(Strings.stopBody), findsOneWidget);
          await shot('stop-sheet');
          await tapKey('stop-confirm', after: 2500);
          final stopped = await sentLink(sid);
          expect(stopped.stopped, isNotNull, reason: 'not stopped here');
          expect(text('link-line-$sid'), Strings.linkStoppedOn(stopped.stopped!.toLocal()));
          expect(await crypto.get('link.$sid'), isNull, reason: 'the stop token was kept after stopping');
          await shot('your-links-stopped');
          final page = await web(url('surgery'), 'stopped');
          expect(page['state'], 'gone', reason: '$page');
          expect(page['h1'], 'This link has stopped working.');
          await act('link ${testLink(url('surgery'))}');
          await sheetFor('a stopped link');
          expect(text('receive-title'), Strings.linkStoppedTitle);
          await shot('arrival-stopped');
          await closeSheet();
          result('stop', 'stopped from Your links: the row says so, the token is gone, the web page says "This link has stopped working.", the app says ${Strings.linkStoppedTitle}');
          // ---- deleting a blessing with a live link stops it ----
          await read('long');
          await tapKey('read-delete');
          expect(find.text(Strings.deleteLiveBody), findsOneWidget);
          await shot('delete-live-link');
          await tapKey('delete-confirm', after: 3000);
          expect(await store.get('long'), isNull);
          expect((await sentLink(idOf('long'))).stopped, isNotNull, reason: 'deleting did not stop its link');
          expect((await web(url('long'), 'deleted-stopped'))['state'], 'gone');
          result('delete', 'deleting a blessing with a live link stopped it first; the web page says it has stopped');
          // ---- 8. every refusal, as the app shows it ----
          await home();
          final v = jsonDecode(protocolVectorsJson) as Map<String, Object?>;
          final rnd = math.Random();
          String newId() => base64Url.encode(List.generate(16, (_) => rnd.nextInt(256))).replaceAll('=', '');
          final refusals = [
            ...(v['refusals']! as List).cast<Map<String, Object?>>(),
            ...(v['records']! as List).cast<Map<String, Object?>>(),
          ];
          final seen = <String>[];
          for (final r in refusals) {
            final id = newId();
            final planted = await act('plant $id ${r['locked']}');
            expect(planted, 'ok');
            await act('link uponthyhead-test://b/$id#${r['key']}');
            await sheetFor(r['name']! as String);
            final want = r['error'] == 'newer' ? Strings.fileNewer : Strings.linkUnreadable;
            expect(text('receive-title'), want, reason: '${r['name']}');
            if (seen.length < 2 || r['error'] == 'newer') await shot('refused-${r['error']}', settle: 300);
            await closeSheet();
            seen.add('${r['name']}: ${r['error']}');
          }
          final someId = newId();
          await act('plant $someId ${(v['vectors']! as List).first['locked']['base64']}');
          for (final f in (v['fragments']! as List).cast<Map<String, Object?>>()) {
            await act('link uponthyhead-test://b/$someId#${f['fragment']}');
            await sheetFor('fragment "${f['fragment']}"');
            expect(text('receive-title'), Strings.linkNoKey);
            if (f['fragment'] == '') await shot('refused-no-key', settle: 300);
            await closeSheet();
            seen.add('fragment ${f['why'] ?? f['fragment']}: key');
          }
          await act('link uponthyhead-test://b/${newId()}#${(v['vectors']! as List).first['link'].toString().split('#').last}');
          await sheetFor('a link never made');
          expect(text('receive-title'), Strings.linkStoppedTitle);
          await closeSheet();
          seen.add('never there: 410, stopped');
          result('refusals', '${seen.length} refused as the contract says: ${seen.join('; ')}');
          // ---- 6. no internet: one line, Send as a file; the file opens as before ----
          await act('server stop');
          final m = await read('minimal');
          await beforeOf('minimal');
          await tester.tap(find.byKey(const Key('read-share')));
          await wait(900);
          await tester.tap(find.byKey(const Key('share-send')));
          await until(() async => shown('share-file'), seconds: 40, what: 'no internet, and the file');
          await wait(700);
          expect(text('share-offline-line'), Strings.offLine);
          expect(find.text(Strings.sendFile), findsOneWidget);
          await shot('no-internet-file');
          await tester.tap(find.byKey(const Key('share-file')));
          await until(NativeShareApi.debugShowing, what: 'the system share sheet');
          await wait(1500);
          final items = await NativeShareApi.debugItems();
          expect(items, hasLength(1));
          expect(items.single['kind'], 'file');
          final name = items.single['name']! as String;
          final a = await act('save ${base64.encode(utf8.encode(items.single['path']! as String))}');
          expect(a, startsWith('ok'), reason: a);
          for (var i = 0; i < 3 && await NativeShareApi.debugShowing(); i++) {
            await act('appdismiss $i');
            await wait(1500);
          }
          await act('server start', seconds: 90);
          await home();
          await store.delete(m.id);
          await act('file $name');
          await sheetFor('the file');
          expect(text('receive-title'), 'A short one');
          await tapKey('receive-keep', after: 600);
          await same('minimal', was('minimal'), 'sent as a file with no internet');
          result('offline', 'no internet: "${Strings.offLine}", "${Strings.sendFile}"; the file "$name" opened and kept as before');
          save(3);
          status.writeAsStringSync('next 3', flush: true);
          return;

        case 3:
          // ---- 9. passing it along ----
          // none left from an earlier attempt
          final before3 = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: audio);
          for (final b in await before3.list(ownership: Ownership.passingOn)) {
            await before3.delete(b.id);
          }
          await before3.close();
          await launch();
          await wait(2500);
          final count = text('count');
          final lights = e.blessings.length;
          Future<Blessing> passOne(int n) async {
            final draft = await record();
            await tapKey('review-now', after: 2600);
            expect(stage('review'), isTrue);
            await tapKey('review-passing', after: 1500);
            if (n == 1) await shot('review-passing');
            await finish();
            final b = (await store.get(draft.id))!;
            expect(b.ownership, Ownership.passingOn);
            expect(b.draft, isFalse);
            expect(e.blessings.where((x) => x.id == b.id), isEmpty, reason: 'it has a light');
            expect(e.blessings.length, lights);
            if (n == 1) await shot('passing-reading-page');
            await home();
            expect(text('count'), count, reason: 'it was counted');
            expect(find.byKey(const Key('to-review')), findsNothing, reason: 'still a draft');
            return b;
          }

          final first = await passOne(1);
          final second = await passOne(2);
          await settings();
          expect(text('settings-pass-count'), '2');
          await shot('settings-pass-along');
          await tapKey('settings-pass-along', after: 1800);
          expect(stage('passing'), isTrue);
          expect(find.byKey(Key('pass-row-${first.id}')), findsOneWidget);
          expect(find.byKey(Key('pass-row-${second.id}')), findsOneWidget);
          expect(text('pass-status-${first.id}'), endsWith(Strings.notSentYet));
          await shot('to-pass-along');
          // send the first: Sent, Keep
          await tapKey('pass-row-${first.id}', after: 2400);
          expect(stage('read'), isTrue);
          await tapKey('read-send', after: 900);
          final u1 = await makeAndSend(first);
          await until(() async => shown('sent-keep'), what: 'the Sent sheet');
          await wait(600);
          expect(find.text(Strings.sentTitle), findsOneWidget);
          await shot('sent-sheet');
          await tapKey('sent-keep', after: 1500);
          final kept = (await store.get(first.id))!;
          expect(kept.sent, isNotNull);
          expect(shown('read-sent'), isTrue);
          await tapKey('read-back', after: 1800);
          expect(stage('passing'), isTrue);
          expect(text('pass-status-${first.id}'), endsWith(Strings.sentOn(kept.sent!.toLocal())));
          await shot('to-pass-along-sent');
          // the second: Sent, Delete; its link still opens on the web
          await tapKey('pass-row-${second.id}', after: 2400);
          await tapKey('read-send', after: 900);
          final u2 = await makeAndSend(second);
          await until(() async => shown('sent-delete'), what: 'the Sent sheet');
          await wait(600);
          await tapKey('sent-delete', after: 2500);
          expect(await store.get(second.id), isNull);
          final page = await web(u2, 'passed-deleted');
          expect(page['state'], 'open', reason: 'the link of a deleted passed-along blessing stopped: $page');
          expect((await sentLink(linkPartsOf(u2)!.id)).stopped, isNull);
          result('passing', 'two recorded and marked: no light, count unchanged ("$count"), in To pass along; Sent → Keep keeps it with its date; Sent → Delete deletes it and its link still opens on the web page');
          // the first back to For me: its light appears
          await until(() async => stage('passing'), what: 'the list');
          await tapKey('pass-row-${first.id}', after: 2400);
          await tapKey('read-edit', after: 2600);
          expect(stage('review'), isTrue);
          await tapKey('review-for-me', after: 2000);
          expect(e.blessings.where((x) => x.id == first.id), hasLength(1), reason: 'no light');
          expect(e.focus, e.blessings.indexWhere((x) => x.id == first.id));
          await tapKey('review-back', after: 2400);
          await shot('for-me-light', settle: 1500);
          await home();
          expect(text('count'), isNot(count));
          result('forMe', 'moved back to For me: its light appears and is counted ("${text('count')}")');
          // leave the run's own blessings out of the samples
          await store.delete(first.id);
          expect(u1, isNotEmpty);
          save(4);
          status.writeAsStringSync('next 4', flush: true);
          return;

        case 4:
          // ---- 10. Spanish ----
          expect(lang, 'es');
          await launch();
          await wait(2500);
          final b = await read('surgery');
          await tester.tap(find.byKey(const Key('read-share')));
          await wait(900);
          final u = await makeAndSend(b, shots: true, copy: false);
          urls['es'] = u;
          await yourLinks();
          expect(find.text(Strings.yourLinks), findsWidgets);
          await shot('your-links');
          await settings();
          await shot('settings');
          await act('link ${testLink(url('surgery'))}');
          await sheetFor('un enlace detenido');
          expect(text('receive-title'), Strings.linkStoppedTitle);
          await shot('arrival-stopped');
          await closeSheet();
          result('spanish', 'the share sheet, the link made, the system sheet, Tus enlaces, Ajustes and a stopped link, in Spanish');
          save(5);
          status.writeAsStringSync('next 5', flush: true);
          return;

        case 5:
          // ---- 10. the first accessibility text size ----
          expect(lang, 'en');
          prefix = 'large-';
          await launch();
          await wait(2500);
          final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
          void onScreen(List<String> keys) {
            for (final k in keys) {
              final r = tester.getRect(find.byKey(Key(k)));
              expect(r.top >= 0 && r.bottom <= screen.height + .5 && r.left >= 0 && r.right <= screen.width + .5, isTrue, reason: '$k off screen: $r');
            }
          }
          final b = await read('surgery');
          await tester.tap(find.byKey(const Key('read-share')));
          await wait(1200);
          onScreen(['share-send', 'share-card-title']);
          await shot('share-s3');
          await tester.tap(find.byKey(const Key('share-send')));
          await until(() async => shown('share-made'), seconds: 40, what: 'the link');
          await wait(900);
          await keepSecrets(tester.state<ShareSheetState>(find.byType(ShareSheet)).debugUrl!);
          onScreen(['share-send-link', 'share-made-line']);
          await shot('share-link-made');
          await tester.tapAt(const Offset(20, 60));
          await wait(1200);
          await yourLinks();
          await shot('your-links');
          await tapKey('link-stop-${idOf('minimal')}');
          onScreen(['stop-confirm', 'stop-cancel']);
          await shot('stop-sheet');
          await tapKey('stop-cancel');
          await settings();
          await shot('settings');
          await act('link ${testLink(url('surgery'))}');
          await sheetFor('a stopped link');
          onScreen(['receive-ok']);
          await shot('arrival-stopped');
          await closeSheet();
          await store.delete('minimal');
          await act('link ${testLink(url('minimal'))}');
          await sheetFor('a link to keep');
          onScreen(['receive-keep', 'receive-not-now']);
          await shot('keep-sheet');
          await tapKey('receive-keep', after: 2500);
          expect(b.id, 'surgery');
          result('large', 'accessibility-medium: the share sheet, the link made, Your links, Stop, a stopped link and the keep sheet: nothing off screen');
          save(99);
          log('RESULTS ${jsonEncode(results)}');
          status.writeAsStringSync('done', flush: true);
          return;

        case 6:
          // ---- iPad: launched by the link ----
          prefix = 'ipad-';
          await launch();
          await sheetFor('the link on iPad');
          expect(text('receive-title'), 'Comfort before surgery');
          await shot('keep-sheet');
          await tapKey('receive-keep', after: 600);
          await same('surgery', was('surgery'), 'iPad, launched by the link');
          await shot('kept-reading-page', settle: 1200);
          await yourLinks();
          await shot('your-links');
          result('ipad', 'sent by link, the web page, launched by the link, kept, Your links');
          save(99);
          log('RESULTS ${jsonEncode(results)}');
          status.writeAsStringSync('done', flush: true);
          return;
      }
    }

    log('LINK PHASE $phase ($lang)');
    try {
      await run();
    } catch (err, st) {
      log('FAILED $err\n${st.toString().split('\n').take(12).join('\n')}');
      status.writeAsStringSync('failed ${'$err'.split('\n').take(3).join(' ')}', flush: true);
      rethrow;
    }
  });
}
