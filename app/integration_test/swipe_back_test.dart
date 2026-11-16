// The edge swipe back (the owner's ruling, 2026-11-16), replayed on the simulator with real
// drags from the left edge: Settings, the reading page and the review page each go back with a
// long drag and spring back from a short one; on review, the typed title is kept and it stays a
// draft. During a recording, a drag from the edge does nothing. Needs the microphone allowed
// (tool/sim_permissions.sh grant), as the recording test does.
//
// Filmed by tool/film.sh from DEMO START to DEMO END:
//   tool/film.sh integration_test/swipe_back_test.dart ../design/sim/onboarding/p2-swipe-back.mov

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/widgets/edge_swipe.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the edge swipe back: Settings, read, review; not while recording', timeout: const Timeout(Duration(minutes: 4)), (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    double moved(String name) {
      final swipe = find.descendant(of: find.byKey(Key('stage-$name')), matching: find.byType(EdgeSwipeBack));
      return swipe.evaluate().isEmpty ? 0 : tester.state<EdgeSwipeBackState>(swipe.first).progress;
    }

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final y = size.height * .55;

    /// A finger from the left edge, [fraction] of the width across, at an unhurried pace, held
    /// still for a moment before it lifts (no flick); [check] is called while it is still down.
    Future<void> edgeDrag(double fraction, {void Function()? check}) async {
      final g = await tester.startGesture(Offset(4, y));
      const steps = 30;
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(size.width * fraction / steps, 0));
        await wait(22);
      }
      await wait(250);
      check?.call();
      await g.up();
      await wait(900);
    }

    final store = await freshSeededStore();
    final draft = Blessing(
      id: 'swipe-draft',
      title: 'Blessing',
      from: '',
      utc: DateTime.utc(2026, 11, 10, 2),
      utcOffset: const Duration(hours: -7),
      place: samplePlace,
      rawText: 'Words heard when it was recorded.',
      firstText: 'Words heard when it was recorded.',
      audio: '',
      language: 'en',
      draft: true,
    );
    await store.create(draft);
    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sky, findsOneWidget, reason: 'the sky never loaded');
    await wait(2000);
    debugPrint('DEMO START');
    await wait(800);

    // ---- Settings ----
    await tester.tap(find.byKey(const Key('more')));
    await wait(1400);
    expect(stage('settings'), isTrue);
    await edgeDrag(.22, check: () => expect(moved('settings'), closeTo(.22, .04), reason: 'the page follows the finger'));
    expect(stage('settings'), isTrue, reason: 'a short drag springs back and stays');
    expect(moved('settings'), 0);
    await edgeDrag(.6);
    expect(stage('settings'), isFalse, reason: 'a long drag goes back');
    expect(stage('home'), isTrue);
    debugPrint('SWIPE settings: short stays, long goes back');
    await wait(800);

    // ---- the reading page ----
    await tester.tap(find.byKey(const Key('read')));
    await wait(1600);
    expect(stage('read'), isTrue);
    await edgeDrag(.2);
    expect(stage('read'), isTrue, reason: 'a short drag springs back and stays');
    await edgeDrag(.6);
    expect(stage('read'), isFalse, reason: 'a long drag goes back');
    expect(stage('home'), isTrue);
    debugPrint('SWIPE read: short stays, long goes back');
    await wait(800);

    // ---- the review page: what was typed is kept, still a draft ----
    await tester.tap(find.byKey(const Key('to-review')));
    await wait(2600);
    expect(stage('review'), isTrue);
    await tester.tap(find.byKey(const Key('review-title')));
    await wait(600);
    await tester.enterText(find.byKey(const Key('review-title')), 'For the new school year');
    await wait(800);
    await edgeDrag(.2, check: () => expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('review-title')), matching: find.byType(EditableText))).focusNode.hasFocus, isFalse, reason: 'the keyboard goes as the swipe begins'));
    expect(stage('review'), isTrue, reason: 'a short drag springs back and stays');
    expect(tester.widget<CupertinoTextField>(find.byKey(const Key('review-title'))).controller!.text, 'For the new school year');
    await edgeDrag(.6);
    expect(stage('review'), isFalse, reason: 'a long drag goes back');
    await wait(800);
    final kept = await store.get('swipe-draft');
    expect(kept!.title, 'For the new school year', reason: 'the typed title is kept');
    expect(kept.draft, isTrue, reason: 'it stays a draft');
    debugPrint('SWIPE review: short stays, long goes back, title kept, still a draft');

    // ---- a recording: nothing ----
    await tester.tap(find.byKey(const Key('new')));
    await wait(2600);
    expect(stage('record'), isTrue);
    await tester.tap(find.byKey(const Key('begin')));
    await wait(1500);
    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    expect(session().live, isTrue, reason: 'Begin did not start: is the microphone allowed?');
    final before = tester.getTopLeft(find.byKey(const Key('rec-x')));
    await edgeDrag(.7, check: () => expect(tester.getTopLeft(find.byKey(const Key('rec-x'))), before, reason: 'the recording page does not move'));
    expect(stage('record'), isTrue, reason: 'a drag from the edge left the recording');
    expect(session().live, isTrue, reason: 'a drag from the edge stopped the recording');
    debugPrint('SWIPE record: nothing');
    await wait(600);
    debugPrint('DEMO END');
    session().discard();
    await wait(1000);
  });
}
