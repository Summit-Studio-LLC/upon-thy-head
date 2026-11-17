import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:upon_thy_head/not_yet.dart';
import 'package:upon_thy_head/onboarding/first_run.dart';
import 'package:upon_thy_head/onboarding/first_run_screens.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/icons.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/strings.dart';

/// The phone's answers, scripted; records the order the questions were put.
class FakeAsker implements FirstRunAsker {
  FakeAsker({
    this.mic = Permission.undetermined,
    this.speechNow = Permission.undetermined,
    this.loc = LocationStatus.undetermined,
    this.bio = const Biometry(type: 'faceID', state: 'ok', passcode: true),
    this.micAnswer = Permission.granted,
    this.speechAnswer = Permission.granted,
    this.locAnswer = LocationStatus.granted,
    this.bioAnswer = const Biometry(type: 'faceID', state: 'ok', passcode: true),
  });
  Permission mic, speechNow, micAnswer, speechAnswer;
  LocationStatus loc, locAnswer;
  Biometry bio, bioAnswer;
  final List<String> asked = [];

  @override
  Future<Permission> microphone() async => mic;
  @override
  Future<Permission> askMicrophone() async {
    asked.add('microphone');
    return mic = micAnswer;
  }

  @override
  Future<Permission> speech() async => speechNow;
  @override
  Future<Permission> askSpeech() async {
    asked.add('speech');
    return speechNow = speechAnswer;
  }

  @override
  Future<LocationStatus> location() async => loc;
  @override
  Future<LocationStatus> askLocation() async {
    asked.add('location');
    return loc = locAnswer;
  }

  @override
  Future<Biometry> biometry() async => bio;
  @override
  Future<Biometry> askBiometrics(String reason) async {
    asked.add('faceID');
    return bio = bioAnswer;
  }

  int settingsOpened = 0;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Settings settings;

  setUp(() async {
    Strings.use(UiLanguage.english);
    dir = await Directory.systemTemp.createTemp('first_run_test');
    settings = await Settings.open('${dir.path}/settings.json');
  });
  tearDown(() => dir.delete(recursive: true));

  group('where a launch begins', () {
    test('a fresh install: the opening', () {
      expect(firstRunStart(null, hasBlessings: false, fileWaiting: false), FirstRunStart.opening);
    });
    test('a fresh install opened by a blessing file: read first', () {
      expect(firstRunStart(null, hasBlessings: false, fileWaiting: true), FirstRunStart.shared);
    });
    test('an install that already has blessings never sees it', () {
      expect(firstRunStart(null, hasBlessings: true, fileWaiting: false), FirstRunStart.none);
      expect(firstRunStart(null, hasBlessings: true, fileWaiting: true), FirstRunStart.none);
      expect(firstRunStart(FirstRun.existing, hasBlessings: false, fileWaiting: false), FirstRunStart.none);
    });
    test('killed on the permissions screen: back to it, with no opening', () {
      expect(firstRunStart(FirstRun.permissions, hasBlessings: false, fileWaiting: false), FirstRunStart.permissions);
    });
    test('killed at the rehearsal: back to its question', () {
      expect(firstRunStart(FirstRun.rehearsal, hasBlessings: false, fileWaiting: false), FirstRunStart.rehearsal);
    });
    test('after a shared first launch, kept or not: the rest at the next launch', () {
      expect(firstRunStart(FirstRun.rest, hasBlessings: true, fileWaiting: false), FirstRunStart.permissions);
      expect(firstRunStart(FirstRun.rest, hasBlessings: false, fileWaiting: false), FirstRunStart.permissions);
    });
    test('done: never again, whatever is in the store', () {
      for (final has in [true, false]) {
        for (final file in [true, false]) {
          expect(firstRunStart(FirstRun.done, hasBlessings: has, fileWaiting: file), FirstRunStart.none);
        }
      }
    });
    test('the recording screen asks only those who have not been through it', () {
      expect(recordScreenMayAsk(FirstRun.done), isFalse);
      expect(recordScreenMayAsk(FirstRun.existing), isTrue);
      expect(recordScreenMayAsk(FirstRun.rest), isTrue);
      expect(recordScreenMayAsk(null), isTrue);
    });
  });

