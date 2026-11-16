// The phone check page (PHONE_CHECK builds), opened from Settings as a person would, run to the end.
//
//   tool/phone_check_sim.sh   (builds with --dart-define=PHONE_CHECK=true and saves the screenshots)
//
// Every check must finish with an answer or a shown error, within its own limit; "Copy report" must
// put the whole report on the clipboard; the report is printed between the markers.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/check/check_page.dart';
import 'package:upon_thy_head/check/checks.dart';
import 'package:upon_thy_head/main.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('phone check: opens from Settings, every check answers, the report copies', (tester) async {
    expect(phoneCheck, isTrue, reason: 'build with --dart-define=PHONE_CHECK=true');
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(400);
      debugPrint('SIMSHOT phone-check/$name');
      await wait(1500);
    }

    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
    for (var i = 0; i < 600 && find.byKey(const Key('sky')).evaluate().isEmpty; i++) {
      await wait(50);
    }
    await wait(2500);
    await tester.tap(find.byKey(const Key('more')));
    await wait(1500);
    final open = find.byKey(const Key('settings-phone-check-open'));
    await tester.scrollUntilVisible(open, 200, scrollable: find.descendant(of: find.byKey(const Key('settings-scroll')), matching: find.byType(Scrollable)));
    await wait(600);
    await shot('01-settings-row');
    await tester.tap(open);
    await wait(1200);
    expect(find.byKey(const Key('check-title')), findsOneWidget);
    await shot('02-running');

    String state(int n) => tester.widget<Text>(find.byKey(Key('check-$n-state'))).data!;
    bool finished() => [for (var n = 1; n <= 10; n++) state(n)].every((s) => s != 'Waiting' && s != 'Checking…');
    var sawSky = false;
    final end = DateTime.now().add(const Duration(minutes: 12));
    while (!finished() && DateTime.now().isBefore(end)) {
      await wait(500);
      if (!sawSky && state(7) == 'Checking…' && find.byType(PhoneCheckPage).evaluate().isNotEmpty) {
        await wait(2500);
        sawSky = true;
        await shot('03-measuring-sky');
      }
    }
    expect(finished(), isTrue, reason: 'every check answers within its limit');
    for (var n = 1; n <= 10; n++) {
      debugPrint('check $n: ${state(n)}');
    }

    final scroll = find.descendant(of: find.byKey(const Key('check-scroll')), matching: find.byType(Scrollable));
    await shot('04-top');
    for (var i = 5; i <= 9; i++) {
      await tester.drag(scroll, const Offset(0, -560));
      await wait(900);
      await shot('0$i-scrolled');
    }
    await tester.scrollUntilVisible(find.byKey(const Key('check-copy')), 200, scrollable: scroll);
    await wait(500);
    await tester.tap(find.byKey(const Key('check-copy')));
    await wait(600);
    await shot('10-copied');

    final page = tester.state<PhoneCheckPageState>(find.byType(PhoneCheckPage));
    final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    expect(copied, page.report);
    for (final t in ['1. This phone', '2. Speech engines', '3. Writing the prepared recordings', '4. Permissions', '5. The microphone',
      '6. A cut-off recording', "7. The sky's speed", '8. The lock', '9. Location', '10. Storage']) {
      expect(copied, contains(t));
    }
    debugPrint('CLIPBOARD-BEGIN');
    for (final l in copied.split('\n')) {
      debugPrint('CB| $l');
    }
    debugPrint('CLIPBOARD-END');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
