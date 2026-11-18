// The family member screens on their own: the capsule and its menu, adding and changing someone,
// removing them (the count named, nothing gone on a single tap), and whose blessing on review; in
// English and Spanish, at the usual size and the largest.
//
//   flutter test test/people_widgets_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/home/home_screen.dart' show EmptyRingFoot;
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/family_pages.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/people/sky_switch.dart';
import 'package:upon_thy_head/people/whose_choice.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/pull_down.dart';

// (logical width, height): iPhone 17 Pro; Pixel 10 Pro at its largest display size
const screens = [Size(402, 874), Size(328, 732)];
const scales = [1.0, 2.0, 3.0];
const p = Palette.lamplight;

final emma = Person(id: 'e', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.utc(2026));
final james = Person(id: 'j', name: 'James', created: DateTime.utc(2026));

Future<void> show(WidgetTester t, Widget child, {Size screen = const Size(402, 874), double scale = 1, EdgeInsets padding = EdgeInsets.zero}) async {
  t.view.physicalSize = screen * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: screen, devicePixelRatio: 3, textScaler: TextScaler.linear(scale), padding: padding, viewPadding: padding),
    child: CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: ColoredBox(color: p.ground, child: child),
    ),
  ));
  await t.pumpAndSettle();
}

/// Nothing drawn past the screen's edges (overflow inside a widget fails the test on its own).
void onScreen(WidgetTester t, Finder f, Size screen) {
  for (final e in f.evaluate()) {
    final r = t.getRect(find.byWidget(e.widget).first);
    expect(r.left >= -.5 && r.right <= screen.width + .5, isTrue, reason: '$r off a ${screen.width} wide screen');
  }
}

/// No word of a page's title broken across lines: never more lines than words.
void wholeWords(WidgetTester t, String key) {
  final para = t.renderObject<RenderParagraph>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(RichText)).first);
  final words = para.text.toPlainText().trim().split(RegExp(r'\s+')).length;
  final text = para.text.toPlainText();
  final lines = {for (final b in para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))) b.top.round()}.length;
  expect(lines, lessThanOrEqualTo(words), reason: '"${para.text.toPlainText()}" broken inside a word');
}

