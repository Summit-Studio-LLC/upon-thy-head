// The Milky Way zoomed all the way in (SkyEngine.minFov, 15 since the ring), with and without the soft copy.
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/zoom_test.dart
//
// Screenshots land in ../design/sim/zoom/. The -v3 shots are at fov 15 with
// the ring placement; the -v2 ones (fov 34, half-size soft copy) and the
// unsuffixed ones (quarter-size copy) are earlier runs, kept for comparison.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_painter.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('zoomed in: smooth dark sky', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
    await wait(1500);

    // where 04-pinched-in.png looked (beside the light in focus), and a dark patch near the galactic pole
    final spots = {
      'focus': (ra: e.blessings[4].ra + 2 * deg, dec: e.blessings[4].dec - 3 * deg),
      'pole': (ra: 190 * deg, dec: 24 * deg),
    };
    for (final MapEntry(key: name, value: at) in spots.entries) {
      e.pinch(SkyEngine.minFov, const Offset(200, 400)); // free the camera
      e.ra = at.ra;
      e.dec = at.dec;
      await wait(1500);
      expect(e.fov, closeTo(SkyEngine.minFov, .01));
      SkyPainter.softMilkyWay = false;
      await wait(300);
      await binding.takeScreenshot('zoom/$name-15-before-v3');
      SkyPainter.softMilkyWay = true;
      await wait(300);
      await binding.takeScreenshot('zoom/$name-15-after-v3');
    }
    // the home framing must not change
    e.zoomTo(90);
    e.lookAt(4, instant: true);
    await wait(800);
    SkyPainter.softMilkyWay = false;
    await wait(300);
    await binding.takeScreenshot('zoom/home-90-before-v3');
    SkyPainter.softMilkyWay = true;
    await wait(300);
    await binding.takeScreenshot('zoom/home-90-after-v3');
  });
}
