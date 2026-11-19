// Regression checks for recording startup rollback, review layout at 3.1× with the keyboard open,
// closing review while the date sheet is up, atomic transcript/audio store updates, fail-closed
// app lock initialization, settings persistence, and sky engine idle settling.
//
//   flutter test test/hardening_fixes_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/record/android_words.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/recovery.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/sheet.dart';

class _ControlledRecorder extends SilentRecorder {
  bool failStart = false;
  Completer<void>? startGate;
  int cancelCount = 0;

  @override
  Future<void> start(String path) async {
    if (startGate != null) await startGate!.future;
    if (failStart) throw StateError('microphone busy');
    await super.start(path);
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    await super.cancel();
  }
}

class _ThrowingLockApi extends NoLockApi {
  bool covered = false;

  @override
  Future<LockMethod> method() async => throw StateError('lock channel unavailable');

  @override
  Future<void> cover(bool on) async {
    covered = on;
  }
}

class _ReviewPlayer extends Player {
  @override
  double get position => 12;
  @override
  double get duration => 185;
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

void main() {
  tearDown(() => Strings.use(UiLanguage.english));

  group('RecordSession.begin fail-safe startup', () {
    test('rolls back to ready with startFailed, clears recording note, and resets on retry', () async {
      final dir = Directory.systemTemp.createTempSync('rec-fail');
      addTearDown(() => dir.deleteSync(recursive: true));
      final rec = _ControlledRecorder()..failStart = true;
      final draft = draftBlessing(DateTime.utc(2026, 11, 18, 12), place: const Place(40.8, -111.9));
      final s = RecordSession(recorder: rec, audioDir: dir.path)..draft = draft;
      addTearDown(s.dispose);
      await s.checkPermissions(ask: false);

      await s.begin();
      expect(s.state, RecordState.ready);
      expect(s.live, isFalse);
      expect(s.startFailed, isTrue);
      expect(s.elapsed, 0);
      expect(s.level.value, 0);
      expect(File(RecordingNote.pathFor(dir.path, draft.id)).existsSync(), isFalse);

      // Practice mode rolls back identically.
      final practice = RecordSession(recorder: rec, audioDir: dir.path, practice: true);
      addTearDown(practice.dispose);
      await practice.checkPermissions(ask: false);
      await practice.begin();
      expect(practice.state, RecordState.ready);
      expect(practice.startFailed, isTrue);

      // Once the microphone is free again, Begin clears startFailed and starts cleanly.
      rec.failStart = false;
      await s.begin();
      expect(s.live, isTrue);
      expect(s.startFailed, isFalse);
      s.discard();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('cancels native recording if discarded or disposed while start is awaiting', () async {
      final dir = Directory.systemTemp.createTempSync('rec-mid-start');
      addTearDown(() => dir.deleteSync(recursive: true));

      // Discarded mid-start.
      final gate1 = Completer<void>();
      final rec1 = _ControlledRecorder()..startGate = gate1;
      final s1 = RecordSession(recorder: rec1, audioDir: dir.path, practice: true);
      addTearDown(s1.dispose);
      await s1.checkPermissions(ask: false);
      final b1 = s1.begin();
      s1.discard();
      final cancelsAfterDiscard = rec1.cancelCount;
      gate1.complete();
      await b1;
      expect(rec1.cancelCount, greaterThan(cancelsAfterDiscard));
      expect(s1.live, isFalse);
      expect(s1.startFailed, isFalse);

      // Disposed mid-start.
      final gate2 = Completer<void>();
      final rec2 = _ControlledRecorder()..startGate = gate2;
      final s2 = RecordSession(recorder: rec2, audioDir: dir.path, practice: true);
      await s2.checkPermissions(ask: false);
      final b2 = s2.begin();
      s2.dispose();
      final cancelsAfterDispose = rec2.cancelCount;
      gate2.complete();
      await b2;
      expect(rec2.cancelCount, greaterThan(cancelsAfterDispose));
    });

    for (final lang in UiLanguage.values) {
      testWidgets('Ready screen shows startFailed notice in ${lang.name} without overflow', (t) async {
        Strings.use(lang);
        final dir = Directory.systemTemp.createTempSync('rec-screen');
        addTearDown(() => dir.deleteSync(recursive: true));
        final rec = _ControlledRecorder()..failStart = true;
        final s = RecordSession(recorder: rec, audioDir: dir.path, practice: true);
        addTearDown(s.dispose);
        await t.runAsync(() async {
          await s.checkPermissions(ask: false);
          await s.begin();
        });

        t.view.physicalSize = const Size(402, 874) * 3;
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 874),
            devicePixelRatio: 3,
            padding: EdgeInsets.only(top: 62, bottom: 34),
            viewPadding: EdgeInsets.only(top: 62, bottom: 34),
            textScaler: TextScaler.linear(3.1),
          ),
          child: CupertinoApp(
            localizationsDelegates: const [
              m.DefaultMaterialLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: ColoredBox(
              color: Palette.lamplight.ground,
              child: RecordLayer(
                palette: Palette.lamplight,
                session: s,
                onBegin: () {},
                onClose: () {},
                onDiscardEarly: () {},
                onAmen: () {},
                onLanguage: (_) {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('start-failed')), findsOneWidget);
        expect(find.text(Strings.startFailed), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  group('ReviewLayer pinned ListenBar and DateSheet lifecycle', () {
    for (final lang in UiLanguage.values) {
      testWidgets('pinned ListenBar with keyboard open at 3.1× text scale does not overflow (${lang.name})', (t) async {
        Strings.use(lang);
        final b = draftBlessing(DateTime.utc(2026, 11, 18, 12), place: saltLakeTemple)
          ..rawText = 'I bless you with peace and strength.'
          ..audio = 'b.m4a';
        t.view.physicalSize = const Size(328, 732) * 3;
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(MediaQuery(
          data: const MediaQueryData(
            size: Size(328, 732),
            devicePixelRatio: 3,
            padding: EdgeInsets.only(top: 62),
            viewPadding: EdgeInsets.only(top: 62),
            viewInsets: EdgeInsets.only(bottom: 280),
            textScaler: TextScaler.linear(3.1),
          ),
          child: CupertinoApp(
            localizationsDelegates: const [
              m.DefaultMaterialLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: ColoredBox(
              color: Palette.lamplight.ground,
              child: ReviewLayer(
                palette: Palette.lamplight,
                blessing: b,
                on: true,
                audioPath: '/tmp/b.m4a',
                words: WordsState.done,
                player: _ReviewPlayer(),
                onSave: () async {},
                onBack: () {},
                onFinish: () {},
              ),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 200));
        // Focus the words box so _pinned && keyboard > 0 mounts the pinned ListenBar.
        t.widget<CupertinoTextField>(find.byKey(const Key('review-words'))).focusNode!.requestFocus();
        await t.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const Key('listen-pinned')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('closing ReviewLayer while DateSheet is open resets Sheet.anyUp to false', (t) async {
      final b = enteredBlessing(DateTime(2026, 11, 18), place: saltLakeTemple);
      var open = true;
      late StateSetter setHost;
      t.view.physicalSize = const Size(402, 874) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          setHost = setState;
          return MediaQuery(
            data: const MediaQueryData(
              size: Size(402, 874),
              devicePixelRatio: 3,
              padding: EdgeInsets.only(top: 62),
              viewPadding: EdgeInsets.only(top: 62),
            ),
            child: CupertinoApp(
              localizationsDelegates: const [
                m.DefaultMaterialLocalizations.delegate,
                DefaultCupertinoLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
              ],
              home: ColoredBox(
                color: Palette.lamplight.ground,
                child: ReviewLayer(
                  palette: Palette.lamplight,
                  blessing: b,
                  on: open,
                  player: _ReviewPlayer(),
                  onSave: () async {},
                  onBack: () {},
                  onFinish: () {},
                ),
              ),
            ),
          );
        },
      ));
      await t.pump(const Duration(milliseconds: 200));
      expect(Sheet.anyUp, isFalse);

      await t.tap(find.byKey(const Key('review-given-row')));
      await t.pump(const Duration(milliseconds: 300));
      expect(Sheet.anyUp, isTrue);

      // Closing ReviewLayer (e.g. on lock or navigation) must take the DateSheet down too.
      setHost(() => open = false);
      await t.pump(const Duration(milliseconds: 300));
      expect(Sheet.anyUp, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Store, Lock, Settings, and SkyEngine hardening', () {
    test('saveTranscript and eraseAudio update targeted columns without clobbering concurrent edits, and forget checkpoints', () async {
      final dir = Directory.systemTemp.createTempSync('store-atomic');
      addTearDown(() => dir.deleteSync(recursive: true));
      final audioDir = p.join(dir.path, 'audio');
      final wordsDir = p.join(dir.path, 'words');
      Directory(audioDir).createSync();
      Directory(wordsDir).createSync();
      AndroidWords.useAudioFolder(audioDir);

      final store = SqliteBlessingStore.open(p.join(dir.path, 'blessings.sqlite'), audioDir: audioDir);
      addTearDown(store.close);

      final b = draftBlessing(DateTime.utc(2026, 11, 18, 12), place: saltLakeTemple)..audio = 'rec1.m4a';
      File(p.join(audioDir, 'rec1.m4a')).writeAsBytesSync([1, 2, 3]);
      File(p.join(wordsDir, 'rec1.m4a.json')).writeAsStringSync('{"pieces":[]}');
      await store.create(b);

      // User edits title, giver, and finishes review on another reference while transcription finishes.
      final edited = (await store.get(b.id))!
        ..title = 'Comfort and peace'
        ..from = 'Dad'
        ..draft = false;
      await store.update(edited);

      await store.saveTranscript(b.id, status: WordsStatus.written, words: 'I bless you with peace.');
      final afterWords = (await store.get(b.id))!;
      expect(afterWords.title, 'Comfort and peace');
      expect(afterWords.from, 'Dad');
      expect(afterWords.draft, isFalse);
      expect(afterWords.wordsStatus, WordsStatus.written);
      expect(afterWords.firstText, 'I bless you with peace.');
      expect(afterWords.rawText, 'I bless you with peace.');

      // If rawText was already typed by hand, saveTranscript preserves rawText and still records firstText.
      final b2 = Blessing(
        id: 'rec2',
        title: Strings.untitled,
        from: '',
        utc: DateTime.utc(2026, 11, 18, 13),
        utcOffset: Duration.zero,
        place: saltLakeTemple,
        rawText: 'Typed by hand.',
        audio: 'rec2.m4a',
      );
      await store.create(b2);
      await store.saveTranscript('rec2', status: WordsStatus.written, words: 'Spoken words.');
      final afterTyped = (await store.get('rec2'))!;
      expect(afterTyped.rawText, 'Typed by hand.');
      expect(afterTyped.firstText, 'Spoken words.');

      // eraseAudio deletes both the audio file and any AndroidWords piece checkpoint without touching title.
      afterWords.title = 'Unsaved local mutation';
      await store.eraseAudio(b);
      expect(b.audio, '');
      expect(File(p.join(audioDir, 'rec1.m4a')).existsSync(), isFalse);
      expect(File(p.join(wordsDir, 'rec1.m4a.json')).existsSync(), isFalse);
      expect((await store.get(b.id))!.title, 'Comfort and peace');
    });

    test('AppLock.init fails closed when LockApi.method throws while lock is chosen', () async {
      final dir = Directory.systemTemp.createTempSync('lock-fail-closed');
      addTearDown(() => dir.deleteSync(recursive: true));
      final settings = await Settings.open(p.join(dir.path, 'settings.json'));
      final api = _ThrowingLockApi();
      final lock = AppLock(api: api);
      await lock.init(settings);
      expect(lock.locked, isTrue);
      expect(api.covered, isTrue);

      // If the user explicitly turned the lock off, init stays unlocked.
      await settings.setLockOn(false);
      final lockOff = AppLock(api: _ThrowingLockApi());
      await lockOff.init(settings);
      expect(lockOff.locked, isFalse);
    });

    test('Settings tolerates malformed JSON field types and serializes concurrent writes', () async {
      final dir = Directory.systemTemp.createTempSync('settings-safe');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = p.join(dir.path, 'settings.json');
      File(file).writeAsStringSync('{"lock":"yes","recordingLanguage":42,"place":{"lat":"x","lon":null},"sky":99}');
      final s = await Settings.open(file);
      expect(s.lockOn, isTrue);
      expect(s.language, isNull);
      expect(s.place, isNull);
      expect(s.sky, '');

      await Future.wait([
        s.setLanguage('es'),
        s.setSky('emma'),
        s.setKeptBy('Dad'),
      ]);
      final reopened = await Settings.open(file);
      expect(reopened.language, 'es');
      expect(reopened.sky, 'emma');
      expect(reopened.keptBy, 'Dad');
      expect(File('$file.tmp').existsSync(), isFalse);
    });

    test('SkyEngine.settled becomes true at rest and false while transitioning or speaking', () {
      final e = SkyEngine(const [])
        ..setView(SkyView.home)
        ..snap();
      expect(e.settled, isTrue);

      e.setView(SkyView.record);
      expect(e.settled, isFalse);
      for (var i = 0; i < 400 && !e.settled; i++) {
        e.step(1 / 60);
      }
      // Record view keeps the golden orb breathing, so it stays active until leaving record view.
      expect(e.settled, isFalse);

      e.setView(SkyView.home);
      for (var i = 0; i < 400 && !e.settled; i++) {
        e.step(1 / 60);
      }
      expect(e.settled, isTrue);
    });
  });
}