  group('kept in the settings file', () {
    test('the step and Face ID asked survive a relaunch', () async {
      expect(settings.firstRun, isNull);
      expect(settings.faceIdAsked, isFalse);
      await settings.setFirstRun(FirstRun.rehearsal);
      await settings.setFaceIdAsked();
      final again = await Settings.open(settings.path);
      expect(again.firstRun, FirstRun.rehearsal);
      expect(again.faceIdAsked, isTrue);
    });
  });

  group('the permissions screen', () {
    FirstRunPermissions perms(FakeAsker a) => FirstRunPermissions(asker: a, settings: settings);
    PermissionRow row(FirstRunPermissions p, PermissionKind k) => p.row(k)!;

    test('nothing is asked until a row\'s Allow; each Allow puts its own question and no other', () async {
      final a = FakeAsker();
      final p = perms(a);
      await p.load();
      expect(a.asked, isEmpty);
      expect(p.rows.map((r) => r.status), everyElement(RowStatus.waiting));
      // the order of acceptance case 2: Face ID, Location, Speech, Microphone
      for (final (k, name) in [
        (PermissionKind.lock, 'faceID'),
        (PermissionKind.location, 'location'),
        (PermissionKind.speech, 'speech'),
        (PermissionKind.microphone, 'microphone'),
      ]) {
        final before = a.asked.length;
        await p.ask(k);
        expect(a.asked.sublist(before), [name]);
        expect(row(p, k).status, RowStatus.allowed);
      }
      expect(p.asking, isNull);
      expect(settings.locationAsked, isTrue);
      expect(settings.faceIdAsked, isTrue);
    });

    test('Continue opens once both required rows are answered, optional ones untouched', () async {
      final a = FakeAsker();
      final p = perms(a);
      expect(p.canContinue, isFalse); // not loaded
      await p.load();
      expect(p.canContinue, isFalse);
      expect(p.stillNeeded, [PermissionKind.microphone, PermissionKind.speech]);
      expect(Strings.stillNeeded(microphone: true, speech: true), 'Allow the microphone and speech recognition to go on.');
      await p.ask(PermissionKind.microphone);
      expect(p.canContinue, isFalse);
      expect(p.stillNeeded, [PermissionKind.speech]);
      expect(Strings.stillNeeded(microphone: false, speech: true), 'Allow speech recognition to go on.');
      await p.ask(PermissionKind.speech);
      expect(p.canContinue, isTrue);
      expect(row(p, PermissionKind.location).status, RowStatus.waiting);
      expect(row(p, PermissionKind.lock).status, RowStatus.waiting);
      expect(settings.faceIdAsked, isFalse); // the lock asks the first time it locks
      expect(a.asked, ['microphone', 'speech']);
    });

    test('a refused required row still lets the person go on; Settings opens the app\'s page', () async {
      final a = FakeAsker(micAnswer: Permission.denied);
      final p = perms(a);
      await p.load();
      await p.ask(PermissionKind.microphone);
      expect(row(p, PermissionKind.microphone).status, RowStatus.off);
      expect(p.canContinue, isFalse);
      await p.ask(PermissionKind.speech);
      expect(p.canContinue, isTrue);
      expect(p.microphoneAllowed, isFalse);
      // iOS never asks twice: a second tap puts nothing
      await p.ask(PermissionKind.microphone);
      expect(a.asked, ['microphone', 'speech']);
      await p.openSettings();
      expect(a.settingsOpened, 1);
      // turned on in Settings, back in the app: the row updates
      a.mic = Permission.granted;
      await p.recheck();
      expect(row(p, PermissionKind.microphone).status, RowStatus.allowed);
    });

    test('a refused row says so; location names the Salt Lake Temple', () async {
      final a = FakeAsker(micAnswer: Permission.denied, locAnswer: LocationStatus.denied, bioAnswer: const Biometry(type: 'faceID', state: 'denied', passcode: true));
      final p = perms(a);
      await p.load();
      for (final k in PermissionKind.values) {
        await p.ask(k);
      }
      expect(row(p, PermissionKind.microphone).status, RowStatus.off);
      expect(row(p, PermissionKind.microphone).line, Strings.microphoneWhy);
      expect(row(p, PermissionKind.microphone).semantics, 'Microphone. Required. To hear the blessing as it is given. Off');
      expect(row(p, PermissionKind.location).line, contains('Salt Lake Temple'));
      expect(row(p, PermissionKind.lock).status, RowStatus.off);
      expect(row(p, PermissionKind.speech).status, RowStatus.allowed);
    });

    test('one question at a time: an Allow while another is up does nothing', () async {
      final a = FakeAsker();
      final p = perms(a);
      await p.load();
      final first = p.ask(PermissionKind.microphone);
      expect(p.asking, PermissionKind.microphone);
      expect(p.canContinue, isFalse);
      await p.ask(PermissionKind.speech);
      await first;
      expect(a.asked, ['microphone']);
    });

    test('rows decided before are shown and not asked again', () async {
      final a = FakeAsker(mic: Permission.granted, speechNow: Permission.denied, loc: LocationStatus.granted);
      final p = perms(a);
      await p.load();
      expect(p.rows.map((r) => r.status), [RowStatus.allowed, RowStatus.off, RowStatus.allowed, RowStatus.waiting]);
      expect(p.canContinue, isTrue);
      for (final k in PermissionKind.values.take(3)) {
        await p.ask(k);
      }
      expect(a.asked, isEmpty);
    });

    test('resumed after a kill with two rows answered: those two shown answered, nothing asked twice', () async {
      await settings.setLocationAsked(); // Allow Once reads as unanswered again at the next launch
      final a = FakeAsker(mic: Permission.granted);
      final p = perms(a);
      await p.load();
      expect(p.rows.map((r) => r.status), [RowStatus.allowed, RowStatus.waiting, RowStatus.allowed, RowStatus.waiting]);
      await p.ask(PermissionKind.location);
      expect(a.asked, isEmpty);
      // and a recheck keeps that Allow Once as allowed
      await p.recheck();
      expect(row(p, PermissionKind.location).status, RowStatus.allowed);
    });

    test('no passcode: the lock row shows the Settings line, has no control, and is not asked', () async {
      final a = FakeAsker(bio: const Biometry(type: 'faceID', state: 'noPasscode', passcode: false));
      final p = perms(a);
      await p.load();
      await p.ask(PermissionKind.lock);
      expect(a.asked, isEmpty);
      final lock = p.rows.last;
      expect(lock.status, RowStatus.info);
      expect(lock.line, Strings.noPasscode);
    });

    test('no Face ID enrolled: the passcode line, not asked', () async {
      final a = FakeAsker(bio: const Biometry(type: 'faceID', state: 'notEnrolled', passcode: true));
      final p = perms(a);
      await p.load();
      expect(p.rows.last.status, RowStatus.info);
      expect(p.rows.last.line, contains('passcode'));
    });

    test('Touch ID has no question: shown as on, named for it', () async {
      final a = FakeAsker(bio: const Biometry(type: 'touchID', state: 'ok', passcode: true));
      final p = perms(a);
      await p.load();
      expect(p.rows.last.title, 'Touch ID');
      expect(p.rows.last.status, RowStatus.allowed);
    });

    Future<void> pumpRow(WidgetTester t, PermissionRow r, double scale, {double width = 346}) async {
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: PermissionRowView(palette: Palette.vigil, row: r)))),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
    }

    for (final scale in [1.0, 1.24, 1.76, 3.12]) {
      testWidgets('the icon sits on the middle of the title and the reason\'s first line at $scale', (t) async {
        for (final lang in UiLanguage.values) {
          Strings.use(lang);
          for (final r in [
            const PermissionRow(PermissionKind.microphone, RowStatus.waiting),
            const PermissionRow(PermissionKind.speech, RowStatus.asking),
            const PermissionRow(PermissionKind.location, RowStatus.off),
            const PermissionRow(PermissionKind.lock, RowStatus.allowed, name: 'Face ID'),
            const PermissionRow(PermissionKind.lock, RowStatus.waiting, name: 'Face ID'),
          ]) {
            await pumpRow(t, r, scale);
            final icon = find.byType(GlyphIcon);
            expect(t.getSize(icon), const Size(22, 22));
            final title = t.getRect(find.byKey(const Key('row-title')));
            final line = t.getRect(find.text(r.line));
            final firstLine = 21 * scale;
            final centre = (title.top + line.top + firstLine) / 2;
            expect((t.getRect(icon).center.dy - centre).abs(), lessThan(1), reason: '${lang.name} ${r.title} ${r.status.name}');
            // the icon sits below the title's top: lower than before
            expect(t.getRect(icon).top, greaterThan(title.top + 1), reason: r.title);
          }
        }
        Strings.use(UiLanguage.english);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the Allow button: beside the words at the normal size, beneath them at the largest', (t) async {
      const r = PermissionRow(PermissionKind.speech, RowStatus.waiting);
      await pumpRow(t, r, 1.0);
      final allow = find.byKey(const Key('allow-speech'));
      expect(allow, findsOneWidget);
      expect(t.getRect(allow).left, greaterThan(t.getRect(find.byKey(const Key('row-title'))).left + 100));
      expect(t.getSemantics(allow).label, 'Allow speech recognition');
      await pumpRow(t, r, 3.12);
      expect(t.getRect(find.byKey(const Key('allow-speech'))).top, greaterThan(t.getRect(find.text(r.line)).top));
      expect(t.takeException(), isNull);
    });

    // Answering a row must not move anything: its words keep their width and the row its height,
    // from Allow to the asking dot to the tick, in both languages, up to the first accessibility size
    // (1.76). Refused, Off and Settings go beneath the words, which still keep their width.
    for (final scale in [1.0, 1.24, 1.76]) {
      testWidgets('nothing moves when a row is answered at $scale', (t) async {
        for (final lang in UiLanguage.values) {
          Strings.use(lang);
          for (final k in PermissionKind.values) {
            final name = k == PermissionKind.lock ? 'Face ID' : null;
            ({Rect row, Rect title, Rect line})? first;
            for (final st in [RowStatus.waiting, RowStatus.asking, RowStatus.allowed, RowStatus.off]) {
              final r = PermissionRow(k, st, name: name);
              await pumpRow(t, r, scale);
              final now = (
                row: t.getRect(find.byType(PermissionRowView)),
                title: t.getRect(find.byKey(const Key('row-title'))),
                line: t.getRect(find.text(r.line)),
              );
              final why = '${lang.name} ${k.name} ${st.name} at $scale';
              if (first == null) {
                first = now;
                continue;
              }
              expect(now.title.width, closeTo(first.title.width, .01), reason: 'the title re-wrapped: $why');
              expect(now.title.top, closeTo(first.title.top, .01), reason: 'the title moved: $why');
              if (st == RowStatus.off) {
                // (refused, location's line becomes a different, shorter one)
                if (k != PermissionKind.location) expect(now.row.height, greaterThanOrEqualTo(first.row.height - .01), reason: why);
              } else {
                expect(now.line.size, first.line.size, reason: 'the reason re-wrapped: $why');
                expect(now.row.height, closeTo(first.row.height, .01), reason: 'the row changed height: $why');
              }
            }
          }
        }
        Strings.use(UiLanguage.english);
        expect(t.takeException(), isNull);
      });
    }

    test('Android: the microphone is asked and required, notifications asked and optional, location and lock not yet', () async {
      NotYet.debugAndroid = true;
      addTearDown(() => NotYet.debugAndroid = false);
      for (final lang in UiLanguage.values) {
        Strings.use(lang);
        final a = FakeAsker(speechAnswer: Permission.denied);
        final p = perms(a);
        await p.load();
        expect(p.rows.map((r) => r.title), [Strings.microphone, Strings.notifications, Strings.location, Strings.screenLock]);
        expect(p.rows.map((r) => r.status), [RowStatus.waiting, RowStatus.waiting, RowStatus.info, RowStatus.info]);
        expect(p.rows[1].reason, Strings.notificationsWhy);
        for (final r in p.rows.skip(2)) {
          expect(r.line, endsWith(Strings.notYetOnThisPhone), reason: r.title);
        }
        expect(p.stillNeeded, [PermissionKind.microphone], reason: 'notifications are optional');
        expect(p.canContinue, isFalse);
        await p.ask(PermissionKind.speech); // the Notifications row
        expect(p.rows[1].status, RowStatus.off);
        expect(p.rows[1].reason, Strings.notificationsWhy, reason: 'kept through the answer');
        expect(p.canContinue, isFalse);
        await p.ask(PermissionKind.microphone);
        expect(p.canContinue, isTrue, reason: 'refused notifications never hold up recording');
        expect(Strings.permsLede, contains(lang == UiLanguage.english ? 'Allow' : 'Permitir'));
      }
      Strings.use(UiLanguage.english);
    });

    testWidgets('refused: Off and Settings in place of Allow; allowed: the tick', (t) async {
      await pumpRow(t, const PermissionRow(PermissionKind.microphone, RowStatus.off), 1.0);
      expect(find.text('Off'), findsOneWidget);
      expect(t.getSemantics(find.byKey(const Key('settings-microphone'))).label, 'Open Settings to allow microphone');
      expect(find.byKey(const Key('allow-microphone')), findsNothing);
      await pumpRow(t, const PermissionRow(PermissionKind.microphone, RowStatus.allowed), 1.0);
      expect(find.byKey(const Key('mark-allowed')), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('Continue is unavailable to VoiceOver until both required rows are answered', (t) async {
      final a = FakeAsker();
      final p = perms(a);
      await p.load();
      final handle = t.ensureSemantics();
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: Directionality(textDirection: TextDirection.ltr, child: PermissionsLayer(palette: Palette.vigil, state: p, onContinue: () {})),
      ));
      await t.pump(const Duration(milliseconds: 400));
      final cont = find.byKey(const Key('permissions-continue'));
      expect(t.getSemantics(cont), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
      expect(find.text('Allow the microphone and speech recognition to go on.'), findsOneWidget);
      await p.ask(PermissionKind.microphone);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Allow speech recognition to go on.'), findsOneWidget);
      await p.ask(PermissionKind.speech);
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getSemantics(cont), isSemantics(isButton: true, hasEnabledState: true, isEnabled: true));
      expect(t.takeException(), isNull);
      handle.dispose();
    });

    test('every row and state has words for VoiceOver, in Spanish too', () async {
      for (final lang in UiLanguage.values) {
        Strings.use(lang);
        for (final k in PermissionKind.values) {
          for (final s in RowStatus.values) {
            final r = PermissionRow(k, s);
            expect(r.semantics.trim(), isNotEmpty);
            expect(r.title.trim(), isNotEmpty);
          }
        }
      }
      Strings.use(UiLanguage.spanish);
      expect(const PermissionRow(PermissionKind.location, RowStatus.off).semantics, contains('Desactivada'));
      expect(const PermissionRow(PermissionKind.microphone, RowStatus.waiting).semantics, contains('Obligatorio'));
      expect(Strings.allowFor(Strings.microphone), 'Permitir micrófono');
      expect(Strings.allowFor('Face ID'), 'Permitir Face ID');
    });
  });

  group('the practice', () {
    test('the ring is Amen from the start, and no recording note is written', () async {
      final practice = Directory('${dir.path}/practice');
      final s = RecordSession(practice: true, audioDir: practice.path)..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
      await s.checkPermissions(ask: false);
      expect(s.amen, isFalse); // not listening yet
      await s.begin();
      expect(s.amen, isTrue);
      expect(practice.existsSync() ? practice.listSync().map((f) => f.path.split('/').last).where((n) => n.endsWith('.json')) : const [], isEmpty);
      final file = await s.finish();
      expect(file, isNotNull);
      s.dispose();

      final normal = RecordSession(audioDir: '${dir.path}/audio')..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
      await normal.checkPermissions(ask: false);
      await normal.begin();
      expect(normal.amen, isFalse); // Discard for the first ten seconds
      expect(Directory('${dir.path}/audio').listSync(), isNotEmpty); // its recording note
      normal.discard();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      normal.dispose();
    });
  });

  group('moving between steps', () {
    tearDown(() => firstRunVisible.value = true);

    testWidgets('the opening\'s timer stops while the app cannot be seen, and goes on after', (t) async {
      var fired = 0;
      final timer = PausableTimer(const Duration(milliseconds: 1000), () => fired++);
      await t.pump(const Duration(milliseconds: 600));
      firstRunVisible.value = false; // a question over the app, the app switcher
      await t.pump(const Duration(seconds: 5));
      expect(fired, 0, reason: 'the name must not be skipped past while nobody can see it');
      firstRunVisible.value = true;
      await t.pump(const Duration(milliseconds: 300));
      expect(fired, 0);
      await t.pump(const Duration(milliseconds: 200));
      expect(fired, 1);
      expect(timer.isActive, isFalse);
    });

    testWidgets('a line of the welcome waits while the app cannot be seen', (t) async {
      firstRunVisible.value = false;
      await t.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: WhileVisible(child: Arrive(delay: Duration(milliseconds: 500), child: Text('In the name of'))),
      ));
      await t.pump(const Duration(seconds: 3));
      double opacity() => t.widget<AnimatedOpacity>(find.ancestor(of: find.text('In the name of'), matching: find.byType(AnimatedOpacity)).first).opacity;
      expect(opacity(), 0);
      firstRunVisible.value = true;
      await t.pump(const Duration(milliseconds: 600));
      expect(opacity(), 1);
    });

    Future<void> pumpStep(WidgetTester t, {required bool welcome, bool still = false}) => t.pumpWidget(MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), disableAnimations: still),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(children: [
              // as the home screen does: the move is turned on as the step begins
              Positioned.fill(key: const ValueKey('w'), child: FirstRunFade(on: welcome, slide: !welcome, child: const Center(child: Text('welcome')))),
              if (!welcome) Positioned.fill(key: const ValueKey('p'), child: FirstRunFade(on: !welcome, slide: true, child: const Center(child: Text('permissions')))),
            ]),
          ),
        ));

    double x(WidgetTester t, String s) => t.getCenter(find.text(s)).dx;

    testWidgets('Continue from the welcome: it leaves to the left as the permissions arrive from the right, together', (t) async {
      await pumpStep(t, welcome: true);
      await t.pumpAndSettle();
      final home = x(t, 'welcome');
      await pumpStep(t, welcome: false);
      await t.pump();
      expect(x(t, 'permissions'), greaterThan(home + 20), reason: 'arrives from a short way right');
      await t.pump(const Duration(milliseconds: 200));
      expect(x(t, 'welcome'), lessThan(home - 5), reason: 'the welcome is on its way left');
      final mid = t.widget<AnimatedOpacity>(find.ancestor(of: find.text('welcome'), matching: find.byType(AnimatedOpacity)).first);
      expect(mid.opacity, 0);
      final shown = t.renderObject<RenderAnimatedOpacity>(find.byWidget(mid)).opacity.value;
      expect(shown, inExclusiveRange(.15, .85), reason: 'fading, not gone at once (found 2026-11-16 in the film)');
      expect(x(t, 'permissions'), greaterThan(home), reason: 'at the same time');
      await t.pump(const Duration(milliseconds: 250));
      expect(x(t, 'permissions'), closeTo(home, .01));
      expect(x(t, 'welcome'), closeTo(home - slideDistance, .01));
      expect(t.widget<AnimatedOpacity>(find.ancestor(of: find.text('welcome'), matching: find.byType(AnimatedOpacity)).first).opacity, 0);
    });

    testWidgets('Reduce Motion: a plain crossfade, nothing moves', (t) async {
      await pumpStep(t, welcome: true, still: true);
      await t.pumpAndSettle();
      final home = x(t, 'welcome');
      await pumpStep(t, welcome: false, still: true);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 80));
        expect(x(t, 'welcome'), home);
        expect(x(t, 'permissions'), home);
      }
    });

    testWidgets('nothing on the step being left takes a touch', (t) async {
      await pumpStep(t, welcome: true);
      await t.pumpAndSettle();
      await pumpStep(t, welcome: false);
      await t.pump();
      final leaving = find.ancestor(of: find.text('welcome'), matching: find.byType(IgnorePointer)).first;
      expect(t.widget<IgnorePointer>(leaving).ignoring, isTrue);
    });
  });
}
