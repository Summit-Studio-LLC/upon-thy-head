import 'dart:async';
import 'dart:io';

/// The languages a blessing can be spoken in, as the app offers them.
enum SpeechLanguage {
  english('en'),
  spanish('es');

  const SpeechLanguage(this.code);

  /// "en" or "es": what the native side and the store use.
  final String code;

  static SpeechLanguage fromCode(String? code) => code == 'es' ? spanish : english;

  /// The phone's language: Spanish if the phone is in Spanish, otherwise English.
  static SpeechLanguage forPhone(String languageCode) => languageCode == 'es' ? spanish : english;
}

/// Whether the person has let the app use something.
enum Permission { granted, denied, undetermined }

class Permissions {
  const Permissions({required this.microphone, required this.speech, this.microphoneAskAgain = false});

  static const granted = Permissions(microphone: Permission.granted, speech: Permission.granted);

  final Permission microphone, speech;

  /// Android: the microphone was refused, and the phone will still put its question once more
  /// (rather than only its Settings page).
  final bool microphoneAskAgain;

  bool get allGranted => microphone == Permission.granted && speech == Permission.granted;
  bool get anyDenied => microphone == Permission.denied || speech == Permission.denied;
  bool get anyUndetermined => microphone == Permission.undetermined || speech == Permission.undetermined;
}

/// Records the microphone, from Begin to Amen, into a file on the phone.
abstract class Recorder {
  Future<Permissions> permissions();

  /// Asks for whatever has not been asked yet. Only ever called on the ready screen.
  Future<Permissions> requestPermissions();

  Future<void> openSettings();

  /// Start listening into the file at [path].
  Future<void> start(String path);

  /// Stop listening; the finished file's path.
  Future<String> stop();

  /// Stop listening and delete everything recorded.
  Future<void> cancel();

  /// True while the system has taken the microphone (a phone call); the recording so far is kept
  /// and listening starts again when it is given back.
  Stream<bool> get paused;

  /// Microphone loudness in dBFS while listening, a few times a second; silent where unused.
  Stream<double> get level => const Stream.empty();
}

/// Maps microphone loudness in dBFS (typically -160..0) to 0..1 for the recording glow.
/// Quiet room tone at or below -50 dBFS rests at 0; spoken voice (-36 to -14 dBFS) lifts smoothly.
double voiceLevelFromDb(double db) {
  if (!db.isFinite || db <= -50) return 0;
  final u = ((db + 50) / 36).clamp(0.0, 1.0);
  return u * (.35 + .65 * u);
}

/// What came back from turning a file into words.
class Transcript {
  const Transcript({required this.text, this.engine = '', this.locale = '', this.unavailable = false, this.later = false});

  /// No engine on this phone can write the language without a server; the audio is kept.
  const Transcript.unavailable() : this(text: '', unavailable: true);

  /// Android: the words are written on this phone only once its speech model is downloaded (with
  /// the person's consent, lib/record/words_model.dart); until then the recording is kept and its
  /// words are written from it when the model arrives.
  const Transcript.later() : this(text: '', later: true);

  final String text;

  /// "analyzer" (Apple's new engine) or "recognizer" (the older one, on the device); "whisper" on Android.
  final String engine;

  /// The locale that was used, e.g. "es-US".
  final String locale;
  final bool unavailable;
  final bool later;
}

/// Turns a recorded file into words, on the phone only.
abstract class Transcriber {
  Future<Transcript> transcribe(String path, SpeechLanguage language);
}

/// Hears nothing: for widget tests and where there is no native side. Its "recording" is an
/// empty file, so storage and deletion are still exercised.
class SilentRecorder implements Recorder {
  SilentRecorder({this.granted = Permissions.granted});

  Permissions granted;
  final StreamController<bool> _paused = StreamController.broadcast();
  final StreamController<double> _level = StreamController.broadcast();
  String? _path;

  /// Tests: pretend the microphone heard [db] dBFS, or the system paused/resumed it.
  void emitDb(double db) => _level.add(db);
  void emitPaused(bool on) => _paused.add(on);

  @override
  Future<Permissions> permissions() async => granted;

  @override
  Future<Permissions> requestPermissions() async => granted;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> start(String path) async {
    _path = path;
    await File(path).parent.create(recursive: true);
  }

  @override
  Future<String> stop() async {
    final p = _path!;
    await File(p).writeAsBytes(const []);
    _path = null;
    return p;
  }

  @override
  Future<void> cancel() async {
    _path = null;
  }

  @override
  Stream<bool> get paused => _paused.stream;

  @override
  Stream<double> get level => _level.stream;
}

/// Writes nothing.
class SilentTranscriber implements Transcriber {
  const SilentTranscriber();

  @override
  Future<Transcript> transcribe(String path, SpeechLanguage language) async => const Transcript(text: '');
}
