import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/polish/changes_screen.dart';
import 'package:upon_thy_head/theme.dart';

Blessing surgery() => sampleBlessings().firstWhere((b) => b.id == 'surgery');

Future<void> pumpScreen(WidgetTester tester, Blessing b, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: const Size(402, 874), padding: const EdgeInsets.only(top: 62), viewPadding: const EdgeInsets.only(top: 62), disableAnimations: reduceMotion),
    child: CupertinoApp(
      home: ChangesLayer(palette: Palette.lamplight, blessing: b, on: true, onSave: () async {}, onDone: () {}),
    ),
  ));
  await tester.pumpAndSettle();
}

String count(WidgetTester t) => t.widget<Text>(find.byKey(const Key('changes-count'))).data!;

void main() {
  testWidgets('a layer that was never opened can be removed (found by the store run)', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: ChangesLayer(palette: Palette.lamplight, blessing: null, on: false, onSave: () async {}, onDone: () {}),
    ));
    await tester.pumpWidget(const CupertinoApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: a restore applies at once, with no gliding words', (tester) async {
    final b = surgery();
    await pumpScreen(tester, b, reduceMotion: true);
    expect(count(tester), '5 changes');
    await tester.tap(find.byKey(const Key('sheet-restore')));
    await tester.pump();
    expect(b.changes[0].kept, isFalse);
    expect(count(tester), '4 of 5 kept', reason: 'the header changes in the same frame');
    expect(tester.hasRunningAnimations, isFalse, reason: 'nothing moves');
    await tester.tap(find.byKey(const Key('sheet-next')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('sheet-step'))).data, '2 of 5', reason: 'the sheet changes at once');
  });

  testWidgets('with motion: the words glide for 540 ms, the sheet slides', (tester) async {
    final b = surgery();
    await pumpScreen(tester, b);
    await tester.tap(find.byKey(const Key('sheet-restore')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(count(tester), '4 of 5 kept');
    await tester.tap(find.byKey(const Key('sheet-next')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<Text>(find.byKey(const Key('sheet-step'))).data, '1 of 5', reason: 'the old change is still sliding out');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('sheet-step'))).data, '2 of 5');
  });

  testWidgets('VoiceOver: each change is a button with its kind and both versions; tapping selects it', (tester) async {
    final handle = tester.ensureSemantics();
    final b = surgery();
    await pumpScreen(tester, b);
    final last = find.semantics.byLabel(RegExp(r'^Heavy change\. Reworded\. Original: your strength, it’s going to come back to you\. Polished: Strength will return to you\.'));
    expect(last, findsOneWidget);
    final node = last.evaluate().single;
    // ignore: deprecated_member_use
    expect(node.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue);
    final cut = find.semantics.byLabel(RegExp(r'^Light change\. Filler removed\. Original: um, right now\. Polished: Left out\.'));
    expect(cut, findsOneWidget);
    tester.semantics.tap(last);
    await tester.pumpAndSettle();
    expect(tester.state<ChangesLayerState>(find.byType(ChangesLayer)).selected, 4);
    handle.dispose();
  });

  testWidgets('a tap on a marked change selects it; the legend shows only the sizes there are', (tester) async {
    final b = surgery();
    b.changes.removeWhere((c) => c.size.code == 'heavy');
    await pumpScreen(tester, b);
    expect(find.byKey(const Key('legend-heavy')), findsNothing);
    expect(find.byKey(const Key('legend-light')), findsOneWidget);
    expect(find.byKey(const Key('legend-moderate')), findsOneWidget);
    final words = tester.getRect(find.byKey(const Key('changes-words')));
    // "knows" begins the second paragraph's second line... find it by tapping along until selection changes
    final state = tester.state<ChangesLayerState>(find.byType(ChangesLayer));
    var hit = false;
    for (var y = words.top + 70; y < words.top + 400 && !hit; y += 10) {
      for (var x = words.left + 4; x < words.right && !hit; x += 24) {
        await tester.tapAt(Offset(x, y));
        await tester.pump(const Duration(milliseconds: 600));
        hit = state.selected != 0;
      }
    }
    expect(hit, isTrue, reason: 'no marked change took a tap');
  });
}
