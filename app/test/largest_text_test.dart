// The screens found faulty at the largest accessibility text size (build 12's evaluation), on a
// 393 × 852 iPhone, in English and Spanish: nothing overflows, overlaps or is cut, and no title or
// button label breaks inside a word.
//
//   flutter test test/largest_text_test.dart

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/home/home_screen.dart' show UnlockButton;
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/date_sheet.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/scrims.dart';

import 'lock_place_test.dart' show FakeLocator;
import 'screen_reader_test.dart' show FakePlayer;

const p = Palette.lamplight;

/// iPhone's largest accessibility size, as Flutter reads it (17 pt body text drawn at about 53).
const largest = 3.12;

Future<void> show(WidgetTester t, Widget child, {double scale = largest}) async {
  t.view.physicalSize = const Size(393, 852) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(
      size: const Size(393, 852),
      devicePixelRatio: 3,
      padding: const EdgeInsets.only(top: 59, bottom: 34),
      viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
      textScaler: TextScaler.linear(scale),
    ),
    child: CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: ColoredBox(color: p.ground, child: child),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Every line of the text found begins at the start of a word.
void wholeWords(WidgetTester t, Finder f) {
  final para = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
  final text = para.text.toPlainText();
  final tp = TextPainter(text: para.text, textDirection: para.textDirection, textScaler: para.textScaler, textAlign: para.textAlign)
    ..layout(maxWidth: para.size.width);
  addTearDown(tp.dispose);
  var at = 0;
  while (at < text.length) {
    final line = tp.getLineBoundary(TextPosition(offset: at));
    if (line.start > 0) expect(RegExp(r'\s').hasMatch(text[line.start - 1]), isTrue, reason: '"$text" broken inside a word at ${line.start}');
    if (line.end <= at) break;
    at = line.end;
    while (at < text.length && RegExp(r'\s').hasMatch(text[at])) {
      at++;
    }
  }
}

/// The text found is drawn whole inside [box] (not cut by a fixed height).
void inside(WidgetTester t, Finder text, Finder box) {
  final r = t.getRect(find.descendant(of: text, matching: find.byType(RichText), matchRoot: true).first);
  final b = t.getRect(box);
  expect(r.top >= b.top - .5 && r.bottom <= b.bottom + .5, isTrue, reason: 'text $r is cut by its box $b');
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('largest_text'));
  tearDown(() {
    dir.deleteSync(recursive: true);
    Strings.use(UiLanguage.english);
  });

  for (final lang in UiLanguage.values) {
    group(lang.name, () {
      setUp(() => Strings.use(lang));

      testWidgets('the recording start: the hint, the language and Enter a past blessing do not overlap; Begin is on screen', (t) async {
        final s = RecordSession(recorder: SilentRecorder(), audioDir: '${dir.path}/audio')..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
        await t.runAsync(() => s.checkPermissions(ask: false));
        await show(
            t,
            RecordLayer(
              palette: p,
              session: s,
              active: false,
              onBegin: () {},
              onClose: () {},
              onDiscardEarly: () {},
              onAmen: () {},
              onLanguage: (_) {},
              onOpenSettings: () {},
              onEnter: () {},
            ));
        expect(t.takeException(), isNull);
        final begin = t.getRect(find.byKey(const Key('begin')));
        expect(begin.top >= 0 && begin.bottom <= 852, isTrue, reason: 'Begin $begin');
        final hint = t.getRect(find.text(Strings.nothingRecorded));
        final enter = find.byKey(const Key('enter-past'));
        await t.ensureVisible(enter);
        await t.pump();
        final hintNow = t.getRect(find.text(Strings.nothingRecorded));
        expect(t.getRect(enter).top, greaterThanOrEqualTo(hintNow.bottom + 40 - .5), reason: 'Enter a past blessing over the hint and language');
        expect(hint.width, greaterThan(0));
        expect(t.getRect(enter).bottom, lessThanOrEqualTo(852));
        await t.pumpWidget(const SizedBox());
        s.dispose();
      });

      testWidgets('Settings: the title whole, Use my location whole', (t) async {
        final settings = await t.runAsync(() => Settings.open('${dir.path}/settings.json'));
        final lock = AppLock(api: NoLockApi(methodIs: LockMethod.faceId));
        await t.runAsync(() => lock.init(settings!, unlocked: true));
        final where = BlessingPlace(settings: settings!, locator: FakeLocator(LocationStatus.granted));
        await show(
            t,
            SettingsLayer(
              palette: p,
              lock: lock,
              where: where,
              language: null,
              version: '1.0',
              onBack: () {},
              onLock: (_) {},
              onLanguage: (_) {},
              onUseLocation: () {},
              onPassAlong: () {},
              onYourLinks: () {},
            ));
        expect(t.takeException(), isNull);
        wholeWords(t, find.byKey(const Key('settings-title')));
        final use = find.byKey(const Key('settings-use-location'));
        await t.ensureVisible(use);
        await t.pump();
        inside(t, find.descendant(of: use, matching: find.text(Strings.useMyLocation)), use);
      });

      testWidgets('the entry page title and the date sheet: no word broken', (t) async {
        final b = enteredBlessing(DateTime(2026, 11, 18), place: saltLakeTemple);
        await show(t, ReviewLayer(palette: p, blessing: b, on: true, player: FakePlayer(), onSave: () async {}, onBack: () {}, onFinish: () {}));
        expect(t.takeException(), isNull);
        wholeWords(t, find.text(Strings.titlePlaceholder));
        await show(
            t,
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DateSheet(palette: p, initial: (precision: DatePrecision.day, year: 2026, month: 11, day: 18), today: DateTime(2026, 11, 18), onDone: (_) {}),
              ),
            ));
        expect(t.takeException(), isNull);
        wholeWords(t, find.text(Strings.whenGiven));
        for (final label in [Strings.fullDateChoice, Strings.monthAndYear, Strings.yearOnly]) {
          wholeWords(t, find.text(label));
        }
      });

      testWidgets('Unlock: its word whole inside its pill', (t) async {
        await show(t, Center(child: UnlockButton(key: const Key('unlock'), palette: p, onTap: () {})));
        expect(t.takeException(), isNull);
        inside(t, find.byKey(const Key('unlock-text')), find.byKey(const Key('unlock')));
      });
    });
  }

  testWidgets('at the usual size the large titles are as they were, and nothing shades the top at rest', (t) async {
    final settings = await t.runAsync(() => Settings.open('${dir.path}/settings.json'));
    final lock = AppLock(api: NoLockApi(methodIs: LockMethod.faceId));
    await t.runAsync(() => lock.init(settings!, unlocked: true));
    final where = BlessingPlace(settings: settings!, locator: FakeLocator(LocationStatus.granted));
    await show(
        t,
        SettingsLayer(
          palette: p,
          lock: lock,
          where: where,
          language: null,
          version: '1.0',
          onBack: () {},
          onLock: (_) {},
          onLanguage: (_) {},
          onUseLocation: () {},
        ),
        scale: 1);
    final title = t.widget<Text>(find.byKey(const Key('settings-title')));
    expect(title.textScaler!.scale(34), 34);
    double shade() => t.widget<Opacity>(find.descendant(of: find.byType(ScrolledUnderShade), matching: find.byType(Opacity))).opacity;
    expect(shade(), 0);
    await t.drag(find.byKey(const Key('settings-scroll')), const Offset(0, -200));
    await t.pump();
    expect(shade(), 1);
  });
}

