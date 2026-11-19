import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/audio.dart';
import '../data/blessing.dart';
import '../data/samples.dart';
import '../data/store.dart';
import '../not_yet.dart';
import '../place/where.dart';
import '../record/android_words.dart';
import '../record/speech.dart';
import '../record/transcriber.dart';
import '../record/words_model.dart';
import '../sky/placement.dart';
import '../sky/sky_engine.dart';
import '../sky/sky_painter.dart';
import '../sky/sky_view.dart';
import '../theme.dart';
import '../widgets/scrims.dart';
import 'spoken.dart';

/// `--dart-define=PHONE_CHECK=true` adds "Phone check" to Settings, and the build bundles the
/// prepared recordings (ios/Runner: the "Phone check audio" build phase). Never in builds for people.
const bool phoneCheck = bool.fromEnvironment('PHONE_CHECK');

/// Printed around the report in the log, so tool/phone.sh can cut it out.
const reportBegin = '===== UPON THY HEAD PHONE CHECK BEGIN =====';
const reportEnd = '===== UPON THY HEAD PHONE CHECK END =====';

const _check = MethodChannel('upon_thy_head/check');
const _lock = MethodChannel('upon_thy_head/lock');
const _player = MethodChannel('upon_thy_head/player');

/// Whether the app was launched with `--open-phone-check` (tool/phone.sh --check).
Future<bool> phoneCheckAsked() async =>
    phoneCheck && ((await _check.invokeListMethod<String>('arguments')) ?? const []).contains('--open-phone-check');

/// Something the person can do from a check's row (start a download, answer a question).
class CheckAction {
  CheckAction(this.label, this.run, {this.rerun = const []});
  final String label;

  /// Does the thing; [say] shows progress under the button.
  final Future<void> Function(void Function(String) say) run;

  /// The checks (by number) to run again once it is done.
  final List<int> rerun;
}

class CheckOutcome {
  CheckOutcome(this.lines, [this.actions = const []]);
  final List<String> lines;
  final List<CheckAction> actions;
}

/// What a check may ask of the page: to put the sky over everything while it measures.
abstract class CheckHost {
  void showOver(Widget? w);
}

class PhoneCheckItem {
  PhoneCheckItem(this.number, this.title, this.limit, this.body);
  final int number;
  final String title;
  final Duration limit;
  final Future<CheckOutcome> Function(CheckHost host) body;
}

/// All the checks, in the order they run and are reported. A check that may put one of the system's
/// questions (5, 6, 9) has minutes, not seconds, so the time a person takes to answer is not a failure.
List<PhoneCheckItem> phoneChecks() => [
      PhoneCheckItem(1, 'This phone', const Duration(seconds: 15), (_) => _thisPhone()),
      PhoneCheckItem(2, 'Speech engines', const Duration(seconds: 30), (_) => _engines()),
      PhoneCheckItem(3, 'Writing the prepared recordings', const Duration(minutes: 5), (_) => _recordings()),
      PhoneCheckItem(4, 'Permissions', const Duration(minutes: 2), (_) => _permissions()),
      PhoneCheckItem(5, 'The microphone', const Duration(minutes: 3), (_) => _microphone()),
      PhoneCheckItem(6, 'A cut-off recording', const Duration(minutes: 3), (_) => _cutOff()),
      PhoneCheckItem(7, 'The sky\'s speed', const Duration(seconds: 60), _sky),
      PhoneCheckItem(8, 'The lock', const Duration(seconds: 10), (_) => _lockMethod()),
      PhoneCheckItem(9, 'Location', const Duration(minutes: 3), (_) => _location()),
      PhoneCheckItem(10, 'Storage', const Duration(seconds: 15), (_) => _storage()),
    ];

// ---- 1. this phone ----

/// Apple's model identifiers for the iPhones this app is likely to meet. Others are shown as the
/// identifier alone.
const _models = {
  'iPhone13,1': 'iPhone 12 mini', 'iPhone13,2': 'iPhone 12', 'iPhone13,3': 'iPhone 12 Pro', 'iPhone13,4': 'iPhone 12 Pro Max',
  'iPhone14,4': 'iPhone 13 mini', 'iPhone14,5': 'iPhone 13', 'iPhone14,2': 'iPhone 13 Pro', 'iPhone14,3': 'iPhone 13 Pro Max',
  'iPhone14,6': 'iPhone SE (3rd generation)', 'iPhone14,7': 'iPhone 14', 'iPhone14,8': 'iPhone 14 Plus',
  'iPhone15,2': 'iPhone 14 Pro', 'iPhone15,3': 'iPhone 14 Pro Max', 'iPhone15,4': 'iPhone 15', 'iPhone15,5': 'iPhone 15 Plus',
  'iPhone16,1': 'iPhone 15 Pro', 'iPhone16,2': 'iPhone 15 Pro Max', 'iPhone17,1': 'iPhone 16 Pro', 'iPhone17,2': 'iPhone 16 Pro Max',
  'iPhone17,3': 'iPhone 16', 'iPhone17,4': 'iPhone 16 Plus', 'iPhone17,5': 'iPhone 16e',
};

