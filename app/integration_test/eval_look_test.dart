// The final evaluation's look (2026-11-20): one walk over the screens never seen by eye in Spanish,
// at the largest text, or on the iPad: home, the glass menu, entering a past blessing and its date
// sheet, Manage family and the hand-over sheet, a reading page, Settings down to About; then the
// lock over a reading page and over a family member's page. The language and text size are the
// simulator's (set by the driving script); the screenshots are the simulator's own, on SIMSHOT
// lines. REDUCE=true instead keeps an entered blessing with Reduce Motion on and marks the moment
// Done is pressed (FILM lines), for a film of the way home.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/strings.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const reduce = bool.fromEnvironment('REDUCE'), film = bool.fromEnvironment('FILM');

  testWidgets('evaluation look', (t) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(900);
      debugPrint('SIMSHOT $name');
      await wait(1500);
    }

    Future<void> until(Finder f, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 20 && f.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<bool> tap(String key, {int settle = 1400}) async {
      final f = find.byKey(Key(key));
      await until(f);
      if (f.evaluate().isEmpty) {
        debugPrint('MISSING $key');
        return false;
      }
      if (f.hitTestable().evaluate().isEmpty) {
        final scroll = find.ancestor(of: f.first, matching: find.byType(Scrollable));
        if (scroll.evaluate().isNotEmpty) {
          await t.scrollUntilVisible(f.first, 150, scrollable: scroll.first);
          await wait(400);
        }
      }
      if (f.hitTestable().evaluate().isEmpty) {
        debugPrint('NOT TAPPABLE $key');
        return false;
      }
      await t.tap(f.hitTestable().first);
      await wait(settle);
      return true;
    }

    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    debugPrint('LANG ${Strings.language}');
    if (reduce) {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    final store = await freshSeededStore();
    for (final p in await store.people()) {
      await store.removePerson(p.id);
    }
    await store.addPerson(Person(id: 'emma', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.now().toUtc()));
    final all = await store.list();
    for (final b in all.take(2)) {
      await store.update(b..personId = 'emma');
    }

    late AppLockHolder holder;
    Future<void> launch() async {
      await t.pumpWidget(const SizedBox());
      await wait(400);
      holder = AppLockHolder(unlockedLock());
      await t.pumpWidget(glassScope(UponThyHeadApp(store: store, stats: false, demo: false, lock: holder.lock)));
      await until(find.byKey(const Key('sky')), seconds: 30);
      await wait(2500);
    }

    if (reduce || film) {
      await launch();
      await tap('new', settle: 1800);
      await tap('enter-past', settle: 1800);
      await tap('review-words', settle: 500);
      final words = find.descendant(of: find.byKey(const Key('review-words')), matching: find.byType(EditableText));
      await t.enterText(words, 'A blessing entered, to see the way home.');
      await wait(800);
      await tap('review-given-row', settle: 1200);
      await tap('precision-year', settle: 800);
      await tap('date-done', settle: 1500);
      debugPrint('FILM start');
      await wait(1500);
      await tap('review-done', settle: 4000);
      debugPrint('FILM stop');
      await wait(500);
      await shot('reduce-after-done');
      return;
    }

    // home, and the glass menu
    await launch();
    await shot('01-home');
    await tap('sky-switch', settle: 1400);
    await shot('02-menu-open');

    // Manage family, Emma's page, the hand-over sheet
    await tap('pull-down-manage', settle: 1600);
    await shot('03-manage-family');
    await tap('family-row-emma', settle: 1400);
    await shot('04-person-page');
    if (await tap('person-hand-over', settle: 1600)) await shot('05-hand-over-sheet');
    // locked over the hand-over sheet / Emma's page
    holder.lock.lock();
    await wait(1500);
    await shot('06-locked-over-family');

    // a reading page
    await launch();
    await tap('read', settle: 1800);
    await shot('07-reading-top');
    final rs = find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.byType(Scrollable));
    if (rs.evaluate().isNotEmpty) {
      await t.drag(rs.first, const Offset(0, -600));
      await wait(1200);
      await shot('08-reading-scrolled');
    }
    holder.lock.lock();
    await wait(1500);
    await shot('09-locked-over-reading');

    // Settings down to About
    await launch();
    await tap('more', settle: 2000);
    await shot('10-settings-top');
    final ss = find.descendant(of: find.byKey(const Key('settings-scroll')), matching: find.byType(Scrollable));
    final sss = ss.evaluate().isNotEmpty ? ss.first : find.byKey(const Key('settings-scroll'));
    for (var i = 0; i < 6; i++) {
      await t.drag(sss, const Offset(0, -350));
      await wait(900);
      await shot('11-settings-down-$i');
      if (find.byKey(const Key('settings-credits')).hitTestable().evaluate().isNotEmpty && i > 0) break;
    }

    // entering a past blessing and its date sheet
    await launch();
    await tap('new', settle: 1800);
    await shot('12-recording-start');
    await tap('enter-past', settle: 1800);
    await shot('13-entry-page');
    await tap('review-given-row', settle: 1200);
    await shot('14-date-sheet');
    debugPrint('LOOK DONE');
  });
}

/// Holds the lock so the walk can lock the app as a minute away would.
class AppLockHolder {
  AppLockHolder(this.lock);
  final AppLock lock;
}
