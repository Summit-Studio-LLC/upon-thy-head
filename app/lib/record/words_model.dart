import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The speech model Android downloads, with the person's consent, to write the words on the phone
/// (docs/android-plan.md 3.5): Whisper base, quantised (q5_1), for English and Spanish alike.
///
/// One set of constants. The address is the upstream public copy the measurements used
/// (whisper.cpp's own model files on Hugging Face); where the app's own copy will be hosted is a
/// launch decision. Tests may point elsewhere at build time, in debug builds only:
///   --dart-define=WORDS_MODEL_URL=http://10.0.2.2:4330/ggml-base-q5_1.bin
///   --dart-define=WORDS_MODEL_SHA256=(64 hex digits; a wrong one proves the refusal)
///   --dart-define=WORDS_MODEL_BYTES=(its size)
/// A release build ignores all three.
class WordsModelSpec {
  const WordsModelSpec({required this.name, required this.url, required this.bytes, required this.sha256});

  final String name, url, sha256;
  final int bytes;

  static const base = WordsModelSpec(
    name: 'ggml-base-q5_1.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin',
    bytes: 59707625,
    sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
  );

  static const _url = String.fromEnvironment('WORDS_MODEL_URL');
  static const _sha = String.fromEnvironment('WORDS_MODEL_SHA256');
  static const _bytes = int.fromEnvironment('WORDS_MODEL_BYTES');

  /// The model this build downloads.
  static WordsModelSpec get current => kReleaseMode
      ? base
      : WordsModelSpec(
          name: base.name,
          url: _url.isEmpty ? base.url : _url,
          bytes: _bytes > 0 ? _bytes : base.bytes,
          sha256: _sha.isEmpty ? base.sha256 : _sha,
        );

  /// The size as the screens say it, in Android's own units (Settings counts a megabyte as a million
  /// bytes): 59,707,625 bytes is "60 MB". (The plan's draft wording said 58 MB; whisper.cpp lists
  /// the file as 57 MiB. The screens take the number from here, so they always match the file.)
  int get megabytes => (bytes / 1000000).round();

  Map<String, Object> toMap() => {'name': name, 'url': url, 'bytes': bytes, 'sha256': sha256};
}

/// Where the model is.
enum ModelState {
  /// Not on the phone and not asked for.
  absent,

  /// Coming in now.
  downloading,

  /// Asked for, but the connection was lost: carries on by itself when it comes back.
  waiting,

  /// Arrived; its SHA-256 is being checked.
  checking,

  /// On the phone and checked.
  ready,

  /// Stopped: see [ModelStatus.problem].
  failed;

  static ModelState of(Object? s) => ModelState.values.firstWhere((v) => v.name == s, orElse: () => ModelState.absent);
}

/// Why a download stopped.
enum ModelProblem { none, checksum, room, server }

class ModelStatus {
  const ModelStatus({
    this.state = ModelState.absent,
    this.problem = ModelProblem.none,
    this.got = 0,
    this.total = 0,
    this.size = 0,
    this.free = 0,
    this.needed = 0,
    this.online = true,
    this.metered = false,
    this.wanted = false,
  });

  factory ModelStatus.of(Map<Object?, Object?> m) => ModelStatus(
        state: ModelState.of(m['state']),
        problem: switch (m['problem']) {
          'checksum' => ModelProblem.checksum,
          'room' => ModelProblem.room,
          'server' => ModelProblem.server,
          _ => ModelProblem.none,
        },
        got: (m['got'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        size: (m['size'] as num?)?.toInt() ?? 0,
        free: (m['free'] as num?)?.toInt() ?? 0,
        needed: (m['needed'] as num?)?.toInt() ?? 0,
        online: m['online'] != false,
        metered: m['metered'] == true,
        wanted: m['wanted'] == true,
      );

  final ModelState state;
  final ModelProblem problem;

  /// Bytes on the phone so far, of [total].
  final int got, total;

  /// The model's size on the phone, once it is there.
  final int size;

  /// Room on the phone, and the room this download still needs (with a margin).
  final int free, needed;
  final bool online, metered;

  /// The person tapped Download and it has not finished or been removed.
  final bool wanted;

  bool get ready => state == ModelState.ready;
  bool get busy => state == ModelState.downloading || state == ModelState.waiting || state == ModelState.checking;
  double get fraction => total <= 0 ? 0 : (got / total).clamp(0, 1).toDouble();

  /// Not enough room for it now (before or after asking).
  bool get noRoom => problem == ModelProblem.room || (!ready && !busy && free > 0 && free < needed);
}

/// The model on this phone, as the screens see it. Android only; elsewhere it stays [absent] and
/// nothing is ever downloaded.
class WordsModel extends ChangeNotifier {
  WordsModel._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'model' && call.arguments is Map) _set(ModelStatus.of(call.arguments as Map<Object?, Object?>));
    });
  }

  static final WordsModel instance = WordsModel._();

  static const _channel = MethodChannel('upon_thy_head/words');

  final WordsModelSpec spec = WordsModelSpec.current;
  ModelStatus _status = const ModelStatus();
  ModelStatus get status => _status;

  /// Called whenever the model arrives (the words of every recording waiting for it are written).
  final List<VoidCallback> _onReady = [];
  void whenReady(VoidCallback f) => _onReady.add(f);
  void notWhenReady(VoidCallback f) => _onReady.remove(f);

  void _set(ModelStatus s) {
    final arrived = s.ready && !_status.ready;
    _status = s;
    notifyListeners();
    if (arrived) {
      for (final f in [..._onReady]) {
        f();
      }
    }
  }

  Future<ModelStatus> _call(String method) async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>(method, {'model': spec.toMap()});
      if (m != null) _set(ModelStatus.of(m));
    } on MissingPluginException {
      // no native side (tests on the host)
    } on PlatformException catch (e) {
      debugPrint('model: $method: ${e.code} ${e.message}');
    }
    return _status;
  }

  /// Look again (and, at launch, carry on with a download the person had started).
  Future<ModelStatus> refresh({bool resume = false}) => _call(resume ? 'resume' : 'model');

  /// The person tapped Download.
  Future<ModelStatus> download() => _call('download');

  /// Stop the download and forget it.
  Future<ModelStatus> cancel() => _call('cancel');

  /// Take the model off the phone (Settings).
  Future<ModelStatus> remove() => _call('remove');

  /// Tests: set what the screens see.
  @visibleForTesting
  void debugSet(ModelStatus s) => _set(s);
}
