// With Reduce Motion on, the constellations are shown complete and still.
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/reduce_motion_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('reduce motion: figures complete and still', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final SkyEngine e = tester.widget<SkyWidget>(sky).engine;
    await wait(1000);
    expect(e.reduceMotion, isTrue);
    await tester.tap(find.byKey(const Key('new')));
    await wait(1500);
    await tester.tap(find.byKey(const Key('begin')));
    await wait(5000);
    expect(e.show!.plans, isNotEmpty);
    await binding.takeScreenshot('record/reduce-motion-a');
    await wait(3000);
    await binding.takeScreenshot('record/reduce-motion-b');
  });
}
