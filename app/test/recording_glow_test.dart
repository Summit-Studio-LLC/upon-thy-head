// The golden recording glow (`SkyEngine.orbUniforms`, `RecordSession.level`, `voiceLevelFromDb`):
// a calm breath in silence, lifting gently in reach and brightness when the microphone hears a
// voice, stilling when paused by a call, and keeping its radius still under Reduce Motion.
//
//   flutter test test/recording_glow_test.dart

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/sky/sky_engine.dart';
import 'package:upon_thy_head/theme.dart';

class _TestPaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  test('voiceLevelFromDb gates room noise at -50 dBFS and rises smoothly across speech levels', () {
    expect(voiceLevelFromDb(double.nan), 0);
    expect(voiceLevelFromDb(double.negativeInfinity), 0);
    expect(voiceLevelFromDb(-160), 0);
    expect(voiceLevelFromDb(-55), 0);
    expect(voiceLevelFromDb(-50), 0);

    final quiet = voiceLevelFromDb(-38);
    final normal = voiceLevelFromDb(-24);
    final clear = voiceLevelFromDb(-16);
    expect(quiet, greaterThan(0.10));
    expect(normal, greaterThan(quiet));
    expect(clear, greaterThan(normal));
    expect(voiceLevelFromDb(-14), closeTo(1.0, 1e-6));
    expect(voiceLevelFromDb(-3), 1.0);
  });

  test('RecordSession.level follows the microphone only while live and unpaused, without rebuilding listeners', () async {
    final dir = Directory.systemTemp.createTempSync('rec-level');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rec = SilentRecorder();
    final s = RecordSession(recorder: rec, audioDir: dir.path, practice: true);
    addTearDown(s.dispose);
    await s.checkPermissions(ask: false);

    // before Begin: microphone levels are ignored
    rec.emitDb(-18);
    await Future<void>.delayed(Duration.zero);
    expect(s.level.value, 0);

    await s.begin();
    var sessionNotifies = 0;
    s.addListener(() => sessionNotifies++);

    rec.emitDb(-20);
    await Future<void>.delayed(Duration.zero);
    expect(s.level.value, greaterThan(0.6));
    expect(sessionNotifies, 0, reason: 'voice level updates must not rebuild the screen tree');

    // paused by a call: level drops at once and ignores further samples until resumed
    rec.emitPaused(true);
    await Future<void>.delayed(Duration.zero);
    expect(s.paused, isTrue);
    expect(s.level.value, 0);
    rec.emitDb(-15);
    await Future<void>.delayed(Duration.zero);
    expect(s.level.value, 0);

    rec.emitPaused(false);
    await Future<void>.delayed(Duration.zero);
    rec.emitDb(-18);
    await Future<void>.delayed(Duration.zero);
    expect(s.level.value, greaterThan(0.75));

    // Discard clears the level
    s.discard();
    expect(s.level.value, 0);
  });

  test('SkyEngine smooths voice with fast attack and slow release, lifts the orb, and honours Reduce Motion and pause', () {
    final e = SkyEngine(const [])
      ..setView(SkyView.record)
      ..snap();

    final silent = e.orbUniforms();
    expect(silent.radius, closeTo(0.15, 1e-6));
    expect(silent.strength, closeTo(0.50, 1e-6));

    // speaking for 0.25 s swells the envelope quickly
    e.voice = 0.85;
    for (var i = 0; i < 15; i++) {
      e.step(1 / 60);
    }
    expect(e.voiceShown, greaterThan(0.75));
    final speaking = e.orbUniforms();
    expect(speaking.radius, greaterThan(silent.radius + 0.06));
    expect(speaking.strength, greaterThan(silent.strength + 0.35));

    // silence for 0.15 s: slow release lingers warmly rather than snapping shut
    final peak = e.voiceShown;
    e.voice = 0;
    for (var i = 0; i < 9; i++) {
      e.step(1 / 60);
    }
    expect(e.voiceShown, lessThan(peak));
    expect(e.voiceShown, greaterThan(0.35), reason: 'lingers gently between words');

    // Reduce Motion: radius stays completely still while brightness still answers the voice
    e.reduceMotion = true;
    e.voice = 0;
    e.voiceShown = 0;
    final stillSilent = e.orbUniforms();
    e.voiceShown = 0.9;
    final stillSpeaking = e.orbUniforms();
    expect(stillSpeaking.radius, closeTo(stillSilent.radius, 1e-9), reason: 'no spatial motion under Reduce Motion');
    expect(stillSpeaking.strength, greaterThan(stillSilent.strength + 0.35), reason: 'brightness still shows recording');

    // paused by a call: the glow dims and stills
    e.reduceMotion = false;
    e.recordingPaused = true;
    for (var i = 0; i < 60; i++) {
      e.step(1 / 60);
    }
    final paused = e.orbUniforms();
    expect(e.voiceShown, lessThan(0.05));
    expect(paused.strength, lessThan(silent.strength * 0.6));
  });

  testWidgets('HomeScreen connects the live microphone level and pause state to the sky orb', (t) async {
    HomeScreen.debugSkipFirstRun = true;
    addTearDown(() => HomeScreen.debugSkipFirstRun = false);
    final dir = Directory.systemTemp.createTempSync('glow-home');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prevPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(dir.path);
    addTearDown(() => PathProviderPlatform.instance = prevPaths);

    final store = SqliteBlessingStore.open('${dir.path}/blessings.sqlite');
    addTearDown(store.close);
    final rec = SilentRecorder();

    t.view.physicalSize = const Size(402, 874) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: HomeScreen(
        palette: Palette.lamplight,
        store: store,
        recorder: rec,
        lock: AppLock(api: NoLockApi(), startUnlocked: true),
      ),
    ));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    final state = t.state<HomeScreenState>(find.byType(HomeScreen));
    await t.tap(find.byKey(const Key('new')));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    await t.tap(find.byKey(const Key('begin')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final silentStrength = state.debugEngine.orbUniforms().strength;

    rec.emitDb(-18);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 30));
    }
    expect(state.debugEngine.voiceShown, greaterThan(0.65));
    expect(state.debugEngine.orbUniforms().strength, greaterThan(silentStrength + 0.25));

    rec.emitPaused(true);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 40));
    }
    expect(state.debugEngine.recordingPaused, isTrue);
    expect(state.debugEngine.voice, 0);
  });
}
