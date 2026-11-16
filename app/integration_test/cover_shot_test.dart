// Renders the app switcher's cover: the locked sky with nothing drawn over it, at the phone's own
// pixels. tool/cover_shot.sh turns it into assets/sky/cover.jpg, which ios/Runner/Privacy.swift
// lays over the app whenever it leaves the foreground with the lock on.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/sky/sky_view.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('cover: the locked sky, bare', (tester) async {
    HomeScreen.debugBare = true;
    final lock = AppLock(api: NoLockApi(methodIs: LockMethod.faceId, answer: false));
    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: lock));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(lock.locked, isTrue);
    expect(tester.widget<SkyWidget>(sky).engine.blessings, isEmpty);
    // the simulator's own screenshot: Flutter's capture leaves the shader-drawn sky out
    debugPrint('SIMSHOT cover');
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
}
