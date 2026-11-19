import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../not_yet.dart';
import 'android_words.dart';
import 'recovery.dart';
import 'transcriber.dart';

/// The microphone and the words, on iOS (ios/Runner/SpeechChannel.swift, OnDeviceSpeech.swift) and
/// Android (android/app/src/main/kotlin/.../SpeechChannel.kt), with the same methods and events.
///
/// Speech is turned into text on the phone only: the native side uses Apple's new engine where
/// the phone has it, otherwise the older recogniser with on-device recognition required, and
/// otherwise answers "unavailable". It never falls back to a server.
class NativeSpeech implements Recorder, Transcriber, AudioJoiner {
  NativeSpeech._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'paused') _paused.add(call.arguments == true);
      if (call.method == 'level' && call.arguments is num) _level.add((call.arguments as num).toDouble());
    });
  }

  static final NativeSpeech instance = NativeSpeech._();

  static const _channel = MethodChannel('upon_thy_head/speech');
  final StreamController<bool> _paused = StreamController.broadcast();
  final StreamController<double> _level = StreamController.broadcast();

  /// Whether this platform answers at all (iOS does; tests on the host and macOS do not).
  static Future<bool> present() async {
    try {
      await _channel.invokeMethod<Object?>('permissions');
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  static Permission _p(Object? s) => switch (s) {
        'granted' => Permission.granted,
        'denied' => Permission.denied,
        _ => Permission.undetermined,
      };

  static Permissions _perms(Map<Object?, Object?>? m) =>
      Permissions(microphone: _p(m?['microphone']), speech: _p(m?['speech']), microphoneAskAgain: m?['microphoneAskAgain'] == true);

  @override
  Future<Permissions> permissions() async => _perms(await _channel.invokeMethod<Map<Object?, Object?>>('permissions'));

  @override
  Future<Permissions> requestPermissions() async =>
      _perms(await _channel.invokeMethod<Map<Object?, Object?>>('requestPermissions'));

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<void> start(String path) => _channel.invokeMethod<void>('start', {'path': path});

  @override
  Future<String> stop() async => (await _channel.invokeMethod<String>('stop'))!;

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Stream<bool> get paused => _paused.stream;

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<String?> join(String audioDir, String id) async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('recover', {'path': '$audioDir/$id.m4a'});
    if (m == null) return null;
    debugPrint('recovery: joined $id, ${(m['seconds'] as num).toStringAsFixed(1)} s');
    return (m['path'] as String).split('/').last;
  }

  /// The length of the audio in the file at [path], in seconds.
  Future<double> seconds(String path) async => ((await _channel.invokeMethod<num>('seconds', {'path': path})) ?? 0).toDouble();

  /// The engine and locale that would write [language] on this phone, or null when none can.
  /// Also starts the download of the new engine's language model where it needs one.
  Future<({String engine, String locale})?> engine(SpeechLanguage language) async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('engine', {'language': language.code});
    return m == null ? null : (engine: m['engine'] as String, locale: m['locale'] as String);
  }

  /// What the phone reports about each engine.
  Future<Map<Object?, Object?>?> describe() => _channel.invokeMethod<Map<Object?, Object?>>('describe');

  @override
  Future<Transcript> transcribe(String path, SpeechLanguage language) async {
    // Android: Whisper on the phone, a piece at a time (android_words.dart, docs/android-plan.md 3.5)
    if (Phone.android) return AndroidWords.instance.transcribe(path, language);
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('transcribe', {'path': path, 'language': language.code, 'trace': debugTrace});
      if (debugTrace) {
        for (final l in (m!['trace'] as List? ?? [])) {
          debugPrint('TRACE $l');
        }
      }
      debugPrint('speech: ${m!['engine']} ${m['locale']} in ${m['ms']} ms');
      return Transcript(text: m['text'] as String, engine: m['engine'] as String, locale: m['locale'] as String);
    } on PlatformException catch (e) {
      debugPrint('speech: ${e.code} ${e.message}');
      if (e.code == 'unavailable') return const Transcript.unavailable();
      rethrow;
    }
  }

  // ---- tests only ----

  /// Print each step the engine reports.
  bool debugTrace = false;

  /// Behave as if the system took (or gave back) the microphone.
  Future<void> debugInterrupt(bool began) => _channel.invokeMethod<void>('debugInterrupt', {'began': began});

  /// Send a pretend microphone loudness in dBFS through the native channel.
  Future<void> debugLevel(double db) => _channel.invokeMethod<void>('debugLevel', {'db': db});

  /// At stop, replace what the microphone heard with a copy of the file at [path] (null: stop doing so).
  Future<void> debugFeed(String? path) => _channel.invokeMethod<void>('debugFeed', {'path': path});

  /// Android: whether the recorder and its foreground service are running now.
  Future<({bool recording, bool service})> debugState() async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('debugState');
    return (recording: m?['recording'] == true, service: m?['service'] == true);
  }
}
