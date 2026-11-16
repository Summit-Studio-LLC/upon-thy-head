import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';

const screen = Size(402, 874);

Future<void> show(WidgetTester tester, Arrival? a, {bool on = true, bool still = false, double scale = 1, VoidCallback? keep, VoidCallback? notNow}) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: screen, devicePixelRatio: 3, disableAnimations: still, textScaler: TextScaler.linear(scale)),
    child: CupertinoApp(
      home: ReceiveSheet(palette: Palette.lamplight, on: on, arrival: a, onKeep: keep ?? () {}, onNotNow: notNow ?? () {}),
    ),
  ));
}

void main() {
  final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
  final rec = BlessingRecord.of(surgery);
  setUp(() => Strings.use(UiLanguage.english));

  test('a file that arrives: new, the same, different, newer, unreadable, too large', () async {
    Future<Blessing?> none(String _) async => null;
    Future<Blessing?> mine(String _) async => surgery;
    final bytes = rec.toFileBytes();
    expect(await arrivalOf(IncomingFile(bytes: bytes), none), isA<ArrivalNew>());
    expect(await arrivalOf(IncomingFile(bytes: bytes), mine), isA<ArrivalSame>());
    final other = rec.toBlessing(place: samplePlace)..rawText = 'Other words.'..changes = [];
    expect(await arrivalOf(IncomingFile(bytes: bytes), (_) async => other), isA<ArrivalDifferent>());
    expect(await arrivalOf(const IncomingFile(tooLarge: true), none), isA<ArrivalUnreadable>());
    expect(await arrivalOf(IncomingFile(bytes: Uint8List.fromList([1, 2, 3])), none), isA<ArrivalUnreadable>());
  });

  testWidgets('the question: title, giver, date, Keep and Not now; VoiceOver hears the title first', (tester) async {
    final handle = tester.ensureSemantics();
    var kept = 0, not = 0;
    await show(tester, ArrivalNew(rec), keep: () => kept++, notNow: () => not++);
    await tester.pumpAndSettle();
    expect(find.text('Comfort before surgery'), findsOneWidget);
    expect(find.text('A blessing from Dad'), findsOneWidget);
    expect(find.text(surgery.longDate), findsOneWidget);
    expect(find.text('Keep it with your blessings?'), findsOneWidget);
    expect(find.bySemanticsLabel('Comfort before surgery'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('^Keep\$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Not now\$')), findsOneWidget);
    await tester.tap(find.byKey(const Key('receive-keep')));
    await tester.tap(find.byKey(const Key('receive-not-now')));
    expect((kept, not), (1, 1));
    handle.dispose();
  });

  testWidgets('hidden, nothing of it is read aloud', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, null, on: false);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('could not be read|blessing', caseSensitive: false)), findsNothing);
    handle.dispose();
  });

  testWidgets('Reduce Motion: simply there, with no slide', (tester) async {
    await show(tester, ArrivalNew(rec), on: false, still: true);
    await tester.pumpAndSettle();
    await show(tester, ArrivalNew(rec), still: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(find.byKey(const Key('receive-sheet'))).bottom, closeTo(screen.height, .5), reason: 'it slid');
    // and without Reduce Motion it does slide
    await show(tester, ArrivalNew(rec), on: false);
    await tester.pumpAndSettle();
    await show(tester, ArrivalNew(rec));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(find.byKey(const Key('receive-sheet'))).bottom, greaterThan(screen.height + 5));
    await tester.pumpAndSettle();
  });

  for (final lang in UiLanguage.values) {
    testWidgets('the first accessibility text size, ${lang.name}: nothing clipped, nothing off screen', (tester) async {
      Strings.use(lang);
      final long = rec.toBlessing(place: samplePlace)..title = 'Comfort before surgery, and for the long days of healing after it';
      for (final a in <Arrival>[ArrivalNew(BlessingRecord.of(long)), ArrivalDifferent(rec, surgery), const ArrivalNewer(), const ArrivalUnreadable('x')]) {
        // iOS's first accessibility size (AX1) sets body text at 28 points against Large's 17
        await show(tester, a, scale: 28 / 17);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$a overflowed');
        for (final k in ['receive-title', 'receive-from', 'receive-date', 'receive-body', 'receive-keep', 'receive-not-now', 'receive-replace', 'receive-keep-mine', 'receive-ok']) {
          final f = find.byKey(Key(k));
          if (f.evaluate().isEmpty) continue;
          final r = tester.getRect(f);
          expect(r.top >= 0 && r.bottom <= screen.height && r.left >= 0 && r.right <= screen.width, isTrue, reason: '$a: $k at $r');
        }
      }
    });
  }
}
