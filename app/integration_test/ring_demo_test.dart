// Short films of the ring, recorded by tool/film.sh between DEMO START and DEMO END.
//
//   tool/film.sh integration_test/ring_demo_test.dart ../design/sim/ring/ring.mp4 --dart-define=DEMO=ring
//   tool/film.sh integration_test/ring_demo_test.dart ../design/sim/ring/slide.mp4 --dart-define=DEMO=slide
//
// ring:  the 120 test blessings; step back through a few with the arrow, then
//        pinch in slowly on a crowded stretch. About 20 seconds.
// slide: the five samples; delete the oldest, which moves the start of the
//        ring, so every light glides to its new place.
//
// Touches are device events, so no test pointer markers are painted.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

import 'support.dart';

const demo = String.fromEnvironment('DEMO', defaultValue: 'ring');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('ring demo: $demo', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    var pointer = 900;
    void send(PointerEvent e) => binding.handlePointerEventForSource(e, source: TestBindingEventSource.device);

    Future<void> tap(Key key) async {
      final c = tester.getCenter(find.byKey(key));
      final id = ++pointer;
      send(PointerDownEvent(pointer: id, position: c));
      await wait(80);
      send(PointerUpEvent(pointer: id, position: c));
      await tester.pump(const Duration(milliseconds: 16));
    }

    /// Two fingers about [c], [from] apart growing to [to] apart over [ms], eased.
    Future<void> pinch(Offset c, double from, double to, int ms) async {
      final a = ++pointer, b = ++pointer;
      const dir = Offset(.94, .34);
      Offset pa(double d) => c - dir * (d / 2);
      Offset pb(double d) => c + dir * (d / 2);
      send(PointerDownEvent(pointer: a, position: pa(from)));
      await wait(40);
      send(PointerDownEvent(pointer: b, position: pb(from)));
      await wait(40);
      var la = pa(from), lb = pb(from);
      final start = DateTime.now();
      while (true) {
        await tester.pump(const Duration(milliseconds: 16));
        final t = (DateTime.now().difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
        final d = from + (to - from) * Curves.easeInOut.transform(t);
        final na = pa(d), nb = pb(d);
        send(PointerMoveEvent(pointer: a, position: na, delta: na - la));
        send(PointerMoveEvent(pointer: b, position: nb, delta: nb - lb));
        la = na;
        lb = nb;
        if (t >= 1) break;
      }
      send(PointerUpEvent(pointer: b, position: lb));
      await wait(30);
      send(PointerUpEvent(pointer: a, position: la));
      await tester.pump(const Duration(milliseconds: 16));
    }

    binding.shouldPropagateDevicePointerEvents = true;
    try {
      await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(dense: demo == 'ring'), stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
      await wait(2500);

      if (demo == 'ring') {
        debugPrint('DEMO START');
        await wait(1500);
        for (var i = 0; i < 5; i++) {
          await tap(const Key('older'));
          await wait(1300);
        }
        await wait(1200);
        final p = e.points[e.focus];
        // pinch in about the light in focus, slowly, by about five times
        final c = Offset(p.x, p.y);
        await pinch(c, 60, 300, 4500);
        await wait(500);
        final q = e.points[e.focus];
        await pinch(Offset(q.x.clamp(120, 280), q.y), 70, 210, 4000);
        await wait(2500);
        debugPrint('RINGDEMO fov at the end ${e.fov.toStringAsFixed(1)}');
        debugPrint('DEMO END');
      } else {
        // read the oldest and delete it: the ring now starts at the next one
        await tap(const Key('older'));
        await wait(300);
        for (var i = 0; i < 4; i++) {
          await tap(const Key('older'));
          await wait(300);
        }
        await wait(3000);
        expect(e.focus, 0);
        // pull back so most of the lights are in view
        e.zoomTo(SkyEngine.maxFov);
        await wait(1500);
        final before = e.blessings[3].ra;
        debugPrint('DEMO START');
        await wait(1200);
        await tap(const Key('read'));
        await wait(2600);
        await tester.ensureVisible(find.byKey(const Key('read-delete')));
        await wait(600);
        await tap(const Key('read-delete'));
        await wait(1500);
        await tap(const Key('delete-confirm'));
        await wait(1200);
        e.zoomTo(SkyEngine.maxFov);
        await wait(3500);
        final moved = e.blessings.firstWhere((b) => b.id == 'surgery').ra - before;
        debugPrint('RINGDEMO slide: Comfort before surgery moved ${(moved.abs() * 180 / math.pi).toStringAsFixed(1)} deg of right ascension');
        expect(e.fov, greaterThan(SkyView.home.fov));
        debugPrint('DEMO END');
      }
      await wait(500);
    } finally {
      binding.shouldPropagateDevicePointerEvents = false;
    }
  });
}
