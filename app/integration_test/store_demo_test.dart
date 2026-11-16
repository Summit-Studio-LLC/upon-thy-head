// A short film of the store at work, for design/sim/store/store.mp4: open a
// blessing, scroll it, go back, open the list, scroll it, open a row, delete it.
// Run by tool/store_demo.sh, which records the simulator between the DEMO
// START and DEMO END lines.
//
// Touches are sent as device events, not test events, so the test binding
// does not paint its pointer markers (the green and red crosshair circles
// seen in record.mp4) over the film.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store demo', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    var pointer = 900;
    void send(PointerEvent e) => binding.handlePointerEventForSource(e, source: TestBindingEventSource.device);

    /// A finger: down at [from], moved to [to] over [ms] (eased), then up.
    Future<void> touch(Offset from, {Offset? to, int ms = 90}) async {
      final id = ++pointer;
      final dest = to ?? from;
      send(PointerDownEvent(pointer: id, position: from));
      final start = DateTime.now();
      var last = from;
      while (true) {
        await tester.pump(const Duration(milliseconds: 16));
        final t = (DateTime.now().difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
        final k = Curves.easeInOut.transform(t);
        final at = Offset.lerp(from, dest, k)!;
        if (at != last) send(PointerMoveEvent(pointer: id, position: at, delta: at - last));
        last = at;
        if (t >= 1) break;
      }
      send(PointerUpEvent(pointer: id, position: dest));
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> tap(Key key) => touch(tester.getCenter(find.byKey(key)));
    Future<void> swipe(Key key, double dy, {int ms = 900}) {
      final c = tester.getCenter(find.byKey(key));
      final from = Offset(c.dx, dy < 0 ? 640 : 300);
      return touch(from, to: from + Offset(0, dy), ms: ms);
    }

    binding.shouldPropagateDevicePointerEvents = true;
    try {
      await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
      await wait(2500);
      debugPrint('DEMO START');
      await wait(2000);

      // open a blessing from the caption's arrow and read it
      await tap(const Key('read'));
      await wait(3200);
      await swipe(const Key('read-scroll'), -360, ms: 1100);
      await wait(1800);
      await swipe(const Key('read-scroll'), -420, ms: 1100);
      await wait(2200);
      await tap(const Key('read-back'));
      await wait(3000);

      // the list, scrolled
      await tap(const Key('list'));
      await wait(2600);
      await swipe(const Key('list-scroll'), -260, ms: 1400);
      await wait(2400);

      // open a row and delete it
      final id = e.blessings[1].id; // When the baby came early
      await tap(Key('row-$id'));
      await wait(3200);
      await swipe(const Key('read-scroll'), -500, ms: 1000);
      await wait(1800);
      await tap(const Key('read-delete'));
      await wait(2200);
      await tap(const Key('delete-confirm'));
      await wait(4000);
      expect(e.blessings.length, 4);
      debugPrint('DEMO END');
      await wait(500);
    } finally {
      binding.shouldPropagateDevicePointerEvents = false;
    }
  });
}
