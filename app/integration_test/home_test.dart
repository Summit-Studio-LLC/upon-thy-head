// Drives the real app on a device or simulator:
//
//   flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/home_test.dart
//
// Screenshots land in ../design/sim/ (see test_driver/integration_test.dart).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('home: chevron, drag, pinch in, pinch out, ruler', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(200);
      await binding.takeScreenshot(name);
    }

    String caption() => tester.widget<Text>(find.byKey(const Key('cap-title'))).data!;

    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));

    // wait for the stars, the Milky Way and the shaders to load
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sky, findsOneWidget, reason: 'the sky never loaded');
    final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
    await wait(1200);
    // opens on the newest
    expect(e.focus, 4);
    expect(caption(), 'Before the new job');
    expect(find.text('Five blessings since June 2024'), findsOneWidget);
    await shot('01-home-test'); // 01-home.png itself is a simctl screenshot with the status bar

    // ---- earlier chevron: turn to the one before with the eased glide ----
    final ra0 = e.ra;
    await tester.tap(find.byKey(const Key('older')));
    await wait(3200);
    expect(e.focus, 3);
    expect(caption(), 'Comfort before surgery');
    expect(e.ra, isNot(closeTo(ra0, 1e-3)), reason: 'the camera did not turn');
    expect(e.free, isFalse);
    await shot('02-older');

    // ---- one-finger drag across the sky ----
    final size = tester.getSize(sky);
    final c = Offset(size.width / 2, size.height * .42);
    final raBeforeDrag = e.ra, decBeforeDrag = e.dec;
    final drag = await tester.startGesture(c);
    for (var i = 0; i < 14; i++) {
      await drag.moveBy(const Offset(-5, 2));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await wait(1500);
    expect(e.free, isTrue);
    expect((e.ra - raBeforeDrag).abs() + (e.dec - decBeforeDrag).abs(), greaterThan(.05), reason: 'the drag did not turn the sky');
    await shot('03-dragged');

    // ---- pinch in (fingers apart): zoom in, tracking the fingers ----
    // pinch around the light in focus, as a person would to look closer at it
    final lp = e.points[e.focus];
    final pc = Offset(lp.x.clamp(160, size.width - 160), lp.y.clamp(200, size.height - 300));
    Future<void> pinch(double from, double to) async {
      final c = pc;
      final a = await tester.startGesture(c + Offset(-from, -from * .3), pointer: 11);
      await tester.pump(const Duration(milliseconds: 16));
      await a.moveBy(const Offset(-6, 0)); // first finger already moving before the second lands
      await tester.pump(const Duration(milliseconds: 16));
      final raBefore = e.ra, decBefore = e.dec, fovBefore = e.fov;
      final b = await tester.startGesture(c + Offset(from, from * .3), pointer: 12);
      await tester.pump(const Duration(milliseconds: 16));
      // a second finger landing must not move or zoom the sky by itself
      expect(e.fov, closeTo(fovBefore, .01), reason: 'zoom jumped when the second finger landed');
      expect((e.ra - raBefore).abs() + (e.dec - decBefore).abs(), lessThan(1e-3), reason: 'sky jumped when the second finger landed');
      const steps = 30;
      final da = Offset(-(to - from), -(to - from) * .3) / steps.toDouble();
      for (var i = 0; i < steps; i++) {
        await a.moveBy(da);
        await b.moveBy(-da);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final fovHeld = e.fov, raHeld = e.ra, decHeld = e.dec;
      await b.up();
      await tester.pump(const Duration(milliseconds: 16));
      await a.moveBy(const Offset(1, 0)); // the remaining finger keeps touching
      await tester.pump(const Duration(milliseconds: 16));
      expect(e.fov, closeTo(fovHeld, .01), reason: 'zoom jumped when a finger lifted');
      expect((e.ra - raHeld).abs() + (e.dec - decHeld).abs(), lessThan(.01), reason: 'sky jumped when a finger lifted');
      await a.up();
    }

    final fovStart = e.fov;
    await pinch(50, 140);
    await wait(800);
    expect(e.fov, lessThan(fovStart * .6), reason: 'pinching apart did not zoom in');
    expect(e.fov, greaterThanOrEqualTo(SkyEngine.minFov));
    await shot('04-pinched-in');

    final fovIn = e.fov;
    await pinch(150, 40);
    await wait(800);
    expect(e.fov, greaterThan(math.min(fovIn * 2.5, 100)), reason: 'pinching together did not zoom out');
    expect(e.fov, lessThanOrEqualTo(SkyEngine.maxFov));
    await shot('05-pinched-out');

    // ---- touch the ruler at January 2025: turn to "When the baby came early" ----
    final ruler = tester.getRect(find.byKey(const Key('ruler')));
    final start = DateTime.utc(2024), end = DateTime.utc(DateTime.now().year + 1);
    final jan25 = DateTime.utc(2025, 1, 12);
    final frac = jan25.difference(start).inMinutes / end.difference(start).inMinutes;
    await tester.tapAt(Offset(ruler.left + frac * ruler.width, ruler.top + 10));
    await wait(3400);
    expect(e.focus, 1);
    expect(caption(), 'When the baby came early');
    expect(e.free, isFalse);
    final b = e.blessings[1];
    var d = (b.ra - e.ra) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    expect(d.abs() + (b.dec - e.dec).abs(), lessThan(1e-3), reason: 'the camera did not arrive at the picked blessing');
    expect(countLine(e.blessings), 'Five blessings since June 2024');
    await shot('06-ruler');
  });
}