String get buildMode => kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

String _gb(num bytes) => bytes < 0 ? 'unknown' : '${(bytes / 1e9).toStringAsFixed(1)} GB';

Future<CheckOutcome> _thisPhone() async {
  final d = (await _check.invokeMethod<Map<Object?, Object?>>('device'))!;
  if (Phone.android) return _thisPhoneAndroid(d);
  final sim = d['simulated'] as String;
  final id = sim.isNotEmpty ? sim : d['machine'] as String;
  final name = _models[id];
  final fps = d['fps'] as int;
  final renderer = ui.ImageFilter.isShaderFilterSupported ? 'Impeller' : 'Skia';
  return CheckOutcome([
    if (sim.isNotEmpty)
      'This is a simulator ("${d['simulatorName']}", model code $id), not a real phone.'
    else
      name == null ? 'Model code: $id (Apple\'s code for the model; this list does not know its name).' : 'Model: $name ($id).',
    'Software: ${d['system']}.',
    'Build: $buildMode${kDebugMode ? ' (slow on purpose; speeds below are not real)' : ''}. Drawing with $renderer.',
    'Screen: up to $fps frames a second${fps >= 120 ? ' (ProMotion)' : ''}.',
    'Storage: ${_gb(d['free'] as num)} free of ${_gb(d['total'] as num)}. Memory: ${_gb(d['memory'] as num)}.',
  ]);
}

// ---- 2. speech engines ----

const _locales = {'en': ['en-US'], 'es': ['es-US', 'es-MX', 'es-ES']};
const _langName = {'en': 'English', 'es': 'Spanish'};

class _Engines {
  _Engines(Map<Object?, Object?> m)
      : present = (m['analyzer'] as Map)['present'] == true,
        available = (m['analyzer'] as Map)['isAvailable'] == true,
        analyzer = ((m['analyzer'] as Map)['locales'] as Map? ?? {}).cast<String, String>(),
        recognizer = (m['recognizer'] as Map).cast<String, String>(),
        chosen = {
          for (final e in (m['chosen'] as Map).entries)
            e.key as String: (engine: (e.value as Map)['engine'] as String, locale: (e.value as Map)['locale'] as String),
        };

  final bool present, available;
  final Map<String, String> analyzer, recognizer;
  final Map<String, ({String engine, String locale})> chosen;

  static Future<_Engines> read() async => _Engines((await _check.invokeMethod<Map<Object?, Object?>>('engines'))!);
}

String _analyzerWords(String? s) => switch (s) {
      'installed' => 'can write it now',
      'supported' => 'needs its language model downloaded first',
      'downloading' => 'is downloading its language model',
      _ => 'cannot write it',
    };

String _recognizerWords(String? s) => switch (s) {
      'on-device' => 'can write it on the phone',
      'server only' => 'could only write it by sending it to Apple, which the app never does',
      _ => 'cannot write it',
    };

String _engineName(String e) => e == 'analyzer' ? 'Apple\'s new engine' : 'the older recogniser';

