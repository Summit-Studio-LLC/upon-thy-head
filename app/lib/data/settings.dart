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
  String? get language => _values['recordingLanguage'] as String?;

  Future<void> setLanguage(String? code) => _set('recordingLanguage', code);

  /// The app lock. On unless the person turned it off (product brief).
  bool get lockOn => _values['lock'] as bool? ?? true;

  Future<void> setLockOn(bool on) => _set('lock', on);

  /// "The place blessings are given", rounded to a tenth of a degree (place/where.dart), or null
  /// when none has been found (then the Salt Lake Temple is used).
  Place? get place {
    final m = _values['place'];
    if (m is! Map) return null;
    final lat = m['lat'], lon = m['lon'];
    return lat is num && lon is num ? Place(lat.toDouble(), lon.toDouble()) : null;
  }

  Future<void> setPlace(Place? place) => _set('place', place == null ? null : {'lat': place.lat, 'lon': place.lon});

  /// The system's location question has been put once; the app never puts it again on its own.
  bool get locationAsked => _values['locationAsked'] as bool? ?? false;

  Future<void> setLocationAsked() => _set('locationAsked', true);

  /// Where the first-run flow stands (onboarding/first_run.dart): null on a fresh install, then
  /// its steps by name, "done" when it is over. Kept here so it is shown once, and a reinstall
  /// starts again.
  String? get firstRun => _values['firstRun'] as String?;

  Future<void> setFirstRun(String? step) => _set('firstRun', step);

  /// The Face ID question has been put by the first-run flow (iOS can say "denied" afterwards,
  /// but not "never asked" on a phone with Face ID off).
  bool get faceIdAsked => _values['faceIdAsked'] as bool? ?? false;

  Future<void> setFaceIdAsked() => _set('faceIdAsked', true);

  /// Whose sky was showing last (a family member's id, people/person.dart), so the app reopens on
  /// it; '' or unset for the person's own.
  String get sky => _values['sky'] as String? ?? '';

  Future<void> setSky(String id) => _set('sky', id.isEmpty ? null : id);

  Future<void> _set(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(_values));
  }
}
