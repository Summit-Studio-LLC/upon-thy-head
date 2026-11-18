// The entry page (the review page for a blessing entered from a written copy) and its date sheet:
// "Given" first, Done dim until there is a year and some words, the Paste chip, no listen bar and no
// polish; Full date / Month and year / Year only, and no date after today. In English and Spanish.
//
//   flutter test test/entry_widgets_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/review/date_sheet.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/strings.dart';

import 'screen_reader_test.dart' show show, FakePlayer, p;
import 'support/semantics.dart';

final today = DateTime(2026, 11, 18);
const GivenChoice todayChoice = (precision: DatePrecision.day, year: 2026, month: 11, day: 18);

Iterable<double> leftOf(WidgetTester t, List<String> keys) => [for (final k in keys) t.getTopLeft(find.byKey(Key(k))).dx];

void main() {
  tearDown(() => Strings.use(UiLanguage.english));

  for (final lang in UiLanguage.values) {
    group(lang.name, () {
      setUp(() => Strings.use(lang));

      testWidgets('the date sheet: three kinds, wheels to match, the note, never after today', (t) async {
        final chosen = <GivenChoice>[];
        await show(t, Padding(padding: const EdgeInsets.all(24), child: DateSheet(palette: p, initial: todayChoice, today: today, onDone: chosen.add)));
        expect(find.text(Strings.whenGiven), findsOneWidget);
        expect(find.byKey(const Key('wheel-day')), findsOneWidget);
        expect(find.byKey(const Key('wheel-month')), findsOneWidget);
        expect(find.byKey(const Key('wheel-year')), findsOneWidget);
        expect(find.byKey(const Key('date-note')), findsNothing);
        // English: month, day, year; Spanish: día, mes, año
        final x = leftOf(t, ['wheel-month', 'wheel-day', 'wheel-year']).toList();
        if (lang == UiLanguage.spanish) {
          expect(x[1] < x[0] && x[0] < x[2], isTrue, reason: 'día, mes, año');
        } else {
          expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: 'month, day, year');
        }

        // month and year: no day wheel, and the note says where the light sits
        await t.tap(find.byKey(const Key('precision-month')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('wheel-day')), findsNothing);
        expect(find.byKey(const Key('wheel-month')), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const Key('date-note'))).data, Strings.precisionNote(DatePrecision.month, DateTime(2026, 11, 15, 12)));

        // year only: the year wheel alone; the wheel turned to 1998 is what Done gives
        await t.tap(find.byKey(const Key('precision-year')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('wheel-month')), findsNothing);
        expect(find.byKey(const Key('wheel-day')), findsNothing);
        await t.drag(find.byKey(const Key('wheel-year')), const Offset(0, 40.0 * 28));
        await t.pumpAndSettle();
        final s = t.state<DateSheetState>(find.byType(DateSheet));
        expect(s.choice.precision, DatePrecision.year);
        expect(s.choice.year, lessThan(2026));
        expect(t.widget<Text>(find.byKey(const Key('date-note'))).data, Strings.precisionNote(DatePrecision.year, DateTime(s.choice.year, 7, 2, 12)));
        await t.tap(find.byKey(const Key('date-done')));
        expect(chosen.single, (precision: DatePrecision.year, year: s.choice.year, month: 1, day: 1));

        // no day after today: a later day this month, or a later month this year, is cut back
        s.reset((precision: DatePrecision.day, year: 2026, month: 12, day: 25));
        await t.pump();
        expect(s.choice, todayChoice);
        s.reset((precision: DatePrecision.day, year: 2027, month: 3, day: 1));
        await t.pump();
        expect(s.choice.year, 2026);
        expect(s.choice.month, lessThanOrEqualTo(11));
        // and no 31st of a month that has 30
        s.reset((precision: DatePrecision.day, year: 1998, month: 9, day: 31));
        await t.pump();
        expect(s.choice.day, 30);
        // February in a leap year
        s.reset((precision: DatePrecision.day, year: 2000, month: 2, day: 31));
        await t.pump();
        expect(s.choice.day, 29);
      });

      testWidgets('the entry page: Given first, Done dim, Paste, no listen bar, no polish', (t) async {
        final dir = Directory.systemTemp.createTempSync('entry_widgets');
        addTearDown(() => dir.deleteSync(recursive: true));
        final b = enteredBlessing(today, place: samplePlace);
        var given = 0, saves = 0, finished = 0;
        final pasted = 'Daniel, by the authority of the Melchizedek Priesthood.\n\nI bless you with peace.\nAmen.';
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': pasted};
          return null;
        });
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        final handle = t.ensureSemantics();
        await show(
            t,
            ReviewLayer(
              palette: p,
              blessing: b,
              on: true,
              player: FakePlayer(),
              onSave: () async => saves++,
              onBack: () {},
              onFinish: () => finished++,
              onGiven: () => given++,
            ));
        // Given, asking; first of the fields
        expect(t.widget<Text>(find.byKey(const Key('review-given'))).data, Strings.whenGiven);
        expect(t.getTopLeft(find.byKey(const Key('review-given-row'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('review-words'))).dy));
        expect(find.byKey(const Key('review-date')), findsNothing);
        expect(find.byType(ListenBar), findsNothing);
        expect(find.byKey(const Key('review-polish')), findsNothing);
        expect(find.text(Strings.typeOrPaste), findsOneWidget);
        // Done is dim, and says why
        final done = nodeLabelled(t, Strings.done).getSemanticsData();
        expect(done.flagsCollection.isEnabled.toString(), contains('isFalse'));
        expect(done.hint, Strings.doneNeedsDateAndWords);
        expect(unpressable(t), isEmpty);

        // Paste: the words exactly as copied, the paragraphs kept; then the chip goes
        await t.runAsync(() async {
          await activate(t, Strings.paste);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pump(const Duration(milliseconds: 500));
        expect(b.rawText, pasted);
        expect(find.byKey(const Key('review-paste')), findsNothing);
        // words but no date: still dim
        expect(nodeLabelled(t, Strings.done).getSemanticsData().flagsCollection.isEnabled.toString(), contains('isFalse'));

        // Given opens the sheet; year only, 1998
        await activate(t, Strings.givenField);
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const Key('date-sheet')), findsOneWidget);
        await activate(t, Strings.yearOnly);
        await t.pump(const Duration(milliseconds: 300));
        t.state<DateSheetState>(find.byType(DateSheet)).reset((precision: DatePrecision.year, year: 1998, month: 1, day: 1));
        await t.pump();
        await t.runAsync(() async {
          await activate(t, Strings.done);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pump(const Duration(milliseconds: 600));
        expect(b.precision, DatePrecision.year);
        expect(b.local, DateTime.utc(1998, 7, 2, 12));
        expect(given, 1);
        expect(saves, greaterThan(0));
        expect(t.widget<Text>(find.byKey(const Key('review-given'))).data, '1998');
        expect(nodeLabelled(t, Strings.givenField).getSemanticsData().value, '1998');
        // a year and words: Done lights
        final lit = nodeLabelled(t, Strings.done).getSemanticsData();
        expect(lit.flagsCollection.isEnabled.toString(), isNot(contains('isFalse')));
        expect(unpressable(t), isEmpty);
        handle.dispose();
        await t.pumpWidget(const SizedBox());
      });
    });
  }

  testWidgets('at the largest text: the entry page and the date sheet fit, nothing overflows', (t) async {
    Strings.use(UiLanguage.english);
    Widget big(Widget child) => Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(3.1)), child: child));
    final b = enteredBlessing(today, place: samplePlace);
    await show(t, big(ReviewLayer(palette: p, blessing: b, on: true, player: FakePlayer(), onSave: () async {}, onBack: () {}, onFinish: () {})));
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('review-given-row')), findsOneWidget);
    expect(find.byKey(const Key('review-paste')), findsOneWidget);
    for (final kind in ['day', 'month', 'year']) {
      await show(t, big(SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: DateSheet(palette: p, initial: todayChoice, today: today, onDone: (_) {})))));
      await t.tap(find.byKey(Key('precision-$kind')));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull, reason: kind);
    }
    await t.pumpWidget(const SizedBox());
  });
}
