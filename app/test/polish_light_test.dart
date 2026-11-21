// The light over the words while polish works (review/polish_light.dart): the piece with the model
// is reported in order; every ticker stops when polish finishes, is cancelled, or the page is
// left; Reduce Motion moves nothing; and polish by the rules alone shows no waiting at all, only
// the glint where its changes landed.
//
//   flutter test test/polish_light_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/polish/model.dart';
import 'package:upon_thy_head/polish/polish.dart';
import 'package:upon_thy_head/review/polish_light.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';

import '../integration_test/stand_in_model.dart';
import 'screen_reader_test.dart' show show, FakePlayer, p;

Blessing long() => Blessing(
      id: 'l',
      title: 'Blessing',
      from: 'Dad',
      utc: DateTime.utc(2026, 11, 1),
      utcOffset: Duration.zero,
      place: const Place(40, -111),
      rawText: walkBlessing,
      language: 'en',
    );

class _Page extends StatefulWidget {
  const _Page({super.key, required this.b, this.still = false, this.onChanges});
  final Blessing b;
  final bool still;
  final VoidCallback? onChanges;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  bool on = true, mounted_ = true;
  void close() => setState(() => on = false);
  void remove() => setState(() => mounted_ = false);
  @override
  Widget build(BuildContext context) => !mounted_
      ? const SizedBox()
      : MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: widget.still),
          child: ReviewLayer(
            palette: p,
            blessing: widget.b,
            on: on,
            player: FakePlayer(),
            onSave: () async {},
            onBack: () {},
            onFinish: () {},
            onChanges: widget.onChanges,
          ),
        );
}

PolishLightState light(WidgetTester t) => t.state<PolishLightState>(find.byKey(const Key('review-light')));
/// "Polish the words", brought into view as a person would scroll to it.
Future<void> press(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('review-polish')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('review-polish')));
}

PolishLight lightWidget(WidgetTester t) => t.widget<PolishLight>(find.byKey(const Key('review-light')));

