// The recording flow with real capture and real on-device transcription, on a simulator:
//
//   tool/speech_tests.sh            (installs, grants permissions, runs this, then the refused run)
//
// or by hand, after `tool/sim_permissions.sh grant` on an installed app:
//
//   SIM_SHOTS=1 flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/speech_test.dart \
//     --dart-define=SPEECH_AUDIO=$PWD/integration_test/audio [--dart-define=SPEECH_REFUSED=true]
//
// The microphone really records (the simulator hears the Mac's microphone), but so the words
// are the same every run, the recorder is told (NativeSpeech.debugFeed) to replace the finished
// file with the prepared recording of the sample blessing, integration_test/audio/en.m4a, at
// Amen. Everything after that — the file in the app's audio folder, the native transcription,
// the store, the reading page — is the real path.
//
// Screenshots are the simulator's own (the system menu is not part of Flutter's frame): the
// test prints `SIMSHOT speech/<name>` and tool/speech_tests.sh saves them in design/sim/speech/.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/language_menu.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');
const refusedRun = bool.fromEnvironment('SPEECH_REFUSED');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late WidgetTester tester;
  late BlessingStore store;
  late String audio;

  Future<void> wait(int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(bool Function() ok, {int seconds = 30, String what = ''}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The simulator's own screenshot, taken by tool/speech_tests.sh when it sees the line.
  Future<void> shot(String name) async {
    await wait(300);
    debugPrint('SIMSHOT speech/$name');
    await wait(1500);
  }

  RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
  bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
  String language() => tester.widget<Text>(find.byKey(const Key('language-label'))).data!;
  List<String> filesOf(String id) => Directory(audio).existsSync()
      ? [for (final f in Directory(audio).listSync()) p.basename(f.path)].where((n) => n.startsWith(id)).toList()
      : [];

  Future<void> hold(int ms) async {
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
    await wait(ms);
    await g.up();
  }

  Future<void> openRecord() async {
    await tester.tap(find.byKey(const Key('new')));
    await wait(2600);
    expect(stage('record'), isTrue);
    await until(() => session().permissions != null, what: 'permissions');
  }

  Future<void> loadSky() async {
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sky, findsOneWidget, reason: 'the sky never loaded');
    await wait(1500);
  }

  Future<void> begin() async {
    await tester.tap(find.byKey(const Key('begin')));
    await wait(200);
    expect(session().live, isTrue);
  }

  Future<void> amen() async {
    await until(() => session().elapsed >= 11, what: 'ten seconds');
    await hold(1100);
    await wait(300);
    expect(stage('after'), isTrue);
  }

  setUp(() async {
    store = await freshSeededStore();
    audio = await defaultAudioDir();
    if (Directory(audio).existsSync()) Directory(audio).deleteSync(recursive: true);
    final settings = File(p.join((await getApplicationSupportDirectory()).path, 'settings.json'));
    if (settings.existsSync()) settings.deleteSync();
  });

  if (refusedRun) {
    testWidgets('speech: permissions refused', (t) async {
      tester = t;
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
      await loadSky();
      await openRecord();
      expect(session().permissions!.anyDenied, isTrue, reason: 'run tool/sim_permissions.sh deny first');
      await wait(800);
      expect(find.byKey(const Key('refused')), findsOneWidget);
      expect(find.byKey(const Key('open-settings')), findsOneWidget);
      expect(find.byKey(const Key('language')), findsNothing);
      expect(session().canBegin, isFalse);
      await tester.tap(find.byKey(const Key('begin')));
      await wait(800);
      expect(session().live, isFalse, reason: 'Begin started a recording without permission');
      await shot('03-refused');
    });
    return;
  }

  testWidgets('speech: language, Begin to Amen, words written on the phone, discard and delete', (t) async {
    tester = t;
    expect(audioDir, isNotEmpty, reason: 'pass --dart-define=SPEECH_AUDIO=<folder with en.m4a>');
    final speech = NativeSpeech.instance;
    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    await loadSky();

    // ---- 1. ready: permissions granted, the phone's language (English) ----
    await openRecord();
    expect(session().permissions!.allGranted, isTrue, reason: 'run tool/sim_permissions.sh grant first');
    expect(find.byKey(const Key('refused')), findsNothing);
    expect(language(), 'English');
    debugPrint('ENGINE en ${await speech.engine(SpeechLanguage.english)}');
    debugPrint('ENGINE es ${await speech.engine(SpeechLanguage.spanish)}');
    await shot('01-ready');

    // ---- 2. the system pull-down menu ----
    final menu = tester.state<LanguageControlState>(find.byKey(const Key('language')));
    await menu.debugOpen();
    await wait(800);
    await shot('02-menu');
    await menu.debugClose();
    await wait(600);

    // ---- 3. choose Español (as the menu's action does), and it is remembered ----
    menu.debugPick(SpeechLanguage.spanish);
    await wait(400);
    expect(language(), 'Español');
    await tester.tap(find.byKey(const Key('rec-x'))); // Close
    await wait(2500);
    expect(stage('home'), isTrue);
    await openRecord();
    expect(language(), 'Español', reason: 'the last choice was not remembered');

    // ---- 4. a Spanish blessing: recorded, kept with its audio; written if the phone can ----
    await begin();
    final esDraft = session().draft!;
    await speech.debugFeed('$audioDir/es.m4a');
    await amen();
    expect(find.byKey(const Key('after-writing')), findsOneWidget, reason: '"Writing the words…" did not show');
    await until(() => session().wordsState != WordsState.writing, what: 'the Spanish words');
    final esState = session().wordsState;
    debugPrint('SPANISH state=$esState engine=${session().transcript?.engine} locale=${session().transcript?.locale} '
        'words=<<<${session().words}>>>');
    expect(esState, anyOf(WordsState.done, WordsState.unavailable));
    await wait(900);
    await shot(esState == WordsState.unavailable ? '05b-after-unavailable' : '05b-after-spanish');
    expect(filesOf(esDraft.id), ['${esDraft.id}.m4a'], reason: 'the Spanish recording was not kept');
    final esSaved = (await store.get(esDraft.id))!;
    expect(esSaved.audio, '${esDraft.id}.m4a');
    expect(esSaved.language, 'es');
    await wait(2200); // the after-Amen screen is still arriving when the words come quickly
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(3000);
    expect(stage('home'), isTrue);

    // ---- 5. back to English; Discard in the first seconds deletes what was recorded ----
    await openRecord();
    expect(language(), 'Español');
    tester.state<LanguageControlState>(find.byKey(const Key('language'))).debugPick(SpeechLanguage.english);
    await wait(400);
    expect(language(), 'English');
    await begin();
    final gone = session().draft!;
    await wait(3000);
    expect(filesOf(gone.id), isNotEmpty, reason: 'nothing was being recorded');
    await hold(1100);
    await wait(1200);
    expect(session().live, isFalse);
    expect(filesOf(gone.id), isEmpty, reason: 'discard left audio behind');

    // ---- 6. an interruption: paused, then listening again; the parts are joined at Amen ----
    await speech.debugFeed(null);
    await begin();
    final joined = session().draft!;
    await wait(3000);
    await speech.debugInterrupt(true);
    await until(() => session().paused, what: 'paused');
    await wait(300);
    expect(find.text('Paused'), findsOneWidget);
    await wait(1500);
    await speech.debugInterrupt(false);
    await until(() => !session().paused, what: 'listening again');
    await wait(300);
    expect(find.text('Listening'), findsOneWidget);
    expect(filesOf(joined.id).where((n) => n.contains('.part')).length, 2, reason: 'a second part did not start');
    await amen();
    await until(() => session().wordsState != WordsState.writing, what: 'the words of the joined recording');
    expect(filesOf(joined.id), ['${joined.id}.m4a'], reason: 'the parts were not joined into one file');
    expect(File(p.join(audio, '${joined.id}.m4a')).lengthSync(), greaterThan(10000));
    debugPrint('JOINED ${File(p.join(audio, '${joined.id}.m4a')).lengthSync()} bytes, words=<<<${session().words}>>>');
    await wait(2200); // the after-Amen screen is still arriving when the words come quickly
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(3000);

    // ---- 7. the English blessing: Begin to Amen makes a file; the words are written ----
    await openRecord();
    expect(language(), 'English');
    await begin();
    final draft = session().draft!;
    await speech.debugFeed('$audioDir/en.m4a');
    await amen();
    expect(find.byKey(const Key('after-writing')), findsOneWidget, reason: '"Writing the words…" did not show');
    expect(find.text('The recording stays on this phone until you have reviewed the words. Then it is erased.'), findsOneWidget);
    await shot('04-after-writing');
    await until(() => session().wordsState == WordsState.done, what: 'the English words');
    await wait(900);
    expect(find.text('The words are kept'), findsOneWidget);
    await shot('05-after-done');
    final kept = (await store.get(draft.id))!;
    expect(kept.rawText, contains('blessing of comfort'));
    expect(kept.audio, '${draft.id}.m4a');
    expect(File(p.join(audio, kept.audio)).existsSync(), isTrue);
    debugPrint('ENGLISH engine=${session().transcript?.engine} locale=${session().transcript?.locale}');
    await speech.debugFeed(null);

    // ---- 8. the reading page shows the words ----
    await wait(2200); // the after-Amen screen is still arriving when the words come quickly
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(3000);
    expect(stage('home'), isTrue);
    await tester.tap(find.byKey(const Key('read')));
    await wait(2500);
    expect(stage('read'), isTrue);
    expect(find.textContaining('blessing of comfort'), findsOneWidget);
    expect(find.byKey(const Key('read-no-words')), findsNothing);
    await shot('06-reading');

    // ---- 9. deleting the blessing deletes its audio ----
    await tester.scrollUntilVisible(find.byKey(const Key('read-delete')), 300, scrollable: find.byType(Scrollable).first);
    await wait(400);
    await tester.tap(find.byKey(const Key('read-delete')));
    await wait(900);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await wait(2500);
    expect(await store.get(draft.id), isNull);
    expect(filesOf(draft.id), isEmpty, reason: 'deleting the blessing left its audio');
  });
}
