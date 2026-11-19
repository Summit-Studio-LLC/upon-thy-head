// Home's liquid glass (package:liquid_glass_widgets): the capsule and the icon group, then the
// capsule's menu open with a family member in it. Screenshots, the simulator's own, taken on each
// SIMSHOT line into ../design/sim/glass/:
//
//   flutter drive -d <udid> --driver=test_driver/integration_test.dart \
//     --target=integration_test/glass_shot_test.dart   (with the SIMSHOT loop of tool/your_links_shot.sh)

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/person.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('home glass: the capsule, the icon group, the person menu', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(900);
      debugPrint('SIMSHOT $name');
      await wait(1500);
    }

    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    final store = await freshSeededStore();
    for (final p in await store.people()) {
      await store.removePerson(p.id);
    }
    await store.addPerson(Person(id: 'glass-emma', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.now().toUtc()));

    await tester.pumpWidget(glassScope(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock())));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await wait(2500);
    expect(find.byKey(const Key('head-buttons')), findsOneWidget);
    await shot('home-capsule-and-buttons');

    await tester.tap(find.byKey(const Key('sky-switch')));
    await wait(1200);
    expect(find.byKey(const Key('pull-down-p:glass-emma')), findsOneWidget);
    await shot('person-menu-open');

    await tester.tapAt(const Offset(200, 760));
    await wait(1200);
    expect(find.byKey(const Key('pull-down-me')), findsNothing);
  });
}
