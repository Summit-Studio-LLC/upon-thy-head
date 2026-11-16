// The real transcription path on the device, with real spoken audio:
//
//   tool/sim_permissions.sh grant
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/speech_engine_test.dart \
//     --dart-define=SPEECH_AUDIO=$PWD/integration_test/audio
//
// SPEECH_AUDIO is a folder the app can read: on a simulator the Mac's own path works. Prints what
// each engine reports, then the words that came back beside the words spoken, the word errors,
// and how long transcription took against the length of the audio.

// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/record/transcriber.dart';

import 'audio/spoken.dart';

const audioDir = String.fromEnvironment('SPEECH_AUDIO');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speech: spoken English and Spanish become words on this device', (tester) async {
    expect(audioDir, isNotEmpty, reason: 'pass --dart-define=SPEECH_AUDIO=<folder with en.m4a and es.m4a>');
    final s = NativeSpeech.instance..debugTrace = const bool.fromEnvironment('SPEECH_TRACE');
    print('ENGINES ${await s.describe()}');
    print('PERMISSIONS mic ${(await s.permissions()).microphone} speech ${(await s.permissions()).speech}');
    for (final (lang, file, said, seconds) in [
      (SpeechLanguage.english, 'en.m4a', spokenEnglish, 37.87),
      (SpeechLanguage.spanish, 'es.m4a', spokenSpanish, 24.10),
    ]) {
      print('CHOSEN ${lang.code} ${await s.engine(lang)}');
      final watch = Stopwatch()..start();
      final t = await s.transcribe('$audioDir/$file', lang);
      watch.stop();
      final e = wordErrors(said, t.text);
      print('RESULT ${lang.code} engine=${t.engine} locale=${t.locale} unavailable=${t.unavailable} '
          'took=${watch.elapsedMilliseconds}ms audio=${seconds}s '
          'errors=${e.errors}/${e.spoken} (sub ${e.subs}, del ${e.dels}, ins ${e.ins})');
      print('HEARD ${lang.code} <<<${t.text}>>>');
      // Spanish has no on-device engine on the simulator (it reports "server only"): that is an
      // honest answer, and the app must say so rather than send audio away
      if (t.unavailable) {
        print('UNAVAILABLE ${lang.code}: no on-device engine on this device');
        expect(lang, SpeechLanguage.spanish, reason: 'English must work on the device');
        continue;
      }
      expect(e.errors / e.spoken, lessThan(.25), reason: 'too many word errors');
    }
  });
}