Future<CheckOutcome> _engines() async {
  if (Phone.android) return _enginesAndroid();
  final e = await _Engines.read();
  final lines = <String>[
    if (!e.present) 'Apple\'s new engine: not on this version of iOS (it needs iOS 26).'
    else if (!e.available) 'Apple\'s new engine: iOS has it, but says it is not available on this phone.'
    else 'Apple\'s new engine: present and available.',
  ];
  for (final MapEntry(key: lang, value: ids) in _locales.entries) {
    for (final id in ids) {
      final a = e.available ? 'the new engine ${_analyzerWords(e.analyzer[id])}' : 'no new engine';
      lines.add('${_langName[lang]} ($id): $a; the older recogniser ${_recognizerWords(e.recognizer[id])}.');
    }
  }
  for (final lang in _locales.keys) {
    final c = e.chosen[lang];
    if (c == null) {
      lines.add('For ${_langName[lang]} the app will use nothing: no engine can write it on this phone, so a '
          '${_langName[lang]} blessing is kept as audio and its words wait until they can be written.');
    } else if (c.engine == 'analyzer') {
      final st = e.analyzer[c.locale];
      lines.add('For ${_langName[lang]} the app will use Apple\'s new engine (${c.locale}), because the phone has it and it supports ${c.locale}'
          '${st == 'installed' ? '.' : '; it will ask iOS to download the language model when a recording starts.'}');
    } else {
      lines.add('For ${_langName[lang]} the app will use the older recogniser (${c.locale}), '
          '${e.available ? 'because the new engine does not support ${_langName[lang]} here' : 'because the new engine is not available'}, '
          'and the older one can write ${c.locale} on the phone.');
    }
  }
  return CheckOutcome(lines);
}

// ---- 3. the prepared recordings ----

Future<Map<String, String>> _audio() async =>
    (await _check.invokeMethod<Map<Object?, Object?>>('audio'))!.map((k, v) => MapEntry(k as String, v as String));

String _first(String s, int n) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length <= n ? one : '${one.substring(0, n)}…';
}

int _marks(String s) => RegExp(r'[.,;:!?¿¡]').allMatches(s).length;

/// One recording through one engine: a sentence for the report.
Future<String> _write(String lang, String path, String engine) async {
  final said = lang == 'en' ? spokenEnglish : spokenSpanish;
  final label = '${_langName[lang]}, ${_engineName(engine)}';
  try {
    final m = (await _check.invokeMethod<Map<Object?, Object?>>('transcribe', {'path': path, 'language': lang, 'engine': engine})
        .timeout(const Duration(seconds: 100)))!;
    final text = m['text'] as String;
    final w = wordErrors(said, text);
    final secs = (m['seconds'] as num).toDouble(), took = (m['ms'] as num) / 1000;
    final um = lang == 'en'
        ? (words(text).contains('um') ? '"um" kept' : '"um" dropped')
        : 'no "um" in this recording';
    return '$label (${m['locale']}): ${w.errors} words wrong out of ${w.spoken}; '
        '${took.toStringAsFixed(1)} s to write ${secs.toStringAsFixed(1)} s of audio; '
        '${_marks(text)} punctuation marks of ${_marks(said)} spoken; $um. '
        'It wrote: "${_first(text, 200)}"';
  } on PlatformException catch (e) {
    if (e.code == 'unavailable' && (e.message ?? '').startsWith('no on-device engine')) {
      return '$label: cannot write ${_langName[lang]} on this phone without sending it to Apple, so it was not tried.';
    }
    return '$label: ${e.code == 'unavailable' ? 'cannot' : 'failed'}: ${e.message}';
  } on TimeoutException {
    return '$label: no answer after 100 seconds; stopped waiting.';
  }
}

Future<CheckOutcome> _recordings() async {
  if (Phone.android) return _recordingsAndroid();
  final e = await _Engines.read();
  final audio = await _audio();
  final speech = await _check.invokeMethod<String>('speechAuth');
  final lines = <String>[];
  final actions = <CheckAction>[];
  for (final lang in _locales.keys) {
    final path = audio[lang]!;
    if (e.available) {
      final id = _locales[lang]!.firstWhere((i) => e.analyzer[i] != null && e.analyzer[i] != 'unsupported', orElse: () => '');
      if (id.isEmpty) {
        lines.add('${_langName[lang]}, Apple\'s new engine: does not support ${_langName[lang]} on this phone.');
      } else if (e.analyzer[id] != 'installed') {
        lines.add('${_langName[lang]}, Apple\'s new engine: its $id language model is not downloaded yet, so it was not tried.');
        actions.add(_download(id));
      } else {
        lines.add(await _write(lang, path, 'analyzer'));
      }
    }
    if (speech != 'granted') {
      lines.add('${_langName[lang]}, the older recogniser: not tried, because it needs speech-recognition permission ($speech). '
          'See check 4.');
    } else {
      lines.add(await _write(lang, path, 'recognizer'));
    }
  }
  return CheckOutcome(lines, actions);
}

