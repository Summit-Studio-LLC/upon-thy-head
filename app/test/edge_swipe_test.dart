import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/edge_swipe.dart';
import 'package:upon_thy_head/widgets/sheet.dart';

void main() {
  late int backs;
  setUp(() => backs = 0);

  // a phone-sized screen, so a third of the width is a third of 400
  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget page({bool enabled = true, bool still = false, bool sheet = false, GestureDragUpdateCallback? ownDrag}) => MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [
            EdgeSwipeBack(
              key: const Key('swipe'),
              enabled: enabled,
              onBack: () => backs++,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: ownDrag,
                child: const SizedBox.expand(child: Center(child: Text('page'))),
              ),
            ),
            Sheet(palette: Palette.vigil, on: sheet, label: 'sheet', child: const SizedBox(height: 100)),
          ]),
        ),
      );

  double progress(WidgetTester t) => t.state<EdgeSwipeBackState>(find.byKey(const Key('swipe'))).progress;

  testWidgets('the page follows the finger one for one', (t) async {
    await phone(t);
    await t.pumpWidget(page());
    final g = await t.startGesture(const Offset(5, 400));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(70, 0));
    await t.pump();
    // the first move goes partly to winning the drag; after that it is one for one
    final before = t.getCenter(find.text('page')).dx;
    await g.moveBy(const Offset(40, 0));
    await t.pump();
    expect(t.getCenter(find.text('page')).dx - before, closeTo(40, .5));
    await g.up();
    await t.pumpAndSettle();
  });

  testWidgets('let go short of a third, slowly: springs back, stays', (t) async {
    await phone(t);
    await t.pumpWidget(page());
    await t.timedDragFrom(const Offset(5, 400), const Offset(100, 0), const Duration(milliseconds: 800));
    await t.pumpAndSettle();
    expect(progress(t), 0);
    expect(backs, 0);
  });

  testWidgets('let go past a third: goes back, once', (t) async {
    await phone(t);
    await t.pumpWidget(page());
    await t.timedDragFrom(const Offset(5, 400), const Offset(180, 0), const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('a short flick goes back', (t) async {
    await phone(t);
    await t.pumpWidget(page());
    await t.flingFrom(const Offset(5, 400), const Offset(60, 0), 800);
    await t.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('the release takes at most 350 ms, at most 100 with Reduce Motion', (t) async {
    await phone(t);
    for (final still in [false, true]) {
      backs = 0;
    await t.pumpWidget(page(still: still));
      final g = await t.startGesture(const Offset(5, 400));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(10, 0));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 200)); // stop the finger
      await g.up();
      await t.pump(); // the release's first frame: its clock starts here
      await t.pump(Duration(milliseconds: still ? 101 : 351));
      await t.pump();
      expect(backs, 1, reason: 'still: $still');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a drag that begins away from the edge is the page\'s own', (t) async {
    var own = 0.0;
    await phone(t);
    await t.pumpWidget(page(ownDrag: (d) => own += d.primaryDelta ?? 0));
    await t.timedDragFrom(const Offset(60, 400), const Offset(250, 0), const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(progress(t), 0);
    expect(own, greaterThan(100));
  });

  testWidgets('nothing while not in front, or while a sheet is up', (t) async {
    await phone(t);
    for (final w in [page(enabled: false), page(sheet: true)]) {
      await t.pumpWidget(w);
      await t.pumpAndSettle();
      await t.timedDragFrom(const Offset(5, 400), const Offset(300, 0), const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(backs, 0);
      expect(progress(t), 0);
    }
  });

  testWidgets('VoiceOver\'s two-finger scrub goes back', (t) async {
    final semantics = t.ensureSemantics();
    await phone(t);
    await t.pumpWidget(page());
    final node = t.getSemantics(find.byKey(const Key('swipe')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.dismiss), isTrue);
    t.binding.renderViews.first.owner!.semanticsOwner!.performAction(node.id, SemanticsAction.dismiss);
    await t.pump();
    expect(backs, 1);
    semantics.dispose();
  });
}
