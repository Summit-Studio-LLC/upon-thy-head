// The life of a blessing, across real restarts. Run by tool/store_lifecycle.sh,
// which launches this test three times and terminates the app between runs
// (`xcrun simctl terminate`), so each run is a new process reading the store
// from disk. A marker file in the app's documents folder says which part runs.
//
//   1. seeded: five; read Comfort before surgery; edit it on the review page; record a sixth
//   2. after a restart: six, the edit kept; the list; open the sixth; delete it
//   3. after another restart: five; delete them all; the empty sky
//
// Screenshots land in ../design/sim/store/.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/home/timeline.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the life of a blessing', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // tool/store_lifecycle.sh watches for SIMSHOT and takes the simulator's own
    // screenshot (status bar included) while the test holds still.
    Future<void> shot(String name) async {
      await wait(250);
      debugPrint('SIMSHOT store/$name');
      await wait(1200);
      await binding.takeScreenshot('store/$name');
    }

    final marker = File('${(await getApplicationDocumentsDirectory()).path}/store_test_phase');
    final phase = marker.existsSync() ? int.parse(marker.readAsStringSync().split(' ').first) : 1;
    debugPrint('STORE PHASE $phase');

    late BlessingStore store;
    late SkyEngine e;
    String caption() => tester.widget<Text>(find.byKey(const Key('cap-title'))).data!;
    String count() => tester.widget<Text>(find.byKey(const Key('count'))).data!;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    String readTitle() => tester.widget<Text>(find.byKey(const Key('read-title'))).data!;

    Future<void> launch(BlessingStore s) async {
      store = s;
      await tester.pumpWidget(UponThyHeadApp(store: s, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await wait(1500);
    }

    Future<void> toEnd() async {
      await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -4000));
      await wait(1400);
    }

    Future<void> toTop() async {
      await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, 4000));
      await wait(1400);
    }

    /// From the reading page: Delete this blessing, then Delete.
    Future<void> deleteShown({String? shotName}) async {
      await toEnd();
      await tester.tap(find.byKey(const Key('read-delete')));
      await wait(800);
      expect(find.text('Delete this blessing?'), findsOneWidget);
      expect(find.text('Its words will be removed from this phone. This cannot be undone.'), findsOneWidget);
      if (shotName != null) await shot(shotName);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await wait(2600);
      expect(stage('home'), isTrue, reason: 'deleting did not go home');
    }

    if (phase == 1) {
      // ---- 1. launched seeded: five ----
      await launch(await freshSeededStore());
      expect(e.blessings.length, 5);
      expect(count(), 'Five blessings since June 2024');
      expect(caption(), 'Before the new job', reason: 'opens on the newest');
      await shot('01-home');
      await tester.tap(find.byKey(const Key('older')));
      await wait(2600);
      expect(caption(), 'Comfort before surgery');

      // ---- 2. read it from the caption's arrow ----
      await tester.tap(find.byKey(const Key('read')));
      await wait(2600);
      expect(stage('read'), isTrue);
      expect(readTitle(), 'Comfort before surgery');
      expect(find.text('Tuesday, March 3, 2026'), findsWidgets);
      expect(find.text('A blessing from Dad'), findsOneWidget);
      expect(find.textContaining('Emma, I lay my hands upon your head to give you'), findsOneWidget);
      expect(e.solo, greaterThan(.9), reason: 'only its light shows');
      expect(e.fov, closeTo(SkyView.read.fov, 1.5));
      await shot('02-reading');
      await toEnd();
      expect(find.text(Strings.polishedFrom(5)), findsOneWidget, reason: 'the sample keeps its five changes');
      expect(find.byKey(const Key('read-review-changes')), findsOneWidget);
      expect(find.text('Its light keeps its place in time on the ring of sky overhead.'), findsOneWidget);
      expect(find.byKey(const Key('read-delete')), findsOneWidget);
      await shot('03-reading-end');
      await toTop();

      // ---- 3. edit the title and the giver ----
      // Edit opens the review page; a finished blessing has no recording, so Done just saves
      await tester.tap(find.byKey(const Key('read-edit')));
      await wait(2600);
      expect(stage('review'), isTrue);
      await tester.enterText(find.byKey(const Key('review-title')), 'Comfort before the operation');
      await tester.enterText(find.byKey(const Key('review-from')), 'Dad and Grandpa Ruiz');
      await wait(400);
      await shot('04a-edit');
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(600);
      await tester.tap(find.byKey(const Key('review-done')));
      await wait(2600);
      expect(stage('read'), isTrue);
      expect(readTitle(), 'Comfort before the operation');
      expect(find.text('A blessing from Dad and Grandpa Ruiz'), findsOneWidget);
      expect((await store.get('surgery'))!.title, 'Comfort before the operation');
      await shot('04-edited');
      await tester.tap(find.byKey(const Key('read-back')));
      await wait(2600);
      expect(stage('home'), isTrue);
      expect(caption(), 'Comfort before the operation');
      expect(tester.widget<Text>(find.byKey(const Key('cap-from'))).data, 'From Dad and Grandpa Ruiz');

      // ---- 4. record a new one through the real flow ----
      await tester.tap(find.byKey(const Key('new')));
      await wait(2600);
      await tester.tap(find.byKey(const Key('begin')));
      final session = tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
      expect(session.live, isTrue, reason: 'Begin did nothing: are the microphone and speech allowed? (tool/store_lifecycle.sh grants them)');
      while (session.elapsed < 11) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(session.amen, isTrue);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
      await wait(2600);
      expect(stage('after'), isTrue);
      final id = session.draft!.id;
      await tester.tap(find.byKey(const Key('save-later')));
      await wait(3000);
      expect(stage('home'), isTrue);
      expect(e.blessings.length, 6);
      expect(count(), 'Six blessings since June 2024');
      expect(caption(), 'Blessing');
      final saved = (await store.get(id))!;
      expect(saved.ownership, Ownership.forMe);
      expect(saved.draft, isTrue);
      expect(await store.count(), 6);
      await shot('05-six');
      marker.writeAsStringSync('2 $id');
      return;
    }

    final newId = marker.readAsStringSync().split(' ').last;
    await launch(SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath()));

    if (phase == 2) {
      // ---- 5. after a real restart: still six, the edit still there ----
      expect(e.blessings.length, 6);
      expect(count(), 'Six blessings since June 2024');
      expect(e.blessings.map((b) => b.id), contains(newId));
      expect(e.blessings.firstWhere((b) => b.id == 'surgery').title, 'Comfort before the operation');
      expect(caption(), 'Blessing', reason: 'opens on the newest, the one recorded');
      await shot('06-after-restart');

      // ---- 6. the list ----
      await tester.tap(find.byKey(const Key('list')));
      await wait(1600);
      expect(stage('list'), isTrue);
      expect(find.descendant(of: find.byType(Timeline), matching: find.text('Comfort before the operation')), findsOneWidget);
      await shot('07-list');
      final tl = tester.state<TimelineState>(find.byType(Timeline));
      // scroll as far as the prototype's second shot: the head at the third row down
      await tester.drag(find.byKey(const Key('list-scroll')), const Offset(0, -300));
      await wait(1400);
      expect(tl.scroll.offset, greaterThan(100));
      await shot('08-list-scrolled');
      await tester.drag(find.byKey(const Key('list-scroll')), const Offset(0, 2000));
      await wait(1400);
      await tester.tap(find.byKey(Key('row-$newId')));
      await wait(2600);
      expect(stage('read'), isTrue);
      expect(readTitle(), 'Blessing');
      expect(find.text('No words have been kept for this blessing yet.'), findsOneWidget);

      // ---- 7. delete the new one ----
      await deleteShown(shotName: '09-delete-sheet');
      expect(e.blessings.length, 5);
      expect(count(), 'Five blessings since June 2024');
      expect(await store.get(newId), isNull);
      await shot('10-five');
      marker.writeAsStringSync('3 $newId');
      return;
    }

    // ---- 7, continued. after another restart: still five ----
    expect(e.blessings.length, 5);
    expect(e.blessings.map((b) => b.id), isNot(contains(newId)));
    expect(count(), 'Five blessings since June 2024');
    expect(e.blessings.firstWhere((b) => b.id == 'surgery').title, 'Comfort before the operation');

    // ---- 8. delete all five, one by one ----
    for (var left = 5; left > 0; left--) {
      final before = caption();
      await tester.tap(find.byKey(const Key('read')));
      await wait(2400);
      expect(readTitle(), before);
      await deleteShown();
      expect(e.blessings.length, left - 1);
      expect(await store.count(), left - 1);
    }
    expect(count(), 'No blessings yet');
    expect(find.byKey(const Key('cap-title')), findsNothing);
    expect(find.byKey(const Key('read')), findsNothing);
    expect(find.byKey(const Key('new')), findsOneWidget);
    expect(countLine(e.blessings), 'No blessings yet');
    await wait(1500);
    // the first-run screen: no ruler, no arrows, no list button; one line and New blessing
    expect(find.byKey(const Key('ruler')), findsNothing);
    expect(find.byKey(const Key('older')), findsNothing);
    expect(find.byKey(const Key('list')), findsNothing);
    expect(find.text('When a blessing is recorded, its light appears here.'), findsOneWidget);
    await shot('11-empty');
    // and a recording can still be opened and closed
    await tester.tap(find.byKey(const Key('new')));
    await wait(2000);
    expect(tester.widget<RecordLayer>(find.byType(RecordLayer)).session.state, RecordState.ready);
    await tester.tap(find.byKey(const Key('rec-x')));
    await wait(2000);
    expect(stage('home'), isTrue);
    marker.deleteSync();
  });
}
