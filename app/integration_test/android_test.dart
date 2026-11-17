// Android's acceptance, run by tool/android_tests.sh on the emulator: the five samples seeded,
// the sky and every page a person reaches without recording, Android's back, then a real kill and
// relaunch. A marker file in the app's documents folder says which part runs:
//
//   1. seeded: the home sky, the list, zoom in and out, the ruler, read a blessing to the end,
//      edit its title on the review page, back from a sheet, from reading and from Settings,
//      delete one with its confirmation, the recording screen (Android's stand-in), and back
//      on the home sky leaving the app
//   2. after the app was killed: four, the edit kept, the deleted one gone
//
// It runs on the iPhone simulator too, unchanged but for the stand-ins, so the two phones'
// screens can be laid side by side (tool/android_tests.sh --ios). Its checks read the engine
// and the store rather than the words, so it passes in Spanish as well as English.
//
// The script takes the device's own screenshot (status and gesture bars included) when the test
// prints DEVSHOT: ../design/sim/android/test/ (or ../design/sim/android/test-ios/).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/timeline.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Android: the seeded app, back, and a restart', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(300);
      debugPrint('DEVSHOT $name');
      await wait(1500);
    }

    /// The system's back (Android's gesture or button), as the engine delivers it.
    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await wait(2600);
    }

    final marker = File('${(await getApplicationDocumentsDirectory()).path}/android_test_phase');
    final phase = marker.existsSync() ? int.parse(marker.readAsStringSync().split(' ').first) : 1;
    debugPrint('ANDROID TEST PART $phase');

    late BlessingStore store;
    late SkyEngine e;
    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    String caption() => tester.widget<Text>(find.byKey(const Key('cap-title'))).data!;
    String readTitle() => tester.widget<Text>(find.byKey(const Key('read-title'))).data!;
    bool leavesApp() => tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first).canPop;

    Future<void> launch(BlessingStore s) async {
      store = s;
      await tester.pumpWidget(UponThyHeadApp(store: s, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sky, findsOneWidget, reason: 'the sky never loaded');
      e = tester.widget<SkyWidget>(sky).engine;
      await wait(1800);
    }

    if (phase == 2) {
      // ---- after the app was killed: everything still there ----
      final kept = marker.readAsStringSync().split(' ');
      final editedId = kept[1], deletedId = kept[2];
      await launch(SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath()));
      expect(e.blessings.length, 4);
      expect(await store.count(), 4);
      expect(e.blessings.map((b) => b.id), isNot(contains(deletedId)));
      expect(e.blessings.firstWhere((b) => b.id == editedId).title, 'Before the new work');
      expect(caption(), 'Before the new work', reason: 'opens on the newest, the edited one');
      await shot('20-after-restart');
      marker.deleteSync();
      return;
    }

    // ---- 1. seeded: the home sky ----
    await launch(await freshSeededStore());
    expect(e.blessings.length, 5);
    expect(e.focus, 4);
    final newest = e.blessings[4];
    expect(caption(), newest.title);
    expect(leavesApp(), isTrue, reason: 'back on the home sky should leave the app');
    await shot('01-home');

    // ---- the list, and back closes it ----
    await tester.tap(find.byKey(const Key('list')));
    await wait(1800);
    expect(stage('list'), isTrue);
    expect(find.byType(Timeline), findsOneWidget);
    expect(leavesApp(), isFalse);
    await shot('02-list');
    await back();
    expect(stage('list'), isFalse, reason: 'back did not close the list');
    expect(stage('home'), isTrue);

    // ---- zoom: pinch in and out around the light in focus ----
    final size = tester.getSize(find.byKey(const Key('sky')));
    final lp = e.points[e.focus];
    final pc = Offset(lp.x.clamp(160, size.width - 160), lp.y.clamp(200, size.height - 300));
    Future<void> pinch(double from, double to) async {
      final a = await tester.startGesture(pc + Offset(-from, -from * .3), pointer: 11);
      await tester.pump(const Duration(milliseconds: 16));
      final b = await tester.startGesture(pc + Offset(from, from * .3), pointer: 12);
      await tester.pump(const Duration(milliseconds: 16));
      const steps = 30;
      final da = Offset(-(to - from), -(to - from) * .3) / steps.toDouble();
      for (var i = 0; i < steps; i++) {
        await a.moveBy(da);
        await b.moveBy(-da);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await b.up();
      await a.up();
      await wait(900);
    }

    final fovStart = e.fov;
    await pinch(50, 140);
    expect(e.fov, lessThan(fovStart * .6), reason: 'pinching apart did not zoom in');
    await shot('03-zoomed-in');
    final fovIn = e.fov;
    await pinch(150, 40);
    expect(e.fov, greaterThan(math.min(fovIn * 2.5, 100)), reason: 'pinching together did not zoom out');
    await shot('04-zoomed-out');

    // ---- the ruler at January 2025: the second-oldest ----
    final ruler = tester.getRect(find.byKey(const Key('ruler')));
    final start = DateTime.utc(2024), end = DateTime.utc(DateTime.now().year + 1);
    final frac = DateTime.utc(2025, 1, 12).difference(start).inMinutes / end.difference(start).inMinutes;
    await tester.tapAt(Offset(ruler.left + frac * ruler.width, ruler.top + 10));
    await wait(3400);
    expect(e.focus, 1);
    expect(e.free, isFalse);
    expect(caption(), e.blessings[1].title);
    await shot('05-ruler');

    // ---- back to the newest, and read it to the end ----
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('newer')));
      await wait(2800);
    }
    expect(e.focus, 4);
    await tester.tap(find.byKey(const Key('read')));
    await wait(2600);
    expect(stage('read'), isTrue);
    expect(readTitle(), newest.title);
    expect(e.fov, closeTo(SkyView.read.fov, 1.5));
    expect(leavesApp(), isFalse);
    await shot('06-reading');
    await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -4000));
    await wait(1400);
    expect(find.byKey(const Key('read-delete')), findsOneWidget);
    expect(find.byKey(const Key('read-share')), findsWidgets);
    await shot('07-reading-end');

    // ---- back from reading: home ----
    await back();
    expect(stage('home'), isTrue, reason: 'back did not leave the reading page');
    expect(stage('read'), isFalse);
    expect(caption(), newest.title);

    // ---- edit its title on the review page ----
    await tester.tap(find.byKey(const Key('read')));
    await wait(2600);
    await tester.tap(find.byKey(const Key('read-edit')));
    await wait(2600);
    expect(stage('review'), isTrue);
    await tester.tap(find.byKey(const Key('review-title')));
    await wait(1500);
    await tester.enterText(find.byKey(const Key('review-title')), 'Before the new work');
    await wait(800);
    // the field being typed in is on screen, above the keyboard
    final field = tester.getRect(find.byKey(const Key('review-title')));
    final view = tester.view;
    final visibleBottom = view.physicalSize.height / view.devicePixelRatio - view.viewInsets.bottom / view.devicePixelRatio;
    expect(field.top, greaterThanOrEqualTo(0));
    expect(field.bottom, lessThanOrEqualTo(visibleBottom), reason: 'the keyboard covers the title being typed');
    await shot('08-review-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(800);
    await tester.tap(find.byKey(const Key('review-done')));
    await wait(2600);
    expect(stage('read'), isTrue);
    expect(readTitle(), 'Before the new work');
    expect((await store.get(newest.id))!.title, 'Before the new work');

    // ---- a sheet: back closes the delete question and stays on the page ----
    await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -4000));
    await wait(1400);
    await tester.tap(find.byKey(const Key('read-delete')));
    await wait(900);
    expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
    await shot('09-delete-sheet');
    await back();
    expect(find.byKey(const Key('delete-confirm')).hitTestable(), findsNothing, reason: 'back did not close the sheet');
    expect(stage('read'), isTrue, reason: 'back closed the page as well as the sheet');
    expect(e.blessings.length, 5);
    await back();
    expect(stage('home'), isTrue);

    // ---- delete one with its confirmation: the one before ----
    await tester.tap(find.byKey(const Key('older')));
    await wait(3000);
    final doomed = e.blessings[e.focus];
    await tester.tap(find.byKey(const Key('read')));
    await wait(2600);
    expect(readTitle(), doomed.title);
    await tester.drag(find.byKey(const Key('read-scroll')), const Offset(0, -4000));
    await wait(1400);
    await tester.tap(find.byKey(const Key('read-delete')));
    await wait(900);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await wait(2800);
    expect(stage('home'), isTrue);
    expect(e.blessings.length, 4);
    expect(await store.get(doomed.id), isNull);
    await shot('10-four');

    // ---- Settings, and back ----
    await tester.tap(find.byKey(const Key('more')));
    await wait(2200);
    expect(stage('settings'), isTrue);
    expect(find.byKey(const Key('settings-use-location')), findsOneWidget);
    await shot('11-settings');
    await back();
    expect(stage('settings'), isFalse, reason: 'back did not leave Settings');
    expect(stage('home'), isTrue);

    // ---- the recording screen: back closes it, and nothing is recorded ----
    await tester.tap(find.byKey(const Key('new')));
    await wait(2400);
    expect(stage('record'), isTrue);
    final session = tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    // nothing is begun here: recording itself is proven by integration_test/android_record_test.dart
    expect(session.live, isFalse);
    await shot('12-record');
    await back();
    expect(stage('record'), isFalse, reason: 'back did not close the recording screen');
    expect(stage('home'), isTrue);
    expect(e.blessings.length, 4, reason: 'the recording screen changed the blessings');
    expect(leavesApp(), isTrue);

    marker.writeAsStringSync('2 ${newest.id} ${doomed.id}');
  });
}
