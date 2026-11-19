// The reading page's pull down to go home (2026-11-18), seen once on the simulator: a pull from the
// top held mid-way, then let go past the distance, back on the sky. SIMSHOT lines are screenshotted
// by the runner (design/sim/pull-down/):
//
//   flutter drive -d <udid> --driver=test_driver/integration_test.dart --target=integration_test/pull_down_shot_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/read/read_screen.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('pull down from the top of a blessing goes home', timeout: const Timeout(Duration(minutes: 3)), (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;
    final store = await freshSeededStore();
    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await wait(2500);
    await tester.tap(find.byKey(const Key('read')));
    await wait(1600);
    expect(stage('read'), isTrue);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final g = await tester.startGesture(Offset(size.width / 2, size.height * .55));
    // about 190 points of finger: the page has moved about 100, short of the 120 that goes home
    for (var i = 0; i < 24; i++) {
      await g.moveBy(const Offset(0, 8));
      await wait(20);
    }
    final pulled = tester.state<ReadLayerState>(find.byType(ReadLayer)).pulled;
    debugPrint('PULLED ${pulled.toStringAsFixed(0)}');
    debugPrint('SIMSHOT pull-down/01-mid-pull');
    await wait(2500);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 8));
      await wait(20);
    }
    await wait(200);
    await g.up();
    await wait(1500);
    expect(stage('read'), isFalse, reason: 'let go past the distance: home');
    debugPrint('SIMSHOT pull-down/02-after-letting-go');
    await wait(2500);
  });
}