void main() {
  tearDown(() => phoneModel = const NoModel());

  test('the piece with the model is reported in order, then the end', () async {
    final b = long();
    final heard = <int>[];
    List<TextRange>? cut;
    final n = await Polish.runWithModel(b, model: StandInModel(delay: Duration.zero), onPiece: (i, pieces) {
      heard.add(i);
      cut ??= pieces;
      expect(identical(cut, pieces), isTrue, reason: 'the same pieces every time');
    });
    expect(cut, hasLength(3), reason: 'the walk blessing is three pieces long');
    expect(heard, [0, 1, 2, 3]);
    for (final r in cut!) {
      expect(walkBlessing.substring(r.start, r.end), ModelSource.pieces(walkBlessing)[cut!.indexOf(r)].text);
    }
    // the stand-in's mends get through the check in every piece
    final fromModel = b.changes.where((c) => c.source == ModelSource.name).toList();
    for (final r in cut!) {
      expect(fromModel.where((c) => c.start >= r.start && c.end <= r.end), isNotEmpty);
    }
    expect(b.polishedText, contains('their home'));
    expect(b.polishedText, contains('ahead.\n\nI bless you'));
    expect(n, b.changes.length);
  });

  test('no report after a cancel, and none without a model', () async {
    final work = PolishWork();
    final heard = <int>[];
    final f = Polish.runWithModel(long(), model: StandInModel(delay: const Duration(milliseconds: 50)), work: work, onPiece: (i, _) => heard.add(i));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    work.cancel();
    expect(await f, isNull);
    expect(heard, [0]);
    heard.clear();
    await Polish.runWithModel(long(), model: StandInModel(isReady: false), onPiece: (i, _) => heard.add(i));
    expect(heard, isEmpty);
  });

  testWidgets('pressed: the band on piece one, then two, then three; the glint; then every ticker stops', (t) async {
    phoneModel = StandInModel();
    final b = long();
    var opened = 0;
    await show(t, _Page(b: b, onChanges: () => opened++));
    expect(light(t).animating, isFalse);
    await press(t);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('review-polishing-light')), findsOneWidget);
    expect(t.state<BreathingLightState>(find.byKey(const Key('review-polishing-light'))).breathing, isTrue);
    final seen = <int>[];
    for (var i = 0; i < 70 && lightWidget(t).at < 3; i++) {
      final at = lightWidget(t).at;
      if (at >= 0 && (seen.isEmpty || seen.last != at)) {
        seen.add(at);
        expect(light(t).bandMoving, isTrue, reason: 'the band moves over piece $at');
      }
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(seen, [0, 1, 2]);
    await t.pump();
    // finished: the row as always, the changed words glinting, the band gone
    expect(find.byKey(const Key('review-polished')), findsOneWidget);
    expect(find.byKey(const Key('review-polishing-light')), findsNothing);
    expect(lightWidget(t).glints, isNotEmpty);
    expect(light(t).bandMoving, isFalse);
    expect(opened, 0, reason: 'the changes screen waits for the glint');
    await t.pump(ReviewLayerState.glintTime + const Duration(milliseconds: 50));
    expect(opened, 1);
    await t.pump(const Duration(seconds: 2));
    expect(light(t).animating, isFalse);
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'nothing left running');
  });

  testWidgets('leaving while it works stops every ticker at once', (t) async {
    final model = phoneModel = StandInModel();
    final key = GlobalKey<_PageState>();
    await show(t, _Page(key: key, b: long()));
    await press(t);
    await t.pump(const Duration(milliseconds: 2500));
    expect(lightWidget(t).at, 1);
    expect(light(t).bandMoving, isTrue);
    key.currentState!.close();
    await t.pump();
    expect(model.cancelled, isNotEmpty);
    expect(light(t).animating, isFalse);
    expect(lightWidget(t).pieces, isEmpty);
    await t.pump(const Duration(seconds: 3));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the page taken away while it works: no ticker outlives it', (t) async {
    phoneModel = StandInModel();
    final key = GlobalKey<_PageState>();
    await show(t, _Page(key: key, b: long()));
    await press(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(light(t).bandMoving, isTrue);
    key.currentState!.remove();
    await t.pump();
    // a ticker left running at dispose fails the test by itself; let the stand-in's timers run out
    await t.pump(const Duration(seconds: 8));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Reduce Motion: no moving band and no breathing; a steady tint, and the glint a fade', (t) async {
    phoneModel = StandInModel();
    // the phone's own setting, as well as the page's: Flutter shortens animations by it
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var opened = 0;
    await show(t, _Page(b: long(), still: true, onChanges: () => opened++));
    await press(t);
    await t.pump(const Duration(milliseconds: 100));
    expect(lightWidget(t).at, 0);
    expect(light(t).bandMoving, isFalse);
    expect(t.state<BreathingLightState>(find.byKey(const Key('review-polishing-light'))).breathing, isFalse);
    for (var i = 0; i < 70 && lightWidget(t).at < 3; i++) {
      expect(light(t).bandMoving, isFalse);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(lightWidget(t).at, 3);
    // the changes still fade in, at their own pace
    await t.pump(const Duration(milliseconds: 400));
    expect(lightWidget(t).glints, isNotEmpty);
    expect(light(t).animating, isTrue, reason: 'the fade is not cut short');
    await t.pump(ReviewLayerState.glintTime);
    expect(opened, 1);
    await t.pump(const Duration(seconds: 2));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('rules only: no waiting state, only the glint, then the changes screen', (t) async {
    phoneModel = StandInModel(isReady: false);
    final b = Blessing(
      id: 'r',
      title: 'Blessing',
      from: 'Dad',
      utc: DateTime.utc(2026, 11, 1),
      utcOffset: Duration.zero,
      place: const Place(40, -111),
      rawText: 'I bless you, um, with peace and and comfort',
      language: 'en',
    );
    var opened = 0;
    await show(t, _Page(b: b, onChanges: () => opened++));
    await press(t);
    await t.pump();
    expect(find.byKey(const Key('review-polishing')), findsNothing);
    expect(find.byKey(const Key('review-polishing-light')), findsNothing);
    expect(lightWidget(t).pieces, isEmpty);
    expect(lightWidget(t).glints, hasLength(b.changes.length));
    expect(light(t).bandMoving, isFalse);
    expect(find.byKey(const Key('review-polished')), findsOneWidget);
    await t.pump(ReviewLayerState.glintTime + const Duration(milliseconds: 50));
    expect(opened, 1);
    await t.pump(const Duration(seconds: 2));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('nothing to polish: it simply settles, with no glint', (t) async {
    phoneModel = StandInModel(isReady: false);
    final b = long()..rawText = 'I bless you with peace.';
    var opened = 0;
    await show(t, _Page(b: b, onChanges: () => opened++));
    await press(t);
    await t.pump();
    expect(find.byKey(const Key('review-nothing')), findsOneWidget);
    expect(lightWidget(t).glints, isEmpty);
    expect(light(t).animating, isFalse);
    await t.pump(const Duration(seconds: 3));
    expect(opened, 0);
  });
}
