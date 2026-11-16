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
  const Permissions({required this.microphone, required this.speech});

  static const granted = Permissions(microphone: Permission.granted, speech: Permission.granted);

  final Permission microphone, speech;

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
}

/// What came back from turning a file into words.
class Transcript {
  const Transcript({required this.text, this.engine = '', this.locale = '', this.unavailable = false});

  /// No engine on this phone can write the language without a server; the audio is kept.
  const Transcript.unavailable() : this(text: '', unavailable: true);

  final String text;

  /// "analyzer" (Apple's new engine) or "recognizer" (the older one, on the device).
  final String engine;

  /// The locale that was used, e.g. "es-US".
  final String locale;
  final bool unavailable;
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
  String? _path;

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
}

/// Writes nothing.
class SilentTranscriber implements Transcriber {
  const SilentTranscriber();

  @override
  Future<Transcript> transcribe(String path, SpeechLanguage language) async => const Transcript(text: '');
}