CheckAction _download(String locale) => CheckAction('Download the $locale model', (say) async {
      await _check.invokeMethod<void>('download', {'locale': locale});
      final end = DateTime.now().add(const Duration(minutes: 15));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final m = (await _check.invokeMethod<Map<Object?, Object?>>('progress', {'locale': locale}))!;
        if (m['error'] != null) return say('The download failed: ${m['error']}');
        if (m['done'] == true) return say('Downloaded.');
        say('Downloading: ${((m['fraction'] as num) * 100).round()}%');
      }
      say('Still not finished after 15 minutes; stopped watching.');
    }, rerun: [2, 3]);

// ---- 4. permissions ----

String _permWords(String s) => switch (s) {
      'granted' => 'allowed',
      'denied' => 'refused',
      'restricted' => 'blocked by Screen Time or a profile',
      _ => 'not asked yet',
    };

Future<CheckOutcome> _permissions() async {
  if (Phone.android) return _permissionsAndroid();
  final perms = await NativeSpeech.instance.permissions();
  final speech = (await _check.invokeMethod<String>('speechAuth'))!;
  final location = await NativeLocator().status();
  String w(Permission x) => switch (x) { Permission.granted => 'allowed', Permission.denied => 'refused', _ => 'not asked yet' };
  final lines = [
    'Microphone: ${w(perms.microphone)}.',
    'Speech recognition: ${_permWords(speech)}.',
    'Location: ${_permWords(location.name)}'
        '${location == LocationStatus.granted ? ((await _check.invokeMethod<bool>('preciseLocation')) == true ? ', with Precise Location on (the app asks only for an approximate place)' : ', approximate only, as the app asks') : ''}.',
  ];
  final actions = <CheckAction>[];
  // Apple: the speech-recognition question "only applies to speech recognition using
  // SFSpeechRecognizer"; "SpeechAnalyzer transcriber modules don't send audio data of the user's
  // voice to Apple's servers" (docs/decisions-and-parked-ideas.md). This proves it on the phone.
  final e = await _Engines.read();
  final id = e.analyzer['en-US'];
  if (!e.available) {
    lines.add('The new engine without speech-recognition permission: cannot be tried, because this phone does not have the new engine.');
  } else if (speech == 'granted') {
    lines.add('The new engine without speech-recognition permission: cannot be tried while speech recognition is allowed. '
        'To try it, turn off Speech Recognition in iPhone Settings > Apps > Upon Thy Head, come back and tap Run again.');
  } else if (id != 'installed') {
    lines.add('The new engine without speech-recognition permission: not tried yet, because its en-US model is not downloaded (check 3).');
  } else {
    final before = speech;
    final r = await _write('en', (await _audio())['en']!, 'analyzer');
    final after = (await _check.invokeMethod<String>('speechAuth'))!;
    final worked = r.contains('words wrong out of');
    lines.add(worked
        ? 'The new engine without speech-recognition permission (${_permWords(before)}): it works. $r'
        : 'The new engine without speech-recognition permission (${_permWords(before)}): it did not work. $r');
    lines.add(after == before
        ? 'No question appeared and the permission is still ${_permWords(after)}.'
        : 'The permission changed from ${_permWords(before)} to ${_permWords(after)} while it ran.');
    if (worked) {
      lines.add('So on this phone the app can write words with the new engine without asking Apple\'s speech question.');
    }
  }
  if (perms.anyUndetermined) {
    actions.add(CheckAction('Ask for the microphone and speech recognition', (say) async {
      final p = await NativeSpeech.instance.requestPermissions();
      say('Microphone ${w(p.microphone)}, speech recognition ${w(p.speech)}.');
    }, rerun: [3, 4]));
  }
  return CheckOutcome(lines, actions);
}

// ---- 5. the microphone ----

Future<String> _tmp(String name) async {
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'phone_check'));
  await dir.create(recursive: true);
  return p.join(dir.path, name);
}

