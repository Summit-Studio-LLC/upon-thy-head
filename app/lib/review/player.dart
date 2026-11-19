import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays a recording on the review page: play, pause, back ten seconds, and where it is.
abstract class Player extends ChangeNotifier {
  /// Seconds into the recording, and its length (0 until loaded).
  double get position;
  double get duration;
  bool get playing;

  /// A recording is loaded.
  bool get loaded => duration > 0;

  Future<void> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(double seconds);

  /// Stop and let go of the file.
  Future<void> unload();

  Future<void> toggle() => playing ? pause() : play();

  /// Back ten seconds (to the start, if nearer).
  Future<void> back() => seek((position - 10).clamp(0, duration).toDouble());
}

/// The recording through iOS (ios/Runner/Playback.swift). While playing, it asks where it is
/// ten times a second.
class NativePlayer extends Player {
  NativePlayer() {
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return;
      if (call.method == 'stopped') {
        _position = ((call.arguments as Map)['position'] as num).toDouble();
        _setPlaying(false);
      }
    });
  }

  static const _channel = MethodChannel('upon_thy_head/player');

  double _position = 0, _duration = 0;
  bool _playing = false, _disposed = false;
  Timer? _poll;

  @override
  double get position => _position;
  @override
  double get duration => _duration;
  @override
  bool get playing => _playing;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _setPlaying(bool on) {
    if (_disposed) return;
    _playing = on;
    _poll?.cancel();
    if (on) _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _ask());
    _changed();
  }

  Future<void> _ask() async {
    if (_disposed) return;
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('position');
      if (_disposed || m == null) return;
      _position = (m['position'] as num).toDouble();
      _duration = (m['duration'] as num).toDouble();
      final playing = m['playing'] == true;
      if (playing != _playing) {
        _setPlaying(playing);
      } else {
        _changed();
      }
    } catch (e) {
      debugPrint('player: $e');
    }
  }

  @override
  Future<void> load(String path) async {
    _setPlaying(false);
    _position = 0;
    try {
      _duration = (await _channel.invokeMethod<num>('load', {'path': path}))?.toDouble() ?? 0;
    } on PlatformException catch (e) {
      debugPrint('player: ${e.code} ${e.message}');
      _duration = 0;
    }
    _changed();
  }

  @override
  Future<void> play() async {
    if (!loaded) return;
    final ok = await _channel.invokeMethod<bool>('play') ?? false;
    _setPlaying(ok);
  }

  @override
  Future<void> pause() async {
    await _channel.invokeMethod<void>('pause');
    _setPlaying(false);
    await _ask();
  }

  @override
  Future<void> seek(double seconds) async {
    await _channel.invokeMethod<void>('seek', {'seconds': seconds});
    _position = seconds;
    _changed();
  }

  @override
  Future<void> unload() async {
    _setPlaying(false);
    _position = _duration = 0;
    await _channel.invokeMethod<void>('unload');
    _changed();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _disposed = true;
    unawaited(_channel.invokeMethod<void>('unload').catchError((_) {}));
    super.dispose();
  }
}

/// Plays nothing, but keeps time as if it did: for widget tests and where there is no native side.
class SilentPlayer extends Player {
  SilentPlayer({this.length = 30});

  /// The pretend recording's length, in seconds.
  final double length;

  double _from = 0, _duration = 0;
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  @override
  double get position => (_from + _clock.elapsedMicroseconds / 1e6).clamp(0, _duration).toDouble();
  @override
  double get duration => _duration;
  @override
  bool get playing => _clock.isRunning;

  @override
  Future<void> load(String path) async {
    await unload();
    _duration = length;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    if (!loaded) return;
    _clock.start();
    _tick ??= Timer.periodic(const Duration(milliseconds: 100), (_) => notifyListeners());
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _from = position;
    _clock
      ..stop()
      ..reset();
    _tick?.cancel();
    _tick = null;
    notifyListeners();
  }

  @override
  Future<void> seek(double seconds) async {
    _from = seconds;
    _clock.reset();
    notifyListeners();
  }

  @override
  Future<void> unload() async {
    await pause();
    _from = _duration = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

/// "1:04"
String clockTime(double seconds) {
  final s = seconds.isFinite ? seconds.floor() : 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
