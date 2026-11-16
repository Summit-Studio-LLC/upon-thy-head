import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../sky/astro.dart';

/// Used when no place has been found: location refused, restricted, or not answered by Amen
/// (Noah, 2026-11-15). The Salt Lake Temple, 40°46′13″ N 111°53′31″ W.
const saltLakeTemple = Place(40.7704, -111.8919);

/// A place rounded to one decimal place of a degree (about 11 km north to south). The app never
/// needs to know more than roughly where on Earth a blessing was given: with the ring, a place only
/// decides which ring of sky the lights sit on and where it starts. Only an approximate place is
/// asked of the phone, and only this rounded one is kept.
Place roughly(double lat, double lon) => Place(_tenth(lat), _tenth(lon));

double _tenth(double x) {
  final r = (x * 10).round() / 10;
  return r == 0 ? 0 : r; // never -0.0
}

enum LocationStatus { undetermined, denied, restricted, granted }

/// The phone's location, as little of it as possible.
abstract class Locator {
  Future<LocationStatus> status();

  /// Put the system's question (only if it has not been answered), and return the answer.
  Future<LocationStatus> request();

  /// Where the phone roughly is, or null.
  Future<({double lat, double lon})?> locate();

  /// This app's page in the Settings app.
  Future<void> openSettings();
}

/// iOS: ios/Runner/Privacy.swift (`LocationChannel`).
class NativeLocator implements Locator {
  static const _channel = MethodChannel('upon_thy_head/location');
  static const _lock = MethodChannel('upon_thy_head/lock');

  static LocationStatus _status(String? s) => switch (s) {
        'granted' => LocationStatus.granted,
        'denied' => LocationStatus.denied,
        'restricted' => LocationStatus.restricted,
        _ => LocationStatus.undetermined,
      };

  @override
  Future<LocationStatus> status() async => _status(await _channel.invokeMethod<String>('status'));

  @override
  Future<LocationStatus> request() async => _status(await _channel.invokeMethod<String>('request'));

  @override
  Future<({double lat, double lon})?> locate() async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('locate');
    if (m == null) return null;
    return (lat: (m['lat'] as num).toDouble(), lon: (m['lon'] as num).toDouble());
  }

  @override
  Future<void> openSettings() => _lock.invokeMethod<void>('openSettings');
}

/// No location at all (tests on the host, other platforms): the fallback is always used.
class NoLocator implements Locator {
  const NoLocator();
  @override
  Future<LocationStatus> status() async => LocationStatus.denied;
  @override
  Future<LocationStatus> request() async => LocationStatus.denied;
  @override
  Future<({double lat, double lon})?> locate() async => null;
  @override
  Future<void> openSettings() async {}
}

/// "The place blessings are given": found once, kept rounded in the settings, used for every new
/// blessing. Until one is found, and whenever location is refused, the Salt Lake Temple.
///
/// Each blessing keeps the place it was given with, so finding a place later never moves a light
/// already in the sky: the ring stays where the first blessing put it.
class BlessingPlace extends ChangeNotifier {
  BlessingPlace({required this.settings, required this.locator});

  final Settings settings;
  final Locator locator;

  /// The place for a new blessing now.
  Place get place => settings.place ?? saltLakeTemple;

  /// No place has been found, so the Salt Lake Temple is in use.
  bool get fallback => settings.place == null;

  LocationStatus? _status;
  LocationStatus? get status => _status;

  /// The recording screen has opened and its microphone and speech questions are answered. The
  /// first time ever, the system's location question is put ([stillReady] is checked just before,
  /// so it is never put once a blessing has begun). After that, only if location is already
  /// allowed (While Using) is the place quietly refreshed; the question is never put again.
  Future<void> onRecordScreen({required bool Function() stillReady}) async {
    try {
      var s = _status = await locator.status();
      if (s == LocationStatus.undetermined && !settings.locationAsked && stillReady()) {
        await settings.setLocationAsked();
        s = _status = await locator.request();
      }
      notifyListeners();
      if (s == LocationStatus.granted) await refresh();
    } catch (e) {
      debugPrint('place: $e');
    }
  }

  /// Settings' "Use my location": ask if never answered this time, open Settings if refused,
  /// else look now.
  Future<void> useMyLocation() async {
    try {
      var s = _status = await locator.status();
      if (s == LocationStatus.undetermined) {
        await settings.setLocationAsked();
        s = _status = await locator.request();
      } else if (s != LocationStatus.granted) {
        await locator.openSettings();
        return;
      }
      notifyListeners();
      if (s == LocationStatus.granted) await refresh();
    } catch (e) {
      debugPrint('place: $e');
    }
  }

  /// Look again at where the phone is, if allowed, and keep it (rounded).
  Future<void> refresh() async {
    final at = await locator.locate();
    if (at == null) return;
    final r = roughly(at.lat, at.lon);
    final old = settings.place;
    if (old != null && old.lat == r.lat && old.lon == r.lon) return;
    await settings.setPlace(r);
    debugPrint('place: near ${r.lat}, ${r.lon}');
    notifyListeners();
  }

  /// Look up the permission again (back from the Settings app).
  Future<void> recheck() async {
    try {
      _status = await locator.status();
      notifyListeners();
    } catch (_) {}
  }
}
