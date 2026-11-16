// The microphone, for real: the app listens on a simulator (which hears the Mac's microphone)
// while the spoken sample blessing plays through the Mac's speakers.
//
//   tool/microphone_test.sh      (installs, grants, runs this, plays the file when asked)
//
// Prints `PLAY` once listening; the script then plays integration_test/audio/en.m4a out loud.
// Nothing replaces what the microphone heard. Reports the words beside the words spoken.

// ignore_for_file: avoid_print

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';

import 'audio/spoken.dart';
import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('microphone: a blessing played aloud becomes words', (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    RecordSession session() => tester.widget<RecordLayer>(find.byType(RecordLayer)).session;
    await NativeSpeech.instance.debugFeed(null);
    await tester.pumpWidget(UponThyHeadApp(store: await freshSeededStore(), stats: false, demo: false, lock: unlockedLock()));
    final sky = find.byKey(const Key('sky'));
    for (var i = 0; i < 600 && sky.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await wait(1500);
    await tester.tap(find.byKey(const Key('new')));
    await wait(3000);
    expect(session().canBegin, isTrue, reason: 'permissions');
    await tester.tap(find.byKey(const Key('begin')));
    await wait(1000);
    print('PLAY');
    await wait(41000); // the recording is 37.9 s
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold'))));
    await wait(1100);
    await g.up();
    final t0 = DateTime.now();
    while (session().wordsState == WordsState.writing || session().wordsState == WordsState.none) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final e = wordErrors(spokenEnglish, session().words);
    print('MIC state=${session().wordsState} engine=${session().transcript?.engine} '
        'took=${DateTime.now().difference(t0).inMilliseconds}ms errors=${e.errors}/${e.spoken} '
        '(sub ${e.subs}, del ${e.dels}, ins ${e.ins})');
    print('MICWORDS <<<${session().words}>>>');
    await tester.tap(find.byKey(const Key('save-later')));
    await wait(2000);
  });
}
