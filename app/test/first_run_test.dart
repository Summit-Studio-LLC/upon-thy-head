import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:flutter/widgets.dart';
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
    FirstRunPermissions perms(FakeAsker a) => FirstRunPermissions(asker: a, settings: settings, beat: Duration.zero);

    test('Continue puts the four questions in order, each answered row marked', () async {
      final a = FakeAsker();
      final p = perms(a);
      await p.load();
      expect(p.rows.map((r) => r.status), everyElement(RowStatus.waiting));
      final lit = <PermissionKind?>[];
      p.addListener(() => lit.add(p.asking));
      await p.run();
      expect(a.asked, ['microphone', 'speech', 'location', 'faceID']);
      expect(lit.whereType<PermissionKind>().toSet(), PermissionKind.values.toSet());
      expect(p.rows.map((r) => r.status), everyElement(RowStatus.allowed));
      expect(p.asking, isNull);
      expect(settings.locationAsked, isTrue);
      expect(settings.faceIdAsked, isTrue);
    });

    test('a refused row says so; location names the Salt Lake Temple', () async {
      final a = FakeAsker(micAnswer: Permission.denied, locAnswer: LocationStatus.denied, bioAnswer: const Biometry(type: 'faceID', state: 'denied', passcode: true));
      final p = perms(a);
      await p.run();
      PermissionRow row(PermissionKind k) => p.rows.firstWhere((r) => r.kind == k);
      expect(row(PermissionKind.microphone).status, RowStatus.off);
      expect(row(PermissionKind.microphone).line, 'Off. You can turn it on in Settings.');
      expect(row(PermissionKind.location).line, contains('Salt Lake Temple'));
      expect(row(PermissionKind.lock).status, RowStatus.off);
      expect(row(PermissionKind.speech).status, RowStatus.allowed);
      expect(p.microphoneAllowed, isFalse);
    });

    test('rows decided before are shown and not asked again', () async {
      final a = FakeAsker(mic: Permission.granted, speechNow: Permission.denied, loc: LocationStatus.granted);
      final p = perms(a);
      await p.run();
      expect(a.asked, ['faceID']);
      expect(p.rows.map((r) => r.status), [RowStatus.allowed, RowStatus.off, RowStatus.allowed, RowStatus.allowed]);
    });

    test('resumed after a kill: nothing asked twice (Allow Once reads as unanswered again)', () async {
      await settings.setLocationAsked();
      await settings.setFaceIdAsked();
      final a = FakeAsker(mic: Permission.granted, speechNow: Permission.granted);
      final p = perms(a);
      await p.run();
      expect(a.asked, isEmpty);
      expect(p.rows.map((r) => r.status), everyElement(RowStatus.allowed));
    });

    test('no passcode: the lock row shows the Settings line and is not asked', () async {
      final a = FakeAsker(bio: const Biometry(type: 'faceID', state: 'noPasscode', passcode: false));
      final p = perms(a);
      await p.run();
      expect(a.asked, isNot(contains('faceID')));
      final lock = p.rows.last;
      expect(lock.status, RowStatus.info);
      expect(lock.line, Strings.noPasscode);
    });

    test('no Face ID enrolled: the passcode line, not asked', () async {
      final a = FakeAsker(bio: const Biometry(type: 'faceID', state: 'notEnrolled', passcode: true));
      final p = perms(a);
      await p.run();
      expect(a.asked, isNot(contains('faceID')));
      expect(p.rows.last.status, RowStatus.info);
      expect(p.rows.last.line, contains('passcode'));
    });

    test('Touch ID has no question: shown as on, named for it', () async {
      final a = FakeAsker(bio: const Biometry(type: 'touchID', state: 'ok', passcode: true));
      final p = perms(a);
      await p.run();
      expect(a.asked, isNot(contains('faceID')));
      expect(p.rows.last.title, 'Touch ID');
      expect(p.rows.last.status, RowStatus.allowed);
    });

    for (final scale in [1.0, 1.76, 3.12]) {
      testWidgets('each row has its icon, its size whatever the text, centred on the title at $scale', (t) async {
        for (final r in [
          const PermissionRow(PermissionKind.microphone, RowStatus.waiting),
          const PermissionRow(PermissionKind.speech, RowStatus.asking),
          const PermissionRow(PermissionKind.location, RowStatus.off),
          const PermissionRow(PermissionKind.lock, RowStatus.allowed, name: 'Face ID'),
        ]) {
          await t.pumpWidget(MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 340, child: PermissionRowView(palette: Palette.vigil, row: r)))),
            ),
          ));
          await t.pump(const Duration(milliseconds: 400));
          final icon = find.byType(GlyphIcon);
          expect(t.getSize(icon), const Size(22, 22));
          final title = t.getRect(find.text(r.title));
          final line = 20 * scale;
          final iconCentre = t.getRect(icon).center.dy;
          expect((iconCentre - (title.top + line / 2)).abs(), lessThan(1.5), reason: r.title);
        }
        expect(t.takeException(), isNull);
      });
    }

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
      expect(const PermissionRow(PermissionKind.microphone, RowStatus.off).line, contains('Configuración'));
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
}
