// Home's date bar and the family menu, looked at by eye (build 13's fixes, 2026-11-21): the five
// samples (a ring of about three years, Emma with two of them, so the menu's count lines name a
// month), then with one of June 2024 (three years), then one of 1998 too (about thirty years). At each: home,
// the menu open, and the menu dragged to its foot. The language and text size are the
// simulator's (set by the driving script); the screenshots are the simulator's own, on SIMSHOT
// lines.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/strings.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const prefix = String.fromEnvironment('PREFIX');

  testWidgets('home look', (t) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> shot(String name) async {
      await wait(900);
      debugPrint('SIMSHOT $prefix$name');
      await wait(1500);
    }

    Future<void> until(Finder f, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 20 && f.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    debugPrint('LANG ${Strings.language}');
    final store = await freshSeededStore();
    for (final p in await store.people()) {
      await store.removePerson(p.id);
    }
    await store.addPerson(Person(id: 'emma', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.now().toUtc()));
    final all = await store.list();
    for (final b in all.take(2)) {
      await store.update(b..personId = 'emma');
    }

    Future<void> launch() async {
      await t.pumpWidget(const SizedBox());
      await wait(400);
      final holder = unlockedLock();
      await t.pumpWidget(glassScope(UponThyHeadApp(store: store, stats: false, demo: false, lock: holder)));
      await until(find.byKey(const Key('sky')), seconds: 30);
      await wait(2500);
    }

    Future<void> menu(String name) async {
      await t.tap(find.byKey(const Key('sky-switch')).hitTestable().first);
      await wait(1600);
      await shot('$name-menu');
      // drag the menu up from its middle, to its foot
      final size = t.view.physicalSize / t.view.devicePixelRatio;
      await t.dragFrom(Offset(size.width / 2, size.height * .6), Offset(0, -size.height * .7));
      await wait(1200);
      await shot('$name-menu-foot');
      final manage = find.byKey(const Key('pull-down-manage')).hitTestable();
      debugPrint('MANAGE ${manage.evaluate().isEmpty ? 'NOT REACHABLE' : 'reachable'}');
      // close it: a tap at the very foot, outside the menu
      await t.tapAt(Offset(size.width / 2, size.height - 4));
      await wait(1200);
    }

    // about three years: the samples
    await launch();
    await shot('span3-home');
    await menu('span3');

    // a blessing of the year [year] beside them, for me
    final s = all.last;
    Future<void> add(int year, DatePrecision precision) => store.create(Blessing(
          id: newBlessingId(),
          title: s.title,
          from: s.from,
          utc: DateTime.utc(year, 6, 14, 18),
          utcOffset: s.utcOffset,
          place: s.place,
          rawText: s.rawText,
          firstText: s.firstText,
          draft: false,
          entered: true,
          precision: precision,
        ));

    // three years: one of June 2024 beside them
    await add(2024, DatePrecision.month);
    await launch();
    await shot('span3b-home');

    // about thirty: one of 1998
    await add(1998, DatePrecision.year);
    await launch();
    await shot('span30-home');
    await menu('span30');
    debugPrint('LOOK DONE');
  });
}
