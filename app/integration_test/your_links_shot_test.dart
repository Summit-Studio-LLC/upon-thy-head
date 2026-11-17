// "Your links" (lib/share/your_links.dart) with one live link and one stopped: the Stop question,
// and the stopped link's row, in English and in Spanish. Nothing is sent: the links are written
// into the store as the share sheet would leave them. Run by tool/your_links_shot.sh, which takes
// the simulator's own screenshots into ../design/sim/link/.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/data/sent_link.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/strings.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final lang in [UiLanguage.english, UiLanguage.spanish]) {
    final code = lang == UiLanguage.english ? 'en' : 'es';
    testWidgets('your links, $code: the Stop question and a stopped link', (tester) async {
      Future<void> wait(int ms) async {
        final end = DateTime.now().add(Duration(milliseconds: ms));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> shot(String name) async {
        await wait(700);
        debugPrint('SIMSHOT $name');
        await wait(1500);
      }

      Strings.use(lang);
      final store = await freshSeededStore();
      // links left by other runs (tool/link_acceptance.sh) would push these two off the screen
      for (final l in await store.links()) {
        await store.removeLink(l.id);
      }
      final now = DateTime.now().toUtc();
      final all = await store.list();
      final surgery = all.firstWhere((b) => b.id == 'surgery');
      final other = all.firstWhere((b) => b.id != 'surgery');
      await store.addLink(SentLink(
          id: 'live-$code', blessingId: surgery.id, title: surgery.title,
          sent: now.subtract(const Duration(hours: 3)), expires: now.add(const Duration(days: 30))));
      await store.addLink(SentLink(
          id: 'stopped-$code', blessingId: other.id, title: other.title,
          sent: now.subtract(const Duration(days: 4)), expires: now.add(const Duration(days: 26)),
          stopped: now.subtract(const Duration(days: 1))));

      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
      final sky = find.byKey(const Key('sky'));
      for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(1500);
      await tester.tap(find.byKey(const Key('more')));
      await wait(1800);
      await tester.tap(find.byKey(const Key('settings-links')));
      await wait(1800);
      expect(find.byKey(Key('link-row-stopped-$code')), findsOneWidget);
      expect(find.byKey(Key('link-stop-stopped-$code')), findsNothing, reason: 'a stopped link has no Stop');
      await shot('$code-your-links-stopped-row');
      await tester.tap(find.byKey(Key('link-stop-live-$code')));
      await wait(1200);
      expect(find.byKey(const Key('stop-confirm')), findsOneWidget);
      expect(find.text(Strings.stopBody), findsOneWidget);
      await shot('$code-stop-question');
      await tester.tap(find.byKey(const Key('stop-cancel')));
      await wait(1200);
      expect(find.byKey(Key('link-stop-live-$code')), findsOneWidget, reason: 'Cancel stopped the link');
      Strings.use(UiLanguage.english);
    });
  }
}
