// The fixes before the first App Store submission (2026-11-20): the listen bar at the largest text
// on a narrow phone, the ring kept below home's head on an iPad in landscape, a new light's
// cross-fade with Reduce Motion, and About's Privacy, Terms and credits. (The glass menu's count
// line is checked in people_widgets_test.dart, at the largest text.)
//
//   flutter test test/store_fixes_test.dart

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';

import 'lock_place_test.dart' show FakeLocator;

const p = Palette.lamplight;

class _Player extends Player {
  @override
  double get position => 754;
  @override
  double get duration => 2701;
  @override
  bool get playing => false;
  @override
  Future<void> load(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(double seconds) async {}
  @override
  Future<void> unload() async {}
}

Future<void> show(WidgetTester t, Widget child, {Size screen = const Size(402, 874), double scale = 1}) async {
  t.view.physicalSize = screen * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: screen, devicePixelRatio: 3, textScaler: TextScaler.linear(scale)),
    child: CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: ColoredBox(color: p.ground, child: child),
    ),
  ));
  await t.pumpAndSettle();
}

Blessing _at(int year, double lat) => Blessing(
    id: 'b$year', title: 'B', from: '', utc: DateTime.utc(year, 3, 3), utcOffset: Duration.zero, place: Place(lat, -111.9), rawText: '', firstText: '', language: 'en');

void main() {
  tearDown(() => Strings.use(UiLanguage.english));

  group('the listen bar', () {
    for (final width in [320.0, 375.0]) {
      testWidgets('$width wide, text ×3.1: the time goes under the line, nothing overflows', (t) async {
        await show(t, Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.topCenter, child: ListenBar(palette: p, player: _Player()))),
            screen: Size(width, 800), scale: 3.1);
        expect(t.takeException(), isNull);
        final play = t.getRect(find.byKey(const Key('listen-play'))), time = t.getRect(find.byKey(const Key('listen-time')));
        expect(time.top, greaterThanOrEqualTo(play.bottom - .5), reason: 'under the controls');
        expect(time.right, lessThanOrEqualTo(width - 16 + .5));
      });
    }

    testWidgets('the usual size: the time beside the line, as before', (t) async {
      await show(t, Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.topCenter, child: ListenBar(palette: p, player: _Player()))));
      final play = t.getRect(find.byKey(const Key('listen-play'))), time = t.getRect(find.byKey(const Key('listen-time')));
      expect(time.center.dy, closeTo(play.center.dy, 1));
    });
  });

  group('the ring on a wide screen', () {
    test('a phone held upright, and any screen taller than wide, is never zoomed', () {
      for (final size in const [Size(402, 874), Size(320, 568), Size(820, 1180), Size(1032, 1376)]) {
        for (final lat in [-40.0, 0.0, 40.7, 55.0]) {
          expect(SkyEngine.fitBelow(size, lat * deg, 150), 1, reason: '$size at $lat');
        }
      }
    });

    for (final size in const [Size(1180, 820), Size(1376, 1032)]) {
      for (final lat in [30.0, 40.7, 51.5]) {
        test('$size at latitude $lat: the ring stays below the head', () {
          const head = 150.0;
          final b = [_at(2020, lat), _at(2023, lat), _at(2026, lat)];
          const RingPlacement().apply(b, now: DateTime.utc(2026, 6));
          final e = SkyEngine(b, focus: 1)
            ..clearTop = head
            ..snap()
            ..basis(size);
          expect(SkyEngine.fitBelow(size, lat * deg, head), lessThan(1), reason: 'it would have run behind the head');
          final o = Projected();
          for (final v in const OverheadPlacement().line(b)) {
            e.project(v, o);
            final onScreen = o.z > .05 && o.x >= 0 && o.x <= size.width && o.y >= 0;
            if (onScreen) expect(o.y, greaterThan(head), reason: 'the line at ${o.x.round()}, ${o.y.round()}');
          }
        });
      }
    }

    test('the southern sky curves away from the head and is left as it is', () {
      expect(SkyEngine.fitBelow(const Size(1180, 820), -33.9 * deg, 150), 1);
    });
  });

  test('Reduce Motion: a new light cross-fades in; the camera neither zooms nor drifts', () {
    final b = [_at(2020, 40.7), _at(2026, 40.7)];
    const RingPlacement().apply(b, now: DateTime.utc(2026, 6));
    final e = SkyEngine(b, focus: 1)
      ..reduceMotion = true
      ..setView(SkyView.review)
      ..snap();
    e
      ..setView(SkyView.home)
      ..setFocus(1, instant: true)
      ..crossFade();
    expect((e.fov, e.cy, e.lights), (SkyView.home.fov, SkyView.home.cy, 0.0));
    e.step(.25);
    expect((e.fov, e.cy), (SkyView.home.fov, SkyView.home.cy), reason: 'no zoom, no drift');
    expect(e.lights, inExclusiveRange(0, 1), reason: 'fading in');
    for (var i = 0; i < 60; i++) {
      e.step(1 / 30);
    }
    expect(e.lights, closeTo(1, .01));
  });

  group('About in Settings', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('uth-about'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> page(WidgetTester t, {double scale = 1}) async {
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
          ),
          scale: scale);
    }

    for (final lang in UiLanguage.values) {
      testWidgets('$lang: Privacy and Terms open their page by name; the credits are there', (t) async {
        Strings.use(lang);
        final opened = <Object?>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('upon_thy_head/lock'), (call) async {
          if (call.method == 'openPage') opened.add((call.arguments as Map)['name']);
          return null;
        });
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('upon_thy_head/lock'), null));
        final handle = t.ensureSemantics();
        await page(t);
        expect(find.text(Strings.credits), findsOneWidget);
        expect(Strings.credits, contains('HYG'));
        for (final (key, label, name) in [('settings-privacy', Strings.privacy, 'privacy'), ('settings-terms', Strings.terms, 'terms')]) {
          await t.scrollUntilVisible(find.byKey(Key(key)), 100, scrollable: find.byType(Scrollable).first);
          await t.pumpAndSettle();
          expect(t.getSemantics(find.byKey(Key(key))), matchesSemantics(isButton: true, hasTapAction: true, label: label));
          await t.tap(find.byKey(Key(key)));
          await t.pumpAndSettle();
          expect(opened.last, name);
        }
        expect(opened, ['privacy', 'terms']);
        handle.dispose();
      });
    }

    testWidgets('the largest text: nothing overflows', (t) async {
      await page(t, scale: 3.1);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('settings-credits')), findsOneWidget);
    });

    test('Android credits its speech engine in both languages', () {
      for (final lang in UiLanguage.values) {
        expect(Strings.wordsFor(lang).creditsAndroid, contains('whisper.cpp'));
      }
    });
  });
}