Future<CheckOutcome> _microphone() async {
  final mic = await _check.invokeMethod<String>('askMicrophone');
  if (mic != 'granted') {
    return CheckOutcome([
      Phone.android
          ? 'The microphone is refused, so nothing could be recorded. Allow it in Settings > Apps > Upon Thy Head.'
          : 'The microphone is refused, so nothing could be recorded. Allow it in iPhone Settings > Apps > Upon Thy Head.',
    ]);
  }
  final path = await _tmp('microphone.m4a');
  final rec = NativeSpeech.instance;
  await rec.start(path);
  await Future<void>.delayed(const Duration(seconds: 5));
  final out = await rec.stop();
  final m = (await _check.invokeMethod<Map<Object?, Object?>>('inspect', {'path': out}))!;
  if (m['error'] != null) return CheckOutcome(['Recorded, but the file ${m['error']} (${m['bytes']} bytes).']);
  final peak = (m['peak'] as num).toDouble();
  final lines = [
    'Recorded ${(m['seconds'] as num).toStringAsFixed(1)} s: ${m['format']}, ${((m['sampleRate'] as num) / 1000).toStringAsFixed(0)} kHz, '
        '${m['channels']} channel${m['channels'] == 1 ? '' : 's'}, ${((m['bytes'] as num) / 1024).toStringAsFixed(0)} KB.',
    'Loudest level heard: ${peak.toStringAsFixed(0)} dB below full scale '
        '(${peak > -50 ? 'it heard sound' : 'almost silence: the microphone may not be hearing anything'}).',
  ];
  try {
    final secs = (await _player.invokeMethod<num>('load', {'path': out}))!.toDouble();
    final played = await _player.invokeMethod<bool>('play');
    if (played == true) {
      await Future<void>.delayed(Duration(milliseconds: (secs * 1000).round() + 400));
      lines.add('Played it back (${secs.toStringAsFixed(1)} s). You should have heard it from the phone\'s speaker.');
    } else {
      lines.add('Could not play it back: the phone would not give the app its audio (is a call going on?).');
    }
  } finally {
    await _player.invokeMethod<void>('unload');
  }
  return CheckOutcome(lines);
}

// ---- 6. a cut-off recording ----

Future<CheckOutcome> _cutOff() async {
  if (await _check.invokeMethod<String>('askMicrophone') != 'granted') return CheckOutcome(['The microphone is refused, so this could not be tried.']);
  // in the real audio folder, as a blessing's recording is (the next launch would clear anything left)
  final path = p.join(await defaultAudioDir(), 'phone-check-cutoff.m4a');
  final rec = NativeSpeech.instance;
  final watch = Stopwatch()..start();
  await rec.start(path);
  try {
    await Future<void>.delayed(const Duration(seconds: 10));
    final m = (await _check.invokeMethod<Map<Object?, Object?>>('partSeconds', {'path': path}))!;
    final t = watch.elapsedMilliseconds / 1000, s = (m['seconds'] as num).toDouble();
    if (m['bytes'] == 0) {
      return CheckOutcome(['After ${t.toStringAsFixed(1)} s of recording, nothing had reached the file on disk. The microphone may not be allowed (check 4), '
          'or the phone is writing later than the simulator did.']);
    }
    return CheckOutcome([
      'After ${t.toStringAsFixed(1)} s of recording, still recording, ${s.toStringAsFixed(1)} s could be read back from the unfinished file '
          '(${((m['bytes'] as num) / 1024).toStringAsFixed(0)} KB on disk in the audio folder), as recovery would read it after the app was killed.',
      t - s <= 3
          ? 'That is ${(t - s).toStringAsFixed(1)} s short, as expected (on the simulator it was within about two seconds).'
          : 'That is ${(t - s).toStringAsFixed(1)} s short, more than the two or so seconds seen on the simulator.',
    ]);
  } finally {
    await rec.cancel();
  }
}

// ---- 7. the sky ----

Future<CheckOutcome> _sky(CheckHost host) async {
  final assets = await loadSkyAssets();
  final fps = ((await _check.invokeMethod<Map<Object?, Object?>>('device'))!['fps'] as int).clamp(30, 240);
  final lines = <String>[
    if (kDebugMode) 'This is a debug build, so these speeds are much slower than the real app.',
  ];
  try {
    for (final (name, list) in [('5 blessings', sampleBlessings()), ('120 blessings', denseBlessings())]) {
      lines.add(await _measure(host, assets, list, name, fps));
    }
  } finally {
    host.showOver(null);
  }
  lines.add('A frame is slow when building or drawing it took longer than ${(1000 / fps).toStringAsFixed(1)} ms, one refresh of this screen.');
  return CheckOutcome(lines);
}

