// The ring: the timeline bent round one circle of sky (lib/sky/placement.dart).
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/ring_test.dart
//
// Screenshots land in ../design/sim/ring/. Prints `RING ...` lines with what
// was measured (lights and labels on screen at each zoom).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/sky/sky_painter.dart';
import 'package:upon_thy_head/sky/sky_view.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late WidgetTester t;
  Future<void> wait(int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> shot(String name) async {
    await wait(200);
    await binding.takeScreenshot('ring/$name');
  }

  Future<SkyEngine> launch({bool dense = false, bool empty = false}) async {
    await t.pumpWidget(UponThyHeadApp(store: await freshSeededStore(dense: dense, empty: empty), stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(sky, findsOneWidget, reason: 'the sky never loaded');
    final e = t.widget<SkyWidget>(sky).engine;
    await wait(1500);
    return e;
  }

  String caption() => t.widget<Text>(find.byKey(const Key('cap-title'))).data!;
  bool stage(String name) => t.widget<Fade>(find.byKey(Key('stage-$name'))).on;

  /// Lights on screen now, and date labels drawn; and no two labels touching.
  ({int lights, int dates, int names}) census(SkyEngine e, String what) {
    final size = e.size;
    var lights = 0;
    for (final p in e.points) {
      if (p.z > 0 && p.x >= 0 && p.x <= size.width && p.y >= 0 && p.y <= size.height) lights++;
    }
    final labels = SkyPainter.debugLabels;
    for (var i = 0; i < labels.length; i++) {
      for (var j = i + 1; j < labels.length; j++) {
        expect(labels[i].box.overlaps(labels[j].box), isFalse, reason: '$what: labels touch: ${labels[i].box} ${labels[j].box}');
      }
    }
    final r = (lights: lights, dates: labels.where((l) => l.date).length, names: labels.where((l) => !l.date).length);
    debugPrint('RING ${DateTime.now().toIso8601String().substring(11, 19)} $what fov=${e.fov.toStringAsFixed(1)} lights=${r.lights} dates=${r.dates} names=${r.names} cut-so-far=${SkyPainter.debugCut}');
    return r;
  }

  /// Pinch to [fov] about the light in focus, over [ms], checking every frame that no labels touch.
  Future<int> zoomTo(SkyEngine e, double fov, {int ms = 2500, String what = 'zoom'}) async {
    final from = e.goalFov, start = DateTime.now();
    var worst = 0;
    while (true) {
      final u = (DateTime.now().difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
      final p = e.points[e.focus];
      e.pinch(math.exp(math.log(from) + (math.log(fov) - math.log(from)) * u), Offset(p.x, p.y));
      await t.pump(const Duration(milliseconds: 16));
      final labels = SkyPainter.debugLabels;
      for (var i = 0; i < labels.length; i++) {
        for (var j = i + 1; j < labels.length; j++) {
          if (labels[i].box.overlaps(labels[j].box)) worst++;
        }
      }
      if (u >= 1) break;
    }
    expect(worst, 0, reason: '$what: labels touched in $worst frame-pairs while zooming');
    return worst;
  }

  testWidgets('five: newest in focus, later to the right, older arrow, record one', (tester) async {
    t = tester;
    final e = await launch();
    expect(e.blessings.length, 5);
    expect(e.focus, 4, reason: 'opens on the newest');
    expect(caption(), 'Before the new job');
    // later runs to the right on screen, measured where the lights land
    for (var i = 1; i < 5; i++) {
      final a = e.points[i - 1], b = e.points[i];
      if (a.z > 0 && b.z > 0 && a.x > 0 && b.x < e.size.width) expect(b.x, greaterThan(a.x), reason: 'blessing $i is not right of ${i - 1}');
    }
    // the ring grows a fixed number of degrees a year from June 2024 to Oct 2026
    final start = zenith(e.blessings.first.utc, e.blessings.first.place).ra;
    final along = ((start - e.blessings[4].ra) % tau + tau) % tau / deg;
    debugPrint('RING five: newest is ${along.toStringAsFixed(1)} deg along; right of older on screen');
    expect(along, closeTo(RingPlacement.perYear * (DateTime.utc(2026, 10, 5, 1, 40).difference(DateTime.utc(2024, 6, 3, 5, 30)).inMinutes / (365.2425 * 1440)), .01));
    census(e, 'five-open');
    await shot('01-five');

    // zoomed all the way out
    await zoomTo(e, SkyEngine.maxFov, ms: 1500, what: 'five-out');
    await wait(1200);
    final wide = census(e, 'five-wide');
    debugPrint('RING five-wide: ${wide.lights} of 5 lights on screen');
    await shot('02-five-wide');

    // back, then one older with the arrow
    e.zoomTo(SkyView.home.fov);
    e.lookAt(e.focus, instant: true);
    await wait(600);
    await tester.tap(find.byKey(const Key('older')));
    await wait(3200);
    expect(e.focus, 3);
    expect(caption(), 'Comfort before surgery');
    census(e, 'five-older');
    await shot('03-older');

    // record a new one through the real flow
    final before = [for (final b in e.blessings) b.ra];
    await tester.tap(find.byKey(const Key('new')));
    await wait(2600);
    final draft = t.widget<RecordLayer>(find.byType(RecordLayer)).session.draft!;
    final ends = RingPlacement.angles(e.blessings.take(5).toList(), DateTime.now()).end;
    final draftAlong = ((start - draft.ra) % tau + tau) % tau / deg;
    expect(draftAlong, closeTo(ends, .01), reason: 'the draft is not at the end of the line');
    expect((e.ra - draft.ra).abs(), lessThan(1e-3), reason: 'the recording screen is not looking at the end of the line');
    await tester.tap(find.byKey(const Key('begin')));
    final session = tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    while (session.elapsed < 11) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
    await wait(1100);
    await g.up();
    await wait(2600);
    expect(stage('after'), isTrue);
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(3000);
    expect(stage('home'), isTrue);
    expect(e.blessings.length, 6);
    expect(e.focus, 5);
    expect(caption(), 'Blessing');
    var moved = 0.0;
    for (var i = 0; i < 5; i++) {
      moved = math.max(moved, (e.blessings[i].ra - before[i]).abs());
    }
    debugPrint('RING recorded: the five moved at most ${(moved / deg).toStringAsFixed(6)} deg');
    expect(moved, lessThan(1e-6), reason: 'the ring is not full; nothing should slide');
    census(e, 'five-recorded');
    await shot('04-recorded');
  });

  testWidgets('dense: labels thin and return without touching as the view zooms', (tester) async {
    t = tester;
    final e = await launch(dense: true);
    expect(e.blessings.length, 120);
    expect(e.focus, 119);
    // step back to a crowded stretch with the arrow, as a person would
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('older')));
      await wait(700);
    }
    await wait(2600);
    final open = census(e, 'dense-open');
    await shot('05-dense');
    await zoomTo(e, 40, what: 'dense-in');
    await wait(1200);
    final mid = census(e, 'dense-40');
    await shot('06-dense-zoomed');
    await zoomTo(e, SkyEngine.minFov, what: 'dense-deepest');
    await wait(1200);
    final deep = census(e, 'dense-deepest');
    // neighbours' spacing at the deepest zoom, around the one in focus
    final f = e.focus, p = e.points;
    final gaps = [
      for (var i = math.max(1, f - 6); i <= math.min(e.blessings.length - 1, f + 6); i++) (Offset(p[i].x, p[i].y) - Offset(p[i - 1].x, p[i - 1].y)).distance,
    ];
    debugPrint('RING dense-deepest neighbour gaps (pt): ${gaps.map((g) => g.round()).join(' ')}');
    await shot('07-dense-deepest');
    expect(open.dates, lessThan(open.lights), reason: 'at the opening zoom some dates should be held back');
    // and back out: labels thin again, never touching
    await zoomTo(e, SkyView.home.fov, what: 'dense-out');
    await wait(1200);
    final back = census(e, 'dense-back');
    debugPrint('RING dense: dates cut without a fade during all the zooms: ${SkyPainter.debugCut}');
    expect(SkyPainter.debugCut, 0, reason: 'a date popped instead of fading');
    debugPrint('RING dense summary: open ${open.lights}/${open.dates}, 40 ${mid.lights}/${mid.dates}, '
        'deepest ${deep.lights}/${deep.dates}, back ${back.lights}/${back.dates} (lights/dates)');
  });

  testWidgets('first run: no blessings', (tester) async {
    t = tester;
    final e = await launch(empty: true);
    expect(e.blessings, isEmpty);
    expect(find.byKey(const Key('ruler')), findsNothing);
    expect(find.byKey(const Key('older')), findsNothing);
    expect(find.byKey(const Key('newer')), findsNothing);
    expect(find.byKey(const Key('list')), findsNothing);
    expect(find.text('When a blessing is recorded, a light appears here.'), findsOneWidget);
    expect(find.byKey(const Key('new')), findsOneWidget);
    expect(find.text('No blessings yet'), findsOneWidget);
    await wait(800);
    await shot('08-first-run');
  });

  testWidgets('recording: a figure reaching the ring stays hidden under it', (tester) async {
    t = tester;
    final e = await launch();
    await tester.tap(find.byKey(const Key('new')));
    await wait(2600);
    await tester.tap(find.byKey(const Key('begin')));
    await wait(1500);
    final size = e.size, h = size.height;
    final ring = tester.getRect(find.byKey(const Key('hold')));
    // find a look point where a picked figure has a star inside the ring's box
    final show = e.show!;
    final dec = e.dec;
    final probe = Projected();
    String? figure;
    for (var k = 0; k < 72 && figure == null; k++) {
      final ra = k * 5 * deg;
      show.start(e, ra, dec, SkyView.record, size);
      e.withCamera(ra, dec, SkyView.record.fov, SkyView.record.cy, size, () {
        for (final pl in show.plans) {
          for (final s in pl.f.segs) {
            e.project(s.b, probe);
            final pb = Offset(probe.x, probe.y);
            e.project(s.a, probe);
            if (probe.z > .1 && (ring.inflate(10).contains(pb) || ring.inflate(10).contains(Offset(probe.x, probe.y)))) {
              figure = '${pl.f.id} at ra ${k * 5}';
              // put that figure in its rest, fully drawn
              show.t0 = e.clock - (pl.t + pl.d + 1);
              return;
            }
          }
        }
      });
      if (figure != null) e.lookToward(ra, dec, instant: true);
    }
    expect(figure, isNotNull, reason: 'no figure reaches the ring anywhere on this circle');
    debugPrint('RING figure under the ring: $figure; ring box $ring of height $h');
    await wait(2500);
    await shot('09-ring-under-figures');
    SkyPainter.fadeFigures = false;
    await wait(300);
    await shot('09b-same-without-fade');
    SkyPainter.fadeFigures = true;
    await wait(300);
  });
}