void main() {
  tearDown(() => Strings.use(UiLanguage.english));

  group('the capsule and its menu', () {
    Widget home(ValueChanged<String?> chosen, {String showing = 'e', List<Person>? people}) {
      final f = Family(people ?? [emma, james], const []);
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
          child: Builder(
            builder: (c) => SkySwitch(
              key: const Key('sky-switch'),
              palette: p,
              label: f.title(showing),
              onTap: () async => chosen(await showPullDownItems(c, palette: p, items: f.menu(showing), width: 300, align: PullDownAlign.start)),
            ),
          ),
        ),
      );
    }

    testWidgets('a tap opens the menu under it; a row chooses; a tap outside chooses nothing', (t) async {
      final picked = <String?>[];
      await show(t, home(picked.add));
      expect(find.text('For Emma'), findsOneWidget);
      await t.tap(find.byKey(const Key('sky-switch')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pull-down')), findsOneWidget);
      expect(t.getRect(find.byKey(const Key('pull-down'))).top, greaterThan(t.getRect(find.byKey(const Key('sky-switch'))).bottom),
          reason: 'it hangs from the capsule');
      expect(t.getRect(find.byKey(const Key('pull-down'))).left, closeTo(t.getRect(find.byKey(const Key('sky-switch'))).left, .5),
          reason: 'from its leading edge');
      for (final label in ['For me', 'For James', 'Add a family member', 'Manage family']) {
        expect(find.descendant(of: find.byKey(const Key('pull-down')), matching: find.text(label)), findsOneWidget, reason: label);
      }
      await t.tap(find.byKey(const Key('pull-down-p:j')));
      await t.pumpAndSettle();
      expect(picked, ['p:j']);
      expect(find.byKey(const Key('pull-down')), findsNothing);

      await t.tap(find.byKey(const Key('sky-switch')));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(390, 860));
      await t.pumpAndSettle();
      expect(picked, ['p:j', null]);
    });

    testWidgets('VoiceOver hears whose sky it is and what the capsule does; the chosen row is selected', (t) async {
      final s = t.ensureSemantics();
      await show(t, home((_) {}));
      expect(find.bySemanticsLabel('For Emma. Choose whose blessings are shown'), findsOneWidget);
      expect(t.getSemantics(find.byKey(const Key('sky-switch'))), isSemantics(isButton: true, hasTapAction: true),
          reason: 'VoiceOver and TalkBack can press it');
      await t.tap(find.byKey(const Key('sky-switch')));
      await t.pumpAndSettle();
      final row = t.getSemantics(find.byKey(const Key('pull-down-p:e')));
      expect(row, isSemantics(isSelected: true, hasTapAction: true));
      s.dispose();
    });

    for (final lang in UiLanguage.values) {
      for (final screen in screens) {
        for (final scale in scales) {
          testWidgets('$lang, ${screen.width} wide, text ×$scale: capsule and open menu on screen', (t) async {
            Strings.use(lang);
            final long = Person(id: 'l', name: 'Maximiliana Esperanza', created: DateTime.utc(2026));
            await show(t, home((_) {}, showing: 'l', people: [emma, long]), screen: screen, scale: scale);
            onScreen(t, find.byKey(const Key('sky-switch')), screen);
            await t.tap(find.byKey(const Key('sky-switch')));
            await t.pumpAndSettle();
            onScreen(t, find.byKey(const Key('pull-down')), screen);
            final menu = t.getRect(find.byKey(const Key('pull-down')));
            expect(menu.bottom, lessThanOrEqualTo(screen.height + .5));
            // the last row can be reached (the menu scrolls when it is taller than the room)
            await t.scrollUntilVisible(find.byKey(const Key('pull-down-manage')), 60,
                scrollable: find.descendant(of: find.byKey(const Key('pull-down')), matching: find.byType(Scrollable)));
            await t.tap(find.byKey(const Key('pull-down-manage')));
            await t.pumpAndSettle();
          });
        }
      }
    }
  });

  group('adding and changing a family member', () {
    testWidgets('Add waits for a name; the name is tidied; the birth date is optional', (t) async {
      final saved = <(String, Day?)>[];
      await show(t, PersonLayer(palette: p, on: true, person: null, onBack: () {}, onSave: (n, b) => saved.add((n, b))));
      expect(find.text('Add a family member'), findsWidgets);
      expect(find.byKey(const Key('person-born-note')), findsOneWidget);
      await t.tap(find.byKey(const Key('person-save')));
      await t.pumpAndSettle();
      expect(saved, isEmpty, reason: 'nothing to add without a name');
      await t.enterText(find.byKey(const Key('person-name')), '  Emma   Rose ');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person-save')));
      await t.pumpAndSettle();
      expect(saved, [('Emma Rose', null)]);
    });

    testWidgets('the birth date: chosen on a sheet, and "No date" takes it away', (t) async {
      final saved = <(String, Day?)>[];
      await show(t, PersonLayer(palette: p, on: true, person: emma, countLine: 'Two blessings since August 2008', blessings: 2, onBack: () {}, onSave: (n, b) => saved.add((n, b))));
      expect(find.text('Born August 3, 2008'), findsNothing, reason: 'the page shows the date itself, not the line');
      await t.tap(find.byKey(const Key('person-born')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('born-picker')), findsOneWidget);
      await t.tap(find.byKey(const Key('born-done')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person-save')));
      await t.pumpAndSettle();
      expect(saved.last, ('Emma', Day(2008, 8, 3)), reason: 'Done keeps the day it opened on');

      await t.tap(find.byKey(const Key('person-born')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('born-none')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person-save')));
      await t.pumpAndSettle();
      expect(saved.last, ('Emma', null));
    });

    testWidgets('removing: the count is named, Keep removes nothing, Remove does', (t) async {
      var asked = 0;
      var answer = false;
      await show(
          t,
          PersonLayer(
              palette: p,
              on: true,
              person: emma,
              blessings: 3,
              onBack: () {},
              onSave: (_, _) {},
              onRemove: () async {
                asked++;
                return answer;
              }));
      await t.tap(find.byKey(const Key('person-remove')));
      await t.pumpAndSettle();
      expect(asked, 0, reason: 'nothing is removed on a single tap');
      expect(find.text('Remove Emma?'), findsOneWidget);
      expect(find.text(Strings.removeBody('Emma', 3)), findsOneWidget);
      expect(Strings.removeBody('Emma', 3), contains('Three blessings leave this phone'));
      await t.tap(find.byKey(const Key('remove-keep')));
      await t.pumpAndSettle();
      expect(asked, 0);

      // a link of hers that could not be stopped: nothing removed, and the sheet says why
      await t.tap(find.byKey(const Key('person-remove')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('remove-confirm')));
      await t.pumpAndSettle();
      expect(asked, 1);
      expect(find.byKey(const Key('remove-note')), findsOneWidget);

      answer = true;
      await t.tap(find.byKey(const Key('remove-confirm')));
      await t.pumpAndSettle();
      expect(asked, 2);
    });

    test('the words of removing: none, one, many; English and Spanish', () {
      expect(Strings.removeBody('Emma', 0), "Emma's ring leaves this phone. There are no blessings on it.");
      expect(Strings.removeBody('Emma', 1), "One blessing leaves this phone with Emma's ring. This cannot be undone.");
      Strings.use(UiLanguage.spanish);
      expect(Strings.removeBody('Emma', 3), contains('tres bendiciones'));
      expect(Strings.removeTitle('Emma'), '¿Quitar a Emma?');
    });

    for (final lang in UiLanguage.values) {
      for (final screen in screens) {
        for (final scale in scales) {
          testWidgets('$lang, ${screen.width} wide, text ×$scale: adding, managing and removing hold', (t) async {
            Strings.use(lang);
            await show(t, PersonLayer(palette: p, on: true, person: null, onBack: () {}, onSave: (_, _) {}), screen: screen, scale: scale);
            wholeWords(t, 'person-title');
            await t.tap(find.byKey(const Key('person-born')));
            await t.pumpAndSettle();
            onScreen(t, find.byKey(const Key('born-done')), screen);

            await show(
                t,
                FamilyLayer(palette: p, people: [emma, james], countLine: (_) => Strings.countLine(12, DateTime(2008, 8)), onBack: () {}, onOpen: (_) {}, onAdd: () {}),
                screen: screen,
                scale: scale);
            expect(find.byKey(const Key('family-row-e')), findsOneWidget);
            wholeWords(t, 'family-title');

            await show(
                t,
                PersonLayer(palette: p, on: true, person: emma, blessings: 12, countLine: 'x', onBack: () {}, onSave: (_, _) {}, onRemove: () async => true),
                screen: screen,
                scale: scale);
            await t.scrollUntilVisible(find.byKey(const Key('person-remove')), 80, scrollable: find.byType(Scrollable).first);
            await t.tap(find.byKey(const Key('person-remove')));
            await t.pumpAndSettle();
            onScreen(t, find.byKey(const Key('remove-confirm')), screen);
            onScreen(t, find.byKey(const Key('remove-keep')), screen);
          });
        }
      }
    }
  });

  group('whose blessing, on review', () {
    testWidgets('a row of names: For me, each family member, Passing it along; the chosen one selected', (t) async {
      Whose value = Whose.me;
      final chosen = <Whose>[];
      await show(
          t,
          StatefulBuilder(
            builder: (c, set) => Center(
              child: WhoseChoice(palette: p, people: [emma, james], value: value, onChanged: (w) => set(() => chosen.add(value = w))),
            ),
          ));
      expect(find.text('Emma'), findsOneWidget);
      expect(find.text('James'), findsOneWidget);
      await t.tap(find.byKey(const Key('review-person-j')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('review-passing')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('review-for-me')));
      await t.pumpAndSettle();
      expect(chosen, [WhosePerson('j'), Whose.passing, Whose.me]);
    });
  });

  group('the largest text', () {
    // the safe area of iPhone 17 Pro, and of a Pixel with its bars
    const safe = {402: EdgeInsets.only(top: 62, bottom: 34), 328: EdgeInsets.only(top: 40, bottom: 24)};

    for (final lang in UiLanguage.values) {
      for (final screen in screens) {
        testWidgets('$lang, ${screen.width} wide, text ×3.1: the menu is the full width, every row reachable, each line at most two lines, the tick beside the name', (t) async {
          Strings.use(lang);
          final pad = safe[screen.width.round()]!;
          final long = Person(id: 'l', name: 'Maximiliana Esperanza', created: DateTime.utc(2026));
          final mine = [for (var i = 0; i < 6; i++) Blessing(id: 'm$i', title: 'B', from: '', utc: DateTime.utc(2024, 6 + i), utcOffset: Duration.zero, place: samplePlace, rawText: '', firstText: '', language: 'en')];
          final f = Family([james, long], mine);
          final picked = <String?>[];
          await show(
              t,
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, pad.top, 16, 0),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.6,
                    child: Builder(
                      builder: (c) => SkySwitch(
                        key: const Key('sky-switch'),
                        palette: p,
                        label: f.title('l'),
                        // the menu is a route over the app: at the person's own size, as on home
                        onTap: () async => picked.add(await showPullDownItems(c, palette: p, items: f.menu('l'), width: 300, align: PullDownAlign.start)),
                      ),
                    ),
                  ),
                ),
              ),
              screen: screen,
              scale: 3.1,
              padding: pad);
          await t.tap(find.byKey(const Key('sky-switch')));
          await t.pumpAndSettle();
          final menu = t.getRect(find.byKey(const Key('pull-down')));
          expect(menu.left, closeTo(16, .5));
          expect(menu.width, closeTo(screen.width - 32, .5), reason: 'the full width between the margins');
          expect(menu.top, greaterThanOrEqualTo(pad.top));
          expect(menu.bottom, lessThanOrEqualTo(screen.height - pad.bottom + .5), reason: 'inside the safe area');
          final scroll = find.descendant(of: find.byKey(const Key('pull-down')), matching: find.byType(Scrollable));
          for (final code in ['me', 'p:j', 'p:l', 'add', 'manage']) {
            final row = find.byKey(Key('pull-down-$code'));
            await t.scrollUntilVisible(row, 80, scrollable: scroll);
            await t.pumpAndSettle();
            final r = t.getRect(row);
            expect(r.top >= menu.top - .5 && r.bottom <= menu.bottom + .5, isTrue, reason: '$code can be brought wholly into view: $r in $menu');
            for (final key in ['pull-down-label', 'pull-down-sub']) {
              final text = find.descendant(of: row, matching: find.byKey(Key(key)));
              if (text.evaluate().isEmpty) continue;
              final para = t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)));
              final line = key == 'pull-down-label' ? 3.1 * 21 : 3.1 * 17;
              expect(para.size.height, lessThanOrEqualTo(2 * line + 1), reason: '$code: "${para.text.toPlainText()}" in at most two lines');
            }
            // the tick (or plus) sits beside the name's first line
            final mark = find.descendant(of: row, matching: find.byKey(const Key('pull-down-mark')));
            final label = t.getRect(find.descendant(of: row, matching: find.byKey(const Key('pull-down-label'))));
            final m = t.getRect(mark);
            expect(m.center.dy, inInclusiveRange(label.top, label.top + 3.1 * 21), reason: '$code: the mark beside the first line');
          }
          await t.tap(find.byKey(const Key('pull-down-manage')));
          await t.pumpAndSettle();
          expect(picked, ['manage']);
        });

        testWidgets('$lang, ${screen.width} wide, text ×3.1: an empty ring\'s line stays between the count line and New blessing', (t) async {
          Strings.use(lang);
          final pad = safe[screen.width.round()]!;
          for (final line in [Strings.firstRun, Strings.emptyRing('Maximiliana Esperanza')]) {
            await show(
                t,
                Stack(children: [
                  // where home puts it
                  Positioned(left: 0, right: 0, bottom: 30, child: EmptyRingFoot(palette: p, line: line, onNew: () {})),
                ]),
                screen: screen,
                scale: 3.1,
                padding: pad);
            final text = t.getRect(find.byKey(const Key('first-run')));
            final pill = t.getRect(find.byKey(const Key('new')));
            expect(text.top, greaterThanOrEqualTo(screen.height * (1 - EmptyRingFoot.share) - pill.height - 36 - 30 - 1),
                reason: '"$line" keeps to the lower part, below the capsule and the count line: $text');
            expect(text.top, greaterThan(screen.height / 2), reason: 'well clear of the head');
            expect(text.bottom, lessThanOrEqualTo(pill.top), reason: 'above New blessing');
            expect(text.left >= 0 && text.right <= screen.width, isTrue);
            wholeWords(t, 'first-run');
          }
        });
      }
    }
  });

  test('review: a family member chosen fills an empty "For"; switching away clears only that', () {
    final people = [emma, james];
    var f = forAfterWhose(text: '', filled: null, to: WhosePerson('e'), people: people);
    expect(f, (text: 'Emma', filled: 'Emma'));
    f = forAfterWhose(text: f.text, filled: f.filled, to: WhosePerson('j'), people: people);
    expect(f, (text: 'James', filled: 'James'), reason: 'the filled-in name follows the choice');
    f = forAfterWhose(text: f.text, filled: f.filled, to: Whose.me, people: people);
    expect(f, (text: '', filled: null), reason: 'switched away: the filled-in name goes');
    // typed names are never overwritten
    expect(forAfterWhose(text: 'Clara', filled: null, to: WhosePerson('e'), people: people), (text: 'Clara', filled: null));
    expect(forAfterWhose(text: 'Emma Rose', filled: 'Emma', to: Whose.passing, people: people), (text: 'Emma Rose', filled: null),
        reason: 'changed by hand after it was filled: kept');
    expect(forAfterWhose(text: 'Emma', filled: null, to: Whose.me, people: people), (text: 'Emma', filled: null),
        reason: 'an "Emma" typed or heard, not filled in, stays');
  });
}