Future<String> _measure(CheckHost host, SkyAssets assets, List<Blessing> list, String name, int fps) async {
  const placement = RingPlacement();
  placement.apply(list);
  final engine = SkyEngine(list, focus: list.length - 1);
  host.showOver(Stack(children: [
    Positioned.fill(child: SkyWidget(engine: engine, assets: assets, palette: Palette.lamplight, line: placement.line(list), interactive: false)),
    const Positioned(left: 0, right: 0, top: 0, height: 190, child: TopScrim(palette: Palette.lamplight)),
    const Positioned(left: 0, right: 0, bottom: 0, height: 392, child: BottomScrim(palette: Palette.lamplight)),
  ]));
  // let the first frames (shader warm-up, images uploaded) pass before measuring
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(collect);
  final watch = Stopwatch()..start();
  var running = true;
  Duration? last;
  var dragging = false;
  void tick(Duration ts) {
    if (!running) return;
    final dt = last == null ? 1 / 60 : (ts - last!).inMicroseconds / 1e6;
    last = ts;
    final t = watch.elapsedMilliseconds / 1000;
    if (t < 5) {
      // a slow drag right to left, drifting up and down
      if (!dragging) {
        engine.dragStart();
        dragging = true;
      }
      engine.dragBy(Offset(-220 * dt, 60 * math.sin(t * 2) * dt), dt);
    } else {
      if (dragging) {
        engine.dragEnd(still: true);
        dragging = false;
      }
      // pinching in and out, from the home view to close in and back, every 2.5 s
      engine.pinch(60 + 40 * math.cos((t - 5) * 2 * math.pi / 2.5), const Offset(200, 420));
    }
    SchedulerBinding.instance.scheduleFrameCallback(tick);
  }

  SchedulerBinding.instance.scheduleFrameCallback(tick);
  await Future<void>.delayed(const Duration(seconds: 10));
  running = false;
  // timings arrive in batches; wait for the last
  await Future<void>.delayed(const Duration(milliseconds: 300));
  SchedulerBinding.instance.removeTimingsCallback(collect);
  final secs = watch.elapsedMilliseconds / 1000;
  host.showOver(null);
  if (timings.isEmpty) return '$name: no frames were reported.';
  final budget = 1000 / fps;
  double ms(Duration d) => d.inMicroseconds / 1000;
  var sum = 0.0, worst = 0.0;
  var slow = 0;
  for (final f in timings) {
    final b = ms(f.buildDuration), r = ms(f.rasterDuration);
    final frame = math.max(b, r);
    sum += frame;
    worst = math.max(worst, frame);
    if (frame > budget) slow++;
  }
  final n = timings.length;
  return '$name, 10 s of dragging then pinching: $n frames (${(n / secs).toStringAsFixed(0)} a second of $fps possible); '
      'average frame ${(sum / n).toStringAsFixed(1)} ms, worst ${worst.toStringAsFixed(1)} ms; '
      '$slow slow (${(100 * slow / n).toStringAsFixed(1)}%).';
}

// ---- 8. the lock ----

Future<CheckOutcome> _lockMethod() async {
  final m = await _lock.invokeMethod<String>('method');
  if (Phone.android) {
    return CheckOutcome([
      switch (m) {
        'fingerprint' => 'The phone unlocks with a fingerprint or screen lock. The app lock will ask for either.',
        'passcode' => 'The phone unlocks with a screen lock (a PIN, pattern or password). The app lock will ask for it.',
        _ => 'The phone has no screen lock, so the app cannot lock. Settings says to set one.',
      },
    ]);
  }
  return CheckOutcome([
    switch (m) {
      'faceID' => 'The phone unlocks with Face ID, and the passcode when Face ID fails. The app lock will ask for Face ID.',
      'touchID' => 'The phone unlocks with Touch ID, and the passcode when Touch ID fails. The app lock will ask for Touch ID.',
      'opticID' => 'The phone unlocks with Optic ID. The app lock will ask for it.',
      'passcode' => 'The phone has a passcode but no Face ID or Touch ID set up. The app lock will ask for the passcode.',
      _ => 'The phone has no passcode, so the app cannot lock. Settings says to set one.',
    },
  ]);
}

// ---- 9. location ----

Future<CheckOutcome> _location() async {
  final loc = NativeLocator();
  var status = await loc.status();
  final lines = <String>[];
  if (status == LocationStatus.undetermined) {
    lines.add('Location had not been asked; the system\'s question was put now.');
    status = await loc.request();
  }
  if (status != LocationStatus.granted) {
    return CheckOutcome([...lines, 'Location is ${status.name}, so no place was found. The app would use the Salt Lake Temple.']);
  }
  final watch = Stopwatch()..start();
  final fix = await loc.locate();
  final t = watch.elapsedMilliseconds / 1000;
  if (fix == null) return CheckOutcome([...lines, 'No place came within ${t.toStringAsFixed(1)} s. The app would use the Salt Lake Temple.']);
  final kept = roughly(fix.lat, fix.lon);
  // how far the rounding moved it, without putting the exact place in the report
  final dLat = (fix.lat - kept.lat) * 111.0, dLon = (fix.lon - kept.lon) * 111.0 * math.cos(fix.lat * math.pi / 180);
  return CheckOutcome([
    ...lines,
    'An approximate place came in ${t.toStringAsFixed(1)} s.',
    'Kept after rounding to a tenth of a degree: ${kept.lat}, ${kept.lon} (the rounding moved it ${math.sqrt(dLat * dLat + dLon * dLon).toStringAsFixed(1)} km). '
        'The exact place is not shown or kept.',
  ]);
}

