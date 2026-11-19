import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/blessing.dart';
import 'keep_awake.dart';
import 'recovery.dart';
import 'transcriber.dart';

enum RecordState { ready, live }

/// Where the words of a finished recording are.
enum WordsState {
  /// Not finished yet.
  none,

  /// Being written from the audio, on the phone.
  writing,

  /// Written (possibly empty, if nothing was said).
  done,

  /// No engine on this phone can write this language yet; the audio is kept.
  unavailable,

  /// The engine failed; the audio is kept.
  failed,

  /// Android: the speech model is not on the phone yet; the words are written from the recording,
  /// which is kept until they are (`WordsStatus.later`), as soon as it is downloaded.
  later,
}

/// One visit to the recording screen: the draft blessing, whether it is
/// listening, and for how long.
class RecordSession extends ChangeNotifier {
  RecordSession({
    Recorder? recorder,
    this.transcriber = const SilentTranscriber(),
    this.audioDir = '',
    this.language = SpeechLanguage.english,
    this.practice = false,
  }) : recorder = recorder ?? SilentRecorder();

  /// Seconds after Begin in which the ring discards instead of finishing.
  static const double window = 10;

  /// Tests only: a wait before the words are written, so a test can close the app in between.
  static Duration debugWordsDelay = Duration.zero;
  static Future<void> debugHoldWords() async {
    if (debugWordsDelay > Duration.zero) await Future<void>.delayed(debugWordsDelay);
  }

  /// How long the ring must be held, to discard or to finish.
  static const Duration hold = Duration(milliseconds: 900);

  final Recorder recorder;
  final Transcriber transcriber;

  /// The first run's rehearsal: the ring is Amen from the start, no recording note is written (so
  /// nothing is ever rebuilt from it), and the audio goes to a folder of its own that is emptied
  /// as soon as the words are shown (onboarding/first_run.dart).
  final bool practice;

  /// The folder recordings are written to (see data/audio.dart).
  String audioDir;

  RecordState get state => _state;
  RecordState _state = RecordState.ready;
  bool get live => _state == RecordState.live;

  /// The discard confirmation sheet is up.
  bool get sheet => _sheet;
  bool _sheet = false;

  /// The microphone could not start when Begin was pressed (a call, or another app holding it).
  bool get startFailed => _startFailed;
  bool _startFailed = false;

  /// The language the blessing is spoken in; fixed once Begin is pressed.
  SpeechLanguage language;

  /// Microphone and speech permission, once known (null while being looked up).
  Permissions? get permissions => _permissions;
  Permissions? _permissions;

  /// Begin is possible: everything needed has been allowed.
  bool get canBegin => _permissions?.allGranted ?? false;

  /// The system has the microphone (a phone call); the recording so far is safe.
  bool get paused => _paused;
  bool _paused = false;
  StreamSubscription<bool>? _pausedSub;

  /// Current voice level from the microphone, 0 (silence or paused) to 1 (full voice).
  /// Kept on its own notifier so the sky can follow it without rebuilding the screens.
  final ValueNotifier<double> level = ValueNotifier(0);
  StreamSubscription<double>? _levelSub;

  final Stopwatch _clock = Stopwatch();

  /// Seconds since Begin, not counting time paused.
  double get elapsed => _clock.elapsedMicroseconds / 1e6;

  /// Past the first ten seconds: the ring now finishes.
  bool get amen => live && (practice || elapsed >= window);

  /// The new blessing this recording becomes.
  Blessing? draft;

  /// The finished recording's file, once stopped.
  String? audioPath;

  /// The words heard, once written.
  String words = '';
  WordsState get wordsState => _wordsState;
  WordsState _wordsState = WordsState.none;
  Transcript? transcript;

  String get _path => p.join(audioDir, '${draft?.id ?? 'practice'}.m4a');

  /// Look up the permissions, and ask for any not yet asked. Called as the ready screen opens.
  Future<void> checkPermissions({bool ask = true}) async {
    _startFailed = false;
    var now = await recorder.permissions();
    if (_disposed) return;
    if (ask && now.anyUndetermined && !now.anyDenied) {
      now = await recorder.requestPermissions();
      if (_disposed) return;
    }
    _permissions = now;
    notifyListeners();
  }

  /// Android: the microphone was refused once and the phone will still ask: ask it again now.
  Future<void> askAgain() async {
    _startFailed = false;
    final now = await recorder.requestPermissions();
    if (_disposed) return;
    _permissions = now;
    notifyListeners();
  }

  void setLanguage(SpeechLanguage l) {
    if (live || _disposed || l == language) return;
    language = l;
    notifyListeners();
  }

