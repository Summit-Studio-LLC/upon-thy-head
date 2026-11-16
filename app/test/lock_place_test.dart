// The app lock's timing rule and its switch, and where blessings are given: rounding, the
// fallback, asking once, and the ring staying where the first blessing put it.
//
//   flutter test test/lock_place_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/sky/placement.dart';

class FakeLocator implements Locator {
  FakeLocator(this.answer, {this.at});
  LocationStatus current = LocationStatus.undetermined;
  final LocationStatus answer;
  ({double lat, double lon})? at;
  int asked = 0, opened = 0;
  @override
  Future<LocationStatus> status() async => current;
  @override
  Future<LocationStatus> request() async {
    asked++;
    return current = answer;
  }

  @override
  Future<({double lat, double lon})?> locate() async => current == LocationStatus.granted ? at : null;
  @override
  Future<void> openSettings() async => opened++;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('uth'));
  tearDown(() => dir.deleteSync(recursive: true));
  Future<Settings> settings() => Settings.open('${dir.path}/settings.json');

  group('when the app locks on its return', () {
    test('after more than 60 seconds away', () {
      expect(shouldLockOnReturn(away: const Duration(seconds: 70), recording: false, playing: false), isTrue);
      expect(shouldLockOnReturn(away: const Duration(seconds: 61), recording: false, playing: false), isTrue);
    });
    test('not at 60 seconds or less', () {
      expect(shouldLockOnReturn(away: const Duration(seconds: 60), recording: false, playing: false), isFalse);
      expect(shouldLockOnReturn(away: const Duration(seconds: 20), recording: false, playing: false), isFalse);
      expect(shouldLockOnReturn(away: Duration.zero, recording: false, playing: false), isFalse);
    });
    test('never while recording or while the review page plays', () {
      expect(shouldLockOnReturn(away: const Duration(hours: 1), recording: true, playing: false), isFalse);
      expect(shouldLockOnReturn(away: const Duration(hours: 1), recording: false, playing: true), isFalse);
    });
  });

  group('the lock', () {
    test('on by default, locked at launch', () async {
      final l = AppLock(api: NoLockApi(methodIs: LockMethod.faceId));
      await l.init(await settings());
      expect(l.chosen, isTrue);
      expect(l.locked, isTrue);
      expect(await l.unlock(), isTrue);
      expect(l.locked, isFalse);
    });
    test('a failed or cancelled unlock stays locked', () async {
      final api = NoLockApi(methodIs: LockMethod.faceId, answer: false);
      final l = AppLock(api: api);
      await l.init(await settings());
      expect(await l.unlock(), isFalse);
      expect(l.locked, isTrue);
      expect(api.asked, 1);
    });
    test('no passcode: cannot lock, opens unlocked, the choice is kept', () async {
      final l = AppLock(api: NoLockApi(methodIs: LockMethod.none));
      await l.init(await settings());
      expect(l.locked, isFalse);
      expect(l.active, isFalse);
      expect(l.chosen, isTrue);
      l.lock();
      expect(l.locked, isFalse);
    });
    test('turning it off asks first; a refusal leaves it on', () async {
      final api = NoLockApi(methodIs: LockMethod.touchId, answer: false);
      final s = await settings();
      final l = AppLock(api: api, startUnlocked: true);
      await l.init(s);
      expect(l.locked, isFalse);
      expect(await l.setChosen(false), isFalse);
      expect(s.lockOn, isTrue);
      api.answer = true;
      expect(await l.setChosen(false), isTrue);
      expect((await settings()).lockOn, isFalse, reason: 'kept on disk');
      final next = AppLock(api: api);
      await next.init(await settings());
      expect(next.locked, isFalse, reason: 'the next launch opens unlocked');
      expect(await next.setChosen(true), isTrue);
      expect(api.asked, 2, reason: 'turning it on does not ask');
      final again = AppLock(api: api);
      await again.init(await settings());
      expect(again.locked, isTrue);
    });
  });

  group('where blessings are given', () {
    test('rounded to one decimal place of a degree', () {
      final m = roughly(19.4326, -99.1332); // Mexico City
      expect(m.lat, 19.4);
      expect(m.lon, -99.1);
      expect(roughly(40.7704, -111.8919).lat, 40.8);
      expect(roughly(-33.8688, 151.2093).lon, 151.2);
      expect(roughly(-0.04, 0.04).lat, 0);
      expect(roughly(-0.04, 0.04).lat.isNegative, isFalse);
    });

    test('the Salt Lake Temple until a place is found', () async {
      final w = BlessingPlace(settings: await settings(), locator: FakeLocator(LocationStatus.denied));
      expect(w.fallback, isTrue);
      expect(w.place.lat, closeTo(40.7704, 1e-9));
      expect(w.place.lon, closeTo(-111.8919, 1e-9));
    });

    test('refused: asked once, the fallback stays, never asked again on its own', () async {
      final loc = FakeLocator(LocationStatus.denied);
      final w = BlessingPlace(settings: await settings(), locator: loc);
      await w.onRecordScreen(stillReady: () => true);
      expect(loc.asked, 1);
      expect(w.fallback, isTrue);
      loc.current = LocationStatus.undetermined; // as after Allow Once, at the next launch
      await w.onRecordScreen(stillReady: () => true);
      expect(loc.asked, 1);
    });

    test('allowed: kept rounded, and used for new blessings', () async {
      final loc = FakeLocator(LocationStatus.granted, at: (lat: 19.4326, lon: -99.1332));
      final s = await settings();
      final w = BlessingPlace(settings: s, locator: loc);
      await w.onRecordScreen(stillReady: () => true);
      expect(w.fallback, isFalse);
      expect([w.place.lat, w.place.lon], [19.4, -99.1]);
      expect([(await settings()).place!.lat, (await settings()).place!.lon], [19.4, -99.1]);
      expect(draftBlessing(DateTime.now(), place: w.place).place.lat, 19.4);
    });

    test('never asked once a blessing has begun', () async {
      final loc = FakeLocator(LocationStatus.granted, at: (lat: 1, lon: 2));
      final w = BlessingPlace(settings: await settings(), locator: loc);
      await w.onRecordScreen(stillReady: () => false);
      expect(loc.asked, 0);
    });

    test('While Using: refreshed quietly, without asking', () async {
      final loc = FakeLocator(LocationStatus.granted, at: (lat: 51.5072, lon: -0.1276))..current = LocationStatus.granted;
      final w = BlessingPlace(settings: await settings(), locator: loc);
      await w.onRecordScreen(stillReady: () => true);
      expect(loc.asked, 0);
      expect([w.place.lat, w.place.lon], [51.5, -0.1]);
    });

    test('Use my location after a refusal opens Settings', () async {
      final loc = FakeLocator(LocationStatus.denied)..current = LocationStatus.denied;
      final w = BlessingPlace(settings: await settings(), locator: loc);
      await w.useMyLocation();
      expect(loc.opened, 1);
      expect(loc.asked, 0);
    });
  });

  test('the ring stays where the first blessing put it when a place is found later', () {
    Blessing b(String id, DateTime utc, Place place) =>
        Blessing(id: id, title: id, from: '', utc: utc, utcOffset: Duration.zero, place: place);
    final first = b('a', DateTime.utc(2026, 11, 15, 3), saltLakeTemple);
    const ring = RingPlacement();
    ring.apply([first], now: DateTime.utc(2026, 11, 16));
    final ra0 = first.ra, dec0 = first.dec;
    final second = b('b', DateTime.utc(2026, 11, 20, 3), roughly(19.4326, -99.1332));
    ring.apply([first, second], now: DateTime.utc(2026, 11, 21));
    expect(first.dec, closeTo(dec0, 1e-12), reason: 'the ring keeps the first blessing\'s latitude');
    expect(first.dec, closeTo(saltLakeTemple.lat * deg, 1e-12));
    expect(second.dec, closeTo(dec0, 1e-12), reason: 'later lights sit on the same ring');
    expect(first.ra, closeTo(ra0, 1e-9), reason: 'the first light does not move');
  });
}
