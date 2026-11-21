// The iPad pass, on the host: the main screens pumped at iPad sizes (11-inch and 13-inch, portrait
// and landscape, and a third-of-screen Split View window) fail on any overflow, and their reading
// and form columns keep a measure; sheets are centred cards on a wide screen. At the iPhone 17 Pro's
// size the same screens must draw exactly as they did before the iPad pass (goldens in
// test/goldens/iphone/, made from the code before it).
//
//   flutter test test/ipad_layout_test.dart
//   flutter test test/ipad_layout_test.dart --update-goldens   (only when an iPhone change is meant)

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/people/family_pages.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/read/read_screen.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/share/share_sheet.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/sheet.dart';

import 'lock_place_test.dart' show FakeLocator;
import 'screen_reader_test.dart' show FakePlayer, FakeShare, surgery;

const p = Palette.lamplight;
const iPhone = Size(402, 874);

/// name, logical size, safe-area padding
const iPads = <(String, Size, EdgeInsets)>[
  ('11-portrait', Size(820, 1180), EdgeInsets.only(top: 24, bottom: 20)),
  ('11-landscape', Size(1180, 820), EdgeInsets.only(top: 24, bottom: 20)),
  ('13-portrait', Size(1032, 1376), EdgeInsets.only(top: 24, bottom: 20)),
  ('13-landscape', Size(1376, 1032), EdgeInsets.only(top: 24, bottom: 20)),
  ('narrow-320', Size(320, 1180), EdgeInsets.only(top: 24, bottom: 20)),
  ('narrow-375', Size(375, 1032), EdgeInsets.only(top: 24, bottom: 20)),
];

/// The widest a reading or form column may be (points), and the widest a sheet's card.
const measure = 680.0, card = 600.0;

/// A RenderFlex overflow's full report, printed (the tester keeps only its first line).
void Function(FlutterErrorDetails)? _print(void Function(FlutterErrorDetails)? was) => (d) {
      if ('${d.exception}'.contains('overflowed')) debugPrint('OVERFLOW ${d.toString().split('\n').where((l) => l.contains('creator') || l.contains('lib/')).take(4).join(' | ')}');
      was?.call(d);
    };

Future<void> show(WidgetTester t, Widget child, {Size screen = iPhone, EdgeInsets padding = const EdgeInsets.only(top: 62, bottom: 34), double scale = 1}) async {
  t.view.physicalSize = screen * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final was = FlutterError.onError;
  FlutterError.onError = _print(was);
  addTearDown(() => FlutterError.onError = was);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: screen, devicePixelRatio: 3, padding: padding, viewPadding: padding, textScaler: TextScaler.linear(scale)),
    child: CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: ColoredBox(color: p.ground, child: child),
    ),
  ));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Every piece of text drawn: none may be wider than the measure, and none off the screen.
