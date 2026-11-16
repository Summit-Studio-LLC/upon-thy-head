// Walks the recording flow on a device or simulator, in real time:
//
//   flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/record_test.dart
//
// Screenshots land in ../design/sim/record/. The test prints `MARK <name> <epoch ms>`
// at New blessing and at Amen so a screen recording can be cut to match.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';
import 'package:upon_thy_head/record/hold_ring.dart';
import 'package:upon_thy_head/record/keep_awake.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/widgets/fade.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('record: begin, tap, hold to discard, amen, the sheet, save for later', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(150);
      await binding.takeScreenshot('record/$name');
    }

    void mark(String name) => debugPrint('MARK $name ${DateTime.now().millisecondsSinceEpoch}');

    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    bool closeShown() => tester.widget<Fade>(find.ancestor(of: find.byKey(const Key('rec-x')), matching: find.byType(Fade)).first).on;
    bool amenShown() => tester.widget<HoldRing>(find.byKey(const Key('hold'))).amen;

    /// Wait until [s] seconds after Begin.
    Future<void> until(double s) async {
      while (session().elapsed < s) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> hold(int ms) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(ms);
      await g.up();
    }

    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sky, findsOneWidget, reason: 'the sky never loaded');
    final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
    await wait(1500);
    expect(e.blessings.length, 5);

    // ---- 1. New blessing: the ready state ----
    mark('new');
    await tester.tap(find.byKey(const Key('new')));
    await wait(2600);
    expect(stage('record'), isTrue);
    expect(session().state, RecordState.ready);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('Nothing is recorded until you press.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    final draft = session().draft!;
    expect(e.blessings.last, same(draft), reason: 'the draft is the light in focus');
    expect(e.focus, 5);
    await shot('01-ready');

    // ---- 2. Begin: about three seconds in ----
    await tester.tap(find.byKey(const Key('begin')));
    await wait(100);
    expect(session().live, isTrue);
    expect(KeepAwake.on, isTrue);
    expect(await KeepAwake.get(), isTrue, reason: 'the idle timer was not disabled');
    await until(3);
    expect(amenShown(), isFalse);
    expect(closeShown(), isFalse,
        reason: 'no Discard at the top right in the first ten seconds');
    await shot('02-first-seconds');

    // ---- 3. a tap on the ring does not discard ----
    await tester.tap(find.byKey(const Key('hold')));
    await wait(500);
    expect(session().live, isTrue, reason: 'a tap discarded the recording');

    // ---- 4. holding the ring for a second inside the ten seconds discards ----
    expect(session().elapsed, lessThan(8));
    await hold(1000);
    await wait(1400);
    expect(session().state, RecordState.ready, reason: 'holding Discard did not discard');
    expect(stage('record'), isTrue, reason: 'discarding should return to Begin, not home');
    expect(await KeepAwake.get(), isFalse, reason: 'the idle timer was not released');
    await shot('03-discarded');

    // ---- 5. Begin again; a discard hold begun at 9.6 s is cancelled by the change to Amen ----
    await tester.tap(find.byKey(const Key('begin')));
    await wait(100);
    expect(session().live, isTrue);
    await until(9.6);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
    await wait(1100); // past both 0.9 s of holding and the ten seconds
    expect(session().live, isTrue, reason: 'a discard hold that crossed ten seconds discarded');
    expect(stage('after'), isFalse, reason: 'a discard hold that crossed ten seconds finished');
    await wait(600); // still holding: nothing more happens
    await g.up();
    await wait(400);
    expect(session().live, isTrue);
    expect(stage('record'), isTrue);
    await until(12);
    expect(amenShown(), isTrue);
    expect(find.text('Hold to finish'), findsOneWidget);
    expect(closeShown(), isTrue);
    expect(find.text('Discard'), findsWidgets);
    await shot('04-amen');

    // ---- 6. about 24 seconds in: figures drawn ----
    await until(24);
    expect(e.show!.plans, isNotEmpty, reason: 'no constellations picked');
    expect(e.show!.a, greaterThan(.9));
    await shot('05-constellations');

    // ---- 7. Discard at the top right: the sheet, and Keep listening ----
    await tester.tap(find.byKey(const Key('rec-x')));
    await wait(900);
    expect(session().sheet, isTrue);
    await shot('06-discard-sheet');
    await tester.tap(find.byKey(const Key('sheet-keep')));
    await wait(700);
    expect(session().sheet, isFalse);
    expect(session().live, isTrue, reason: 'Keep listening stopped the recording');

    // ---- 8. a short press nudges; holding Amen finishes ----
    await tester.tap(find.byKey(const Key('hold')));
    await wait(300);
    expect(session().live, isTrue, reason: 'a short press on Amen finished');
    await wait(500);
    await hold(1100);
    mark('amen');
    await wait(2600);
    expect(stage('after'), isTrue);
    expect(session().live, isFalse);
    expect(await KeepAwake.get(), isFalse);
    // the real microphone heard the room: wait for its words, then the settled title
    for (var i = 0; i < 300 && session().wordsState == WordsState.writing; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(session().wordsState, WordsState.done);
    expect(find.text(session().words.trim().isEmpty ? Strings.noWordsHeard : Strings.wordsKept), findsOneWidget);
    expect(e.solo, greaterThan(.9));
    await shot('07-after');

    // ---- 9. Save for later: home, six blessings, the new one in focus ----
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(3000);
    expect(stage('home'), isTrue);
    expect(e.blessings.length, 6);
    expect(e.focus, 5);
    expect(e.blessings[5], same(draft));
    expect(countLine(e.blessings), 'Six blessings since June 2024');
    expect(find.text('Six blessings since June 2024'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('cap-title'))).data, 'Blessing');
    expect(e.weights[5], greaterThan(.9));
    expect(e.fov, closeTo(SkyView.home.fov, .5));
    await shot('08-home-six');
  });
}
