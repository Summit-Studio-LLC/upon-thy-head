import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sky/astro.dart';

/// The few choices the app remembers between launches, in one small JSON file in
/// Library/Application Support: the app lock, the language recordings start in, where blessings
/// are given, and whether location has been asked for.
class Settings {
  Settings(this.path);

  final String path;
  Map<String, Object?> _values = {};
  Future<void> _writing = Future.value();

  static Future<Settings> open([String? path]) async {
    final s = Settings(path ?? p.join((await getApplicationSupportDirectory()).path, 'settings.json'));
    try {
      final f = File(s.path);
      if (await f.exists()) s._values = (jsonDecode(await f.readAsString()) as Map).cast();
    } catch (_) {
      // unreadable: start again from the defaults
    }
    return s;
  }

  /// The language the Begin screen's pull-down starts on: "en" or "es", or null for "Same as this
  /// iPhone" (the default). Choosing on the Begin screen sets it too, so the choice is remembered.
  String? get language {
    final v = _values['recordingLanguage'];
    return v is String ? v : null;
  }

  Future<void> setLanguage(String? code) => _set('recordingLanguage', code);

  /// The app lock. On unless the person turned it off (product brief).
  bool get lockOn {
    final v = _values['lock'];
    return v is bool ? v : true;
  }

  Future<void> setLockOn(bool on) => _set('lock', on);

  /// "The place blessings are given", rounded to a tenth of a degree (place/where.dart), or null
  /// when none has been found (then the Salt Lake Temple is used).
  Place? get place {
    final m = _values['place'];
    if (m is! Map) return null;
    final lat = m['lat'], lon = m['lon'];
    return lat is num && lon is num && lat.isFinite && lon.isFinite ? Place(lat.toDouble(), lon.toDouble()) : null;
  }

  Future<void> setPlace(Place? place) => _set('place', place == null ? null : {'lat': place.lat, 'lon': place.lon});

  /// The system's location question has been put once; the app never puts it again on its own.
  bool get locationAsked {
    final v = _values['locationAsked'];
    return v is bool ? v : false;
  }

  Future<void> setLocationAsked() => _set('locationAsked', true);

  /// Where the first-run flow stands (onboarding/first_run.dart): null on a fresh install, then
  /// its steps by name, "done" when it is over. Kept here so it is shown once, and a reinstall
  /// starts again.
  String? get firstRun {
    final v = _values['firstRun'];
    return v is String ? v : null;
  }

  Future<void> setFirstRun(String? step) => _set('firstRun', step);

  /// The Face ID question has been put by the first-run flow (iOS can say "denied" afterwards,
  /// but not "never asked" on a phone with Face ID off).
  bool get faceIdAsked {
    final v = _values['faceIdAsked'];
    return v is bool ? v : false;
  }

  Future<void> setFaceIdAsked() => _set('faceIdAsked', true);

  /// Whose sky was showing last (a family member's id, people/person.dart), so the app reopens on
  /// it; '' or unset for the person's own.
  String get sky {
    final v = _values['sky'];
    return v is String ? v : '';
  }

  Future<void> setSky(String id) => _set('sky', id.isEmpty ? null : id);

  /// The "Kept by" name typed when a ring was last handed over ("Dad"), offered the next time;
  /// null until one has been sent.
  String? get keptBy {
    final v = _values['keptBy'];
    return v is String ? v : null;
  }

  Future<void> setKeptBy(String name) => _set('keptBy', name.trim().isEmpty ? null : name.trim());

  Future<void> _set(String key, Object? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final next = _writing.catchError((_) {}).then((_) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode(_values), flush: true);
      await tmp.rename(path);
    });
    _writing = next;
    return next;
  }
}
