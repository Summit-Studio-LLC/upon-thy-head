// Handing Emma's ring to her own phone (design/entry-and-rings, B1 rows 9–16), one quick look on
// the simulator: the sending sheet on Dad's phone, then — the phone emptied as if it were Emma's —
// the ring's link opened, the welcome and the first blessing to read. The link is made against the
// website running here (LINK_SERVICE), never the live service. Run by tool/hand_over_shot.sh, which
// takes the simulator's own screenshots into ../design/sim/handover/.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/share/link_crypto.dart';
import 'package:upon_thy_head/share/link_service.dart';
import 'package:upon_thy_head/share/links.dart';
import 'package:upon_thy_head/strings.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hand over: the sending sheet, then the ring arriving', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(Finder f, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 20 && f.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(f, findsWidgets);
    }

    Future<void> shot(String name) async {
      await wait(900);
      debugPrint('SIMSHOT $name');
      await wait(1500);
    }

    Strings.use(UiLanguage.english);
    final store = await freshSeededStore();
    for (final p in await store.people()) {
      await store.removePerson(p.id);
    }
    for (final l in await store.links()) {
      await store.removeLink(l.id);
    }
    // Emma's ring on Dad's phone: the five samples
    await store.addPerson(Person(id: 'emma', name: 'Emma'));
    for (final b in await store.list()) {
      await store.update(b..personId = 'emma');
    }

    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    await until(find.byKey(const Key('sky')));
    await wait(1500);
    await tester.tap(find.byKey(const Key('sky-switch')));
    await wait(1200);
    await tester.tap(find.text(Strings.manageFamily).first); // the menu's row (the page's title is built too)
    await wait(1200);
    await tester.tap(find.byKey(const Key('family-row-emma')));
    await wait(1200);
    await tester.tap(find.byKey(const Key('person-hand-over')));
    await until(find.byKey(const Key('hand-over-send')));
    await shot('01-sending-sheet');

    // the ring's link, made against the website here, as the Send button would
    final ring = [for (final b in await store.list()) b];
    final links = Links(store: store, crypto: const NativeLinkCrypto(), secrets: const NativeLinkCrypto(), service: HttpLinkService());
    final made = await links.makeRing('emma', ring, keptBy: 'Dad', title: 'Emma’s ring');
    expect(made, isA<Made>(), reason: '$made');

    // Emma's own phone: nothing on it yet
    await tester.pumpWidget(const SizedBox());
    await wait(500);
    final hers = await freshSeededStore(empty: true);
    for (final p in await hers.people()) {
      await hers.removePerson(p.id);
    }
    await tester.pumpWidget(UponThyHeadApp(store: hers, stats: false, demo: false, lock: unlockedLock()));
    await until(find.byKey(const Key('sky')));
    await wait(1500);
    // the link arriving as iOS hands it over (Share.swift's "incoming"), without the "Open in" alert;
    // the app then fetches it from the website here and unlocks it as any link
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'upon_thy_head/share', const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', {'link': (made as Made).url})), (_) {});
    await until(find.byKey(const Key('ring-arrival-title')), seconds: 40);
    await shot('02-ring-arrives');
    await tester.tap(find.byKey(const Key('ring-arrival-continue')));
    await wait(1200);
    await shot('03-reading-oldest-first');
    await tester.tap(find.byKey(const Key('ring-arrival-keep')));
    await until(find.byKey(const Key('kept-for-you')));
    await shot('04-kept-for-you-by');
  });
}
