import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../strings.dart';

/// How this phone proves it is its owner. [none]: no passcode (Android: no screen lock) is set, so
/// the app cannot lock. [fingerprint]: Android with a strong fingerprint enrolled; [passcode] on
/// Android is the screen lock (PIN, pattern or password) alone.
enum LockMethod { faceId, touchId, opticId, fingerprint, passcode, none }

/// The time away after which the app locks again on its return.
const lockAfter = Duration(seconds: 60);

/// The rule for locking when the app comes back: after more than [lockAfter] away, but never while
/// a recording is in progress or the review page's audio is playing in the background.
bool shouldLockOnReturn({required Duration away, required bool recording, required bool playing}) =>
    away > lockAfter && !recording && !playing;

/// The phone's own authentication and the switcher cover.
abstract class LockApi {
  Future<LockMethod> method();

  /// True when the person proved it is them. The system handles failures and lockouts.
  Future<bool> authenticate(String reason);

  /// Cover the app with the plain sky whenever it leaves the foreground.
  Future<void> cover(bool on);

  Future<String> version();

  /// The app is in front again: [away] since it went to the background ([background] false when it
  /// only went inactive). Answer once anything to hide is hidden; the cover is lifted then.
  set onActive(Future<void> Function(Duration away, bool background)? f);
}

/// iOS: ios/Runner/Privacy.swift (`LockChannel`); Android: LockChannel.kt.
class NativeLockApi implements LockApi {
  NativeLockApi() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'active') {
        final m = (call.arguments as Map?) ?? const {};
        final away = Duration(milliseconds: (((m['away'] as num?) ?? 0) * 1000).round());
        await _onActive?.call(away, m['background'] == true);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('upon_thy_head/lock');
  Future<void> Function(Duration, bool)? _onActive;

  @override
  set onActive(Future<void> Function(Duration away, bool background)? f) => _onActive = f;

  @override
  Future<LockMethod> method() async => switch (await _channel.invokeMethod<String>('method')) {
        'faceID' => LockMethod.faceId,
        'touchID' => LockMethod.touchId,
        'opticID' => LockMethod.opticId,
        'fingerprint' => LockMethod.fingerprint,
        'passcode' => LockMethod.passcode,
        _ => LockMethod.none,
      };

  @override
  Future<bool> authenticate(String reason) async => await _channel.invokeMethod<bool>('authenticate', {'reason': reason}) ?? false;

  @override
  Future<void> cover(bool on) => _channel.invokeMethod<void>('cover', {'on': on});

  @override
  Future<String> version() async => await _channel.invokeMethod<String>('version') ?? '';

  /// Android: the phone's own screen-lock settings (a phone with no screen lock).
  static Future<void> openSecurity() => _channel.invokeMethod<void>('openSecurity');

  /// The website's privacy policy or terms, [name] "privacy" or "terms", in the phone's own browser,
  /// leaving the app. Only a name crosses the channel: the two addresses live in the native code,
  /// which opens nothing else. (The browser loads the page; the app itself makes no network call.)
  static Future<void> openPage(String name) async {
    try {
      await _channel.invokeMethod<void>('openPage', {'name': name});
    } on MissingPluginException {
      // a test, or a platform without the channel: nothing to open
    } on PlatformException {
      // no browser to open it in: nothing to show
    }
  }

  /// Tests: whether the cover is up now.
  static Future<bool> debugCovered() async => await _channel.invokeMethod<bool>('debugCovered') ?? false;
}

/// No lock at all (tests on the host, other platforms).
class NoLockApi implements LockApi {
  NoLockApi({this.methodIs = LockMethod.none, this.answer = true});
  LockMethod methodIs;
  bool answer;
  int asked = 0;
  @override
  Future<LockMethod> method() async => methodIs;
  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return answer;
  }

  @override
  Future<void> cover(bool on) async {}
  @override
  Future<String> version() async => '';
  @override
  set onActive(Future<void> Function(Duration away, bool background)? f) {}
}

/// The app lock: on by default; the words are private, and a blessing starting never waits on it.
class AppLock extends ChangeNotifier {
  /// [startUnlocked]: the integration tests begin as if the person had just unlocked, with the
  /// lock itself on as a real user has it. Nothing else changes.
  AppLock({required this.api, this.startUnlocked = false});

  final LockApi api;
  final bool startUnlocked;
  Settings? _settings;

  LockMethod method = LockMethod.none;

  /// The person's choice (on unless turned off).
  bool get chosen => _settings?.lockOn ?? true;

  /// The lock works: chosen, and the phone has a passcode.
  bool get active => chosen && method != LockMethod.none;

  bool get locked => _locked;
  bool _locked = false;

  /// Asking now.
  bool get asking => _asking;
  bool _asking = false;

  bool _ready = false;
  bool get ready => _ready;

  /// [unlocked]: start unlocked this once (the first run, before anything is kept).
  Future<void> init(Settings settings, {bool unlocked = false}) async {
    _settings = settings;
    try {
      method = await api.method();
    } catch (e) {
      debugPrint('lock: $e');
      method = LockMethod.none;
    }
    _locked = active && !startUnlocked && !unlocked;
    _ready = true;
    await _cover();
    notifyListeners();
  }

  /// Look again at what the phone has (a passcode set or removed while away).
  Future<void> recheck() async {
    try {
      final m = await api.method();
      if (m == method) return;
      method = m;
      if (!active) _locked = false;
      await _cover();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _cover() async {
    try {
      await api.cover(active);
    } catch (_) {}
  }

  void lock() {
    if (!active || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Ask the phone. True when unlocked.
  Future<bool> unlock() async {
    if (!_locked) return true;
    if (_asking) return false;
    _asking = true;
    notifyListeners();
    var ok = false;
    try {
      ok = await api.authenticate(Strings.unlockReason);
    } catch (e) {
      debugPrint('lock: $e');
    }
    _asking = false;
    if (ok) _locked = false;
    notifyListeners();
    return ok;
  }

  /// The switch in Settings. Turning it off asks first; turning it on does not.
  Future<bool> setChosen(bool on) async {
    if (on == chosen) return true;
    if (!on && method != LockMethod.none) {
      _asking = true;
      notifyListeners();
      var ok = false;
      try {
        ok = await api.authenticate(Strings.turnOffLockReason);
      } catch (_) {}
      _asking = false;
      if (!ok) {
        notifyListeners();
        return false;
      }
    }
    await _settings?.setLockOn(on);
    if (!active) _locked = false;
    await _cover();
    notifyListeners();
    return true;
  }
}
