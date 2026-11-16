// The sample "Comfort before surgery" on the changes screen with its last change selected, for
// comparing with design/prototype/shots/05-review-changes.png. Run by tool/changes_shot.sh.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the sample on the changes screen', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    final store = await freshSeededStore();
    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await wait(1500);
    await tester.tap(find.byKey(const Key('list')));
    await wait(1200);
    await tester.tap(find.byKey(const Key('row-surgery')));
    await wait(2600);
    final s = find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.byType(Scrollable)).first;
    final pos = tester.state<ScrollableState>(s).position;
    pos.jumpTo(pos.maxScrollExtent);
    await wait(600);
    await tester.tap(find.byKey(const Key('read-review-changes')));
    await wait(1800);
    await tester.tap(find.byKey(const Key('sheet-prev')));
    await wait(1400);
    debugPrint('SIMSHOT polish/16-sample-last-change');
    await wait(1500);
  });
}