void measured(WidgetTester t, Size screen, String where) {
  for (final e in find.byType(RichText).evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    // as drawn: a label a FittedBox scales down to fit is measured at its drawn size
    final r = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    if (r.width < 1) continue;
    expect(r.width, lessThanOrEqualTo(measure + .5), reason: '$where: a line ${r.width.toStringAsFixed(0)} wide on a ${screen.width} screen');
    expect(r.left >= -.5 && r.right <= screen.width + .5, isTrue,
        reason: '$where: "${(e.widget as RichText).text.toPlainText()}" at $r off a ${screen.width} wide screen');
  }
}

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('ipad_layout'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  Widget read() => ReadLayer(
        palette: p,
        blessing: surgery(),
        placement: const OverheadPlacement(),
        on: true,
        onBack: () {},
        onReview: () {},
        onDelete: () async => false,
        onChanges: () {},
        share: FakeShare(),
      );

  Widget review() => ReviewLayer(
        palette: p,
        blessing: surgery()..draft = true,
        on: true,
        player: FakePlayer(),
        audioPath: '${dir.path}/a.m4a',
        knownTags: const ['healing', 'family'],
        onSave: () async {},
        onBack: () {},
        onFinish: () {},
        onChanges: () {},
        onOwnership: (_) {},
      );

  Future<Widget> settingsPage(WidgetTester t) async {
    final settings = await t.runAsync(() => Settings.open('${dir.path}/settings.json'));
    final lock = AppLock(api: NoLockApi(methodIs: LockMethod.touchId));
    await t.runAsync(() => lock.init(settings!, unlocked: true));
    final where = BlessingPlace(settings: settings!, locator: FakeLocator(LocationStatus.granted));
    return SettingsLayer(
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
    );
  }

  Widget confirm() => Stack(children: [
        Positioned.fill(
          child: ConfirmSheet(
            palette: p,
            on: true,
            barrier: true,
            panelKey: const Key('confirm-panel'),
            title: Strings.deleteTitle,
            body: Strings.deleteBody,
            dangerLabel: Strings.delete,
            safeLabel: Strings.keep,
            onDanger: () {},
            onSafe: () {},
          ),
        ),
      ]);

  Widget shareSheet() => Stack(children: [
        Positioned.fill(child: ShareSheet(palette: p, on: true, blessing: surgery(), share: FakeShare(), links: null, onClose: () {}, onSent: (_, _) {})),
      ]);

  Widget receive() => Stack(children: [
        Positioned.fill(
          child: ReceiveSheet(palette: p, on: true, arrival: ArrivalNew(BlessingRecord.of(surgery())), onKeep: () {}, onNotNow: () {}),
        ),
      ]);

  Widget family() => FamilyLayer(
        palette: p,
        people: [Person(id: 'e', name: 'Emma', born: Day(2014, 8, 3), created: DateTime.utc(2026))],
        countLine: (_) => 'Two blessings since 2024',
        onBack: () {},
        onOpen: (_) {},
        onAdd: () {},
      );

  final screens = <String, Future<Widget> Function(WidgetTester)>{
    'read': (_) async => read(),
    'review': (_) async => review(),
    'settings': settingsPage,
    'confirm': (_) async => confirm(),
    'share-sheet': (_) async => shareSheet(),
    'receive': (_) async => receive(),
    'family': (_) async => family(),
  };

  group('iPhone 17 Pro: the same pixels as before the iPad pass', () {
    for (final e in screens.entries) {
      testWidgets(e.key, (t) async {
        Strings.use(UiLanguage.english);
        await show(t, await e.value(t));
        await expectLater(find.byType(CupertinoApp), matchesGoldenFile('goldens/iphone/${e.key}.png'));
      });
    }
  });

  for (final (name, size, padding) in iPads) {
    group('iPad $name', () {
      for (final e in screens.entries) {
        for (final lang in UiLanguage.values) {
          testWidgets('${e.key} ${lang.name}', (t) async {
            Strings.use(lang);
            await show(t, await e.value(t), screen: size, padding: padding);
            measured(t, size, '${e.key} $name ${lang.name}');
          });
        }
        testWidgets('${e.key} at the largest text', (t) async {
          Strings.use(UiLanguage.english);
          await show(t, await e.value(t), screen: size, padding: padding, scale: 3.1);
          final error = t.takeException();
          expect(error, isNull);
        });
      }
      testWidgets('a confirmation is a centred card, not a full-width slab', (t) async {
        Strings.use(UiLanguage.english);
        await show(t, confirm(), screen: size, padding: padding);
        final r = t.getRect(find.byKey(const Key('confirm-panel')));
        expect(r.width, lessThanOrEqualTo(size.width > card ? card + .5 : size.width + .5), reason: 'the card is ${r.width} wide');
        expect((r.center.dx - size.width / 2).abs(), lessThan(1), reason: 'the card is centred');
      });
    });
  }

  tearDown(() => Strings.use(UiLanguage.english));
}
