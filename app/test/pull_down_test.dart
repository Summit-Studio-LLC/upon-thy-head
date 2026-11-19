// The reading page's pull down to go home (2026-11-18): only a deliberate pull begun with the page
// at rest at its top goes back; a scroll, a fling or a short pull never does.
//
//   flutter test test/pull_down_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/read/read_screen.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/theme.dart';

import 'screen_reader_test.dart' show FakeShare, surgery;

const iPhone = Size(402, 874);

void main() {
  late int backs;
  setUp(() => backs = 0);

  Future<void> show(WidgetTester t, {Blessing? blessing, bool still = false}) async {
    t.view.physicalSize = iPhone * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MediaQuery(
      data: MediaQueryData(size: iPhone, devicePixelRatio: 3, padding: const EdgeInsets.only(top: 62, bottom: 34), viewPadding: const EdgeInsets.only(top: 62, bottom: 34), disableAnimations: still),
      child: CupertinoApp(
        localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        home: ColoredBox(
          color: Palette.lamplight.ground,
          child: ReadLayer(
            key: const Key('read'),
            palette: Palette.lamplight,
            blessing: blessing ?? surgery(),
            placement: const OverheadPlacement(),
            on: true,
            onBack: () => backs++,
            onReview: () {},
            onDelete: () async => false,
            share: FakeShare(),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
  }

  ReadLayerState state(WidgetTester t) => t.state<ReadLayerState>(find.byKey(const Key('read')));
  ScrollPosition scroll(WidgetTester t) => t.state<ScrollableState>(find.descendant(of: find.byKey(const Key('read-scroll')), matching: find.byType(Scrollable))).position;

  // the middle of the screen, on the words
  const middle = Offset(201, 600);

  testWidgets('a long pull from the top: the page follows with resistance, and letting go goes home', (t) async {
    await show(t);
    final g = await t.startGesture(middle);
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 12));
      await t.pump(const Duration(milliseconds: 16));
    }
    // 240 of finger, less the first two steps that crossed the slop, at 0.6: past the distance,
    // and the page itself has not scrolled
    expect(state(t).pulled, closeTo((240 - 24) * ReadLayer.pullGive, .5));
    expect(state(t).pulled, greaterThan(ReadLayer.pullHome));
    expect(scroll(t).pixels, 0);
    expect(backs, 0, reason: 'nothing until the finger lifts');
    await g.up();
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('a short slow pull settles back and nothing changes', (t) async {
    await show(t);
    await t.timedDragFrom(middle, const Offset(0, 150), const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(state(t).pulled, 0);
    expect(scroll(t).pixels, 0);
  });

  testWidgets('a short pull let go with a firm flick goes home', (t) async {
    await show(t);
    await t.flingFrom(middle, const Offset(0, 110), 1600);
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('a drag begun scrolled down that carries past the top stays', (t) async {
    await show(t);
    scroll(t).jumpTo(300);
    await t.pump(const Duration(seconds: 1));
    await t.timedDragFrom(const Offset(201, 200), const Offset(0, 640), const Duration(milliseconds: 1500));
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(state(t).pulled, 0);
    expect(scroll(t).pixels, 0, reason: 'it scrolled to the top and bounced, as before');
  });

  testWidgets('a fling from mid-page that reaches the top stays, and so does a pull at once after it', (t) async {
    await show(t);
    scroll(t).jumpTo(400);
    await t.pump(const Duration(seconds: 1));
    await t.flingFrom(const Offset(201, 300), const Offset(0, 250), 4000);
    // coasting into the top: a pull now is not from rest
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.timedDragFrom(middle, const Offset(0, 300), const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(scroll(t).pixels, 0);
  });

  testWidgets('a scroll up from the top is a scroll', (t) async {
    await show(t);
    await t.timedDragFrom(middle, const Offset(0, -300), const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(scroll(t).pixels, greaterThan(200));
  });

  testWidgets('a blessing shorter than the screen can be pulled away', (t) async {
    final short = surgery();
    short.rawText = short.firstText = 'Be at peace.';
    short.changes.clear();
    await show(t, blessing: short);
    // the page is always a little taller than the screen (its own minimum height); the words all fit
    expect(scroll(t).maxScrollExtent, lessThan(100));
    await t.timedDragFrom(middle, const Offset(0, 260), const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('nothing while a sheet is up', (t) async {
    await show(t);
    state(t).debugShare();
    await t.pump(const Duration(seconds: 1));
    await t.timedDragFrom(const Offset(201, 200), const Offset(0, 300), const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    expect(backs, 0);
  });

  testWidgets('Reduce Motion: the page does not follow, and a pull past the distance goes home', (t) async {
    await show(t, still: true);
    final g = await t.startGesture(middle);
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 12));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(state(t).pulled, 0);
    await g.up();
    await t.pump();
    expect(backs, 1);
  });
}