// ---- 10. storage ----

Future<CheckOutcome> _storage() async {
  if (Phone.android) return _storageAndroid();
  final dir = await defaultAudioDir();
  final excluded = await _check.invokeMethod<bool>('backupExcluded', {'path': dir});
  final path = await SqliteBlessingStore.defaultPath();
  final lines = [
    switch (excluded) {
      true => 'The audio folder is marked as excluded from iCloud and computer backups.',
      false => 'The audio folder is NOT marked as excluded from backups.',
      _ => 'The audio folder does not exist yet (nothing has been recorded into it), so its backup setting could not be read.',
    },
  ];
  if (!File(path).existsSync()) {
    lines.add('The blessings file does not exist yet.');
  } else {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final v = db.userVersion;
      final n = db.select('SELECT count(*) AS n FROM blessings').first['n'];
      lines.add('The blessings file is at schema version $v${v == SqliteBlessingStore.schemaVersion ? ', the version this build writes' : '; this build writes ${SqliteBlessingStore.schemaVersion}'}. It holds $n blessing${n == 1 ? '' : 's'}.');
    } finally {
      db.close();
    }
  }
  return CheckOutcome(lines);
}

// ---- Android: the same ten checks, against this phone's own pieces ----

Future<CheckOutcome> _thisPhoneAndroid(Map<Object?, Object?> d) async {
  final sim = d['simulated'] as String? ?? '';
  final renderer = ui.ImageFilter.isShaderFilterSupported ? 'Impeller' : 'Skia';
  return CheckOutcome([
    if (sim.isNotEmpty)
      'This is an emulator ("${d['simulatorName']}", ${d['name']}), not a real phone.'
    else
      'Phone: ${d['machine']}.',
    'Software: ${d['system']}. Processor: ${d['abi']}. Speech library: ${d['whisperLib']}.',
    'Build: $buildMode${kDebugMode ? ' (slow on purpose; speeds below are not real)' : ''}. Drawing with $renderer.',
    'Screen: up to ${d['fps']} frames a second.',
    'Storage: ${_gb(d['free'] as num)} free of ${_gb(d['total'] as num)}. Memory: ${_gb(d['memory'] as num)}.',
  ]);
}

Future<CheckOutcome> _enginesAndroid() async {
  final s = await WordsModel.instance.refresh();
  final lines = <String>[
    'Writing the words uses Whisper on this phone (whisper.cpp), for English and Spanish. Nothing is sent away.',
    switch (s.state) {
      ModelState.ready => 'The 60 MB speech model (ggml-base-q5_1) is on the phone and checked.',
      ModelState.downloading => 'The 60 MB speech model is downloading (${(s.fraction * 100).round()}%).',
      ModelState.waiting => 'The 60 MB speech model is waiting for a connection.',
      ModelState.checking => 'The 60 MB speech model arrived and is being checked.',
      ModelState.failed => 'The 60 MB speech model stopped (${s.problem.name}).',
      _ => 'The 60 MB speech model is not on the phone yet.',
    },
  ];
  return CheckOutcome(lines, [if (!s.ready) _downloadModel()]);
}

CheckAction _downloadModel() => CheckAction('Download the 60 MB speech model', (say) async {
      await WordsModel.instance.download();
      final end = DateTime.now().add(const Duration(minutes: 15));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final now = WordsModel.instance.status;
        if (now.ready) return say('Downloaded.');
        if (now.state == ModelState.failed) return say('The download failed: ${now.problem.name}');
        if (now.state == ModelState.waiting) {
          say('Waiting for a connection.');
        } else {
          say('Downloading: ${(now.fraction * 100).round()}%');
        }
      }
      say('Still not finished after 15 minutes; stopped watching.');
    }, rerun: [2, 3]);