  Future<void> _rollbackStart({required bool cancelled}) async {
    _state = RecordState.ready;
    _sheet = false;
    _paused = false;
    _clock
      ..stop()
      ..reset();
    if (!_disposed) level.value = 0;
    KeepAwake.set(false);
    await forget();
    _startFailed = !cancelled;
    if (!_disposed) notifyListeners();
  }

  Future<void> begin() async {
    if (live || _disposed || !canBegin || (!practice && draft == null)) return;
    _startFailed = false;
    _state = RecordState.live;
    _sheet = false;
    _paused = false;
    level.value = 0;
    _clock
      ..reset()
      ..start();
    KeepAwake.set(true);
    notifyListeners();
    _pausedSub ??= recorder.paused.listen(_onPaused);
    _levelSub ??= recorder.level.listen(_onLevel);
    if (practice) {
      try {
        await recorder.start(_path);
      } catch (e) {
        debugPrint('record: could not start the practice: $e');
        await _rollbackStart(cancelled: !live || _disposed);
        return;
      }
      if (!live || _disposed) {
        await recorder.cancel();
        return;
      }
      return;
    }
    // from this moment the blessing exists: if the app is closed before Amen, the next launch
    // rebuilds it from this note and the audio beside it (see recovery.dart)
    final d = draft!;
    _noted = d.id;
    try {
      await RecordingNote.of(d).write(audioDir);
    } catch (e) {
      debugPrint('record: could not write the recording note: $e');
    }
    // discarded while the note was being written
    if (!live || _disposed || _noted != d.id) return;
    try {
      await recorder.start(_path);
    } catch (e) {
      debugPrint('record: could not start: $e');
      await _rollbackStart(cancelled: !live || _disposed || _noted != d.id);
      return;
    }
    if (!live || _disposed || _noted != d.id) {
      await recorder.cancel();
      return;
    }
  }

  void _onPaused(bool on) {
    if (!live || _disposed || on == _paused) return;
    _paused = on;
    if (on) level.value = 0;
    on ? _clock.stop() : _clock.start();
    notifyListeners();
  }

  void _onLevel(double db) {
    if (!live || _paused || _disposed) return;
    level.value = voiceLevelFromDb(db);
  }

  /// The id whose recording note is on disk, until the blessing is in the store or thrown away.
  String? _noted;

  /// The blessing is in the store: the note that would have rebuilt it is no longer needed.
  Future<void> forget() async {
    final id = _noted;
    _noted = null;
    if (id != null) await RecordingNote.remove(audioDir, id);
  }

  /// Throw the recording away. Back to ready, with nothing kept: the audio and the note are deleted.
  void discard() {
    if (_disposed) return;
    if (live) recorder.cancel();
    forget();
    _startFailed = false;
    _state = RecordState.ready;
    _sheet = false;
    _paused = false;
    level.value = 0;
    _clock
      ..stop()
      ..reset();
    KeepAwake.set(false);
    notifyListeners();
  }

  /// Amen: stop listening. The finished file's path, or null if nothing could be kept.
  Future<String?> finish() async {
    if (!live || _disposed) return null;
    _state = RecordState.ready;
    _sheet = false;
    _paused = false;
    level.value = 0;
    _clock.stop();
    KeepAwake.set(false);
    _wordsState = WordsState.writing;
    notifyListeners();
    try {
      audioPath = await recorder.stop();
    } catch (e) {
      debugPrint('record: could not stop: $e');
      audioPath = null;
    }
    if (_disposed) return null;
    return audioPath;
  }

  /// Write the words from the finished file. Never throws: a failure keeps the audio.
  Future<void> transcribe() async {
    final path = audioPath;
    if (path == null) {
      _settle(WordsState.failed);
      return;
    }
    try {
      await debugHoldWords();
      if (_disposed) return;
      final t = await transcriber.transcribe(path, language);
      if (_disposed) return;
      transcript = t;
      words = t.text;
      _settle(t.later ? WordsState.later : t.unavailable ? WordsState.unavailable : WordsState.done);
    } catch (e) {
      debugPrint('speech: $e');
      _settle(WordsState.failed);
    }
  }

  void _settle(WordsState s) {
    _wordsState = s;
    if (!_disposed) notifyListeners();
  }

  void showSheet(bool on) {
    if (_sheet == on || _disposed) return;
    _sheet = on;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    if (live) {
      recorder.cancel();
      forget();
      KeepAwake.set(false);
    }
    _pausedSub?.cancel();
    _levelSub?.cancel();
    _disposed = true;
    level.dispose();
    super.dispose();
  }
}
