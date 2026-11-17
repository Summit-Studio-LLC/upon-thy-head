// Android: the words engine on its own, on known recordings (docs/android-plan.md 3.5, tasks 8-10).
// Used by tool/android_words.sh to measure Whisper inside the app against the Mac's numbers; the
// recordings and the model are put into the app's own folders by the script first.
//
//   --dart-define=WORDS_FILES=libri_en.m4a:en,mls_es.m4a:es   (in <files>/words_in/)
//
// Prints one line per file: WORDS <name> <ms> <json text, cut short>; the whole text goes to
// <files>/words_in/out/<name>.txt.

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:upon_thy_head/record/android_words.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/record/words_model.dart';

const files = String.fromEnvironment('WORDS_FILES');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('android words: known recordings become words', (tester) async {
    final support = (await getApplicationSupportDirectory()).path;
    final inDir = p.join(p.dirname(support), 'files', 'words_in');
    // the script puts the model and the recordings in place once the app is installed, then says go
    for (var i = 0; i < 600 && !File(p.join(inDir, 'go')).existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print('MODEL ${(await WordsModel.instance.refresh()).state}');
    final w = AndroidWords(folder: () async => p.join(support, 'words_test'));
    for (final job in files.split(',').where((s) => s.isNotEmpty)) {
      final [name, lang] = job.split(':');
      final path = p.join(Directory(inDir).existsSync() ? inDir : support, name);
      final sw = Stopwatch()..start();
      final t = await w.transcribe(path, SpeechLanguage.fromCode(lang));
      // the whole text to a file (logcat cuts long lines), the time to the log
      final out = Directory(p.join(inDir, 'out'))..createSync(recursive: true);
      File(p.join(out.path, '$name.txt')).writeAsStringSync(t.text);
      print('WORDS $name ${sw.elapsedMilliseconds} later=${t.later} unavailable=${t.unavailable} ${jsonEncode(t.text.length > 300 ? '${t.text.substring(0, 300)}…' : t.text)}');
    }
    File(p.join(inDir, 'done')).writeAsStringSync('');
    print('WORDS done');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