Future<String> _writeWhisper(String lang, String path) async {
  final said = lang == 'en' ? spokenEnglish : spokenSpanish;
  final label = '${_langName[lang]}, Whisper';
  final sw = Stopwatch()..start();
  try {
    final t = await AndroidWords.instance.transcribe(path, SpeechLanguage.fromCode(lang)).timeout(const Duration(minutes: 4));
    if (t.later) return '$label: the speech model is not on the phone yet, so this was not written.';
    if (t.unavailable) return '$label: this phone cannot write ${_langName[lang]}.';
    final info = await _check.invokeMethod<Map<Object?, Object?>>('inspect', {'path': path});
    final secs = (info?['seconds'] as num?)?.toDouble() ?? 0;
    final w = wordErrors(said, t.text);
    final paras = t.text.split(RegExp(r'\n\s*\n')).where((s) => s.trim().isNotEmpty).length;
    final um = lang == 'en' ? (words(t.text).contains('um') ? '"um" kept' : '"um" dropped') : 'no "um" in this recording';
    return '$label: ${w.errors} words wrong out of ${w.spoken}; '
        '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s to write ${secs.toStringAsFixed(1)} s of audio; '
        '$paras paragraph${paras == 1 ? '' : 's'}; $um. It wrote: "${_first(t.text, 200)}"';
  } on TimeoutException {
    return '$label: no answer after 4 minutes; stopped waiting.';
  } catch (e) {
    return '$label: failed: $e';
  }
}

Future<CheckOutcome> _recordingsAndroid() async {
  final s = await WordsModel.instance.refresh();
  if (!s.ready) {
    return CheckOutcome(
      ['The speech model is not on the phone yet, so the prepared recordings were not written.'],
      [_downloadModel()],
    );
  }
  AndroidWords.useAudioFolder(await defaultAudioDir());
  final audio = await _audio();
  final lines = <String>[];
  for (final lang in _locales.keys) {
    lines.add(await _writeWhisper(lang, audio[lang]!));
  }
  return CheckOutcome(lines);
}

Future<CheckOutcome> _permissionsAndroid() async {
  final perms = await NativeSpeech.instance.permissions();
  final raw = await const MethodChannel('upon_thy_head/speech').invokeMethod<Map<Object?, Object?>>('permissions');
  final notes = raw?['notifications'] as String? ?? 'undetermined';
  final location = await NativeLocator().status();
  String w(Permission x) => switch (x) { Permission.granted => 'allowed', Permission.denied => 'refused', _ => 'not asked yet' };
  final lines = [
    'Microphone: ${w(perms.microphone)}.',
    'Notifications: ${_permWords(notes)}.',
    'Approximate location: ${_permWords(location.name)}.',
  ];
  final actions = <CheckAction>[];
  if (perms.microphone == Permission.undetermined || notes == 'undetermined') {
    actions.add(CheckAction('Ask for the microphone and notifications', (say) async {
      final p = await NativeSpeech.instance.requestPermissions();
      final again = await const MethodChannel('upon_thy_head/speech').invokeMethod<Map<Object?, Object?>>('permissions');
      say('Microphone ${w(p.microphone)}, notifications ${_permWords(again?['notifications'] as String? ?? 'undetermined')}.');
    }, rerun: [4, 5, 6]));
  }
  return CheckOutcome(lines, actions);
}

Future<CheckOutcome> _storageAndroid() async {
  final dir = await defaultAudioDir();
  final excluded = await _check.invokeMethod<bool>('backupExcluded', {'path': dir});
  final path = await SqliteBlessingStore.defaultPath();
  // Recordings live in the app's files folder. allowBackup is off for the whole app, and the
  // backup rules exclude everything; the no-backup folder is the second guard (models, the
  // silence finder). The channel's true means this path is inside that folder.
  final lines = <String>[
    switch (excluded) {
      true => 'The audio folder is inside the no-backup folder, and the app allows no backup.',
      false => 'The audio folder is not inside the no-backup folder. The app allows no backup (allowBackup is off, and the backup rules exclude everything), so recordings are not copied off the phone.',
      _ => 'The audio folder\'s backup setting could not be read.',
    },
  ];
  if (!File(path).existsSync()) {
    lines.add('The blessings file does not exist yet.');
  } else {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final v = db.userVersion;
      final n = db.select('SELECT count(*) AS n FROM blessings').first['n'];
      lines.add('The blessings file is at schema version $v${v == SqliteBlessingStore.schemaVersion ? ', the version this build writes' : '; this build writes ${SqliteBlessingStore.schemaVersion}'}. It holds $n blessing${n == 1 ? '' : 's'}.');
    } finally {
      db.close();
    }
  }
  return CheckOutcome(lines);
}
