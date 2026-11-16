import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../lock/lock.dart';
import '../place/where.dart';
import '../record/transcriber.dart';
import '../strings.dart';

/// The first run (design/onboarding/, the owner's rulings of 2026-11-16): the opening, the welcome,
/// one permissions screen, and the rehearsal. Shown once, on the first launch of a fresh install;
/// where it stands is kept in the settings file ([Settings.firstRun]) so a kill resumes it and a
/// reinstall starts it again.
abstract final class FirstRun {
  /// Through the welcome; the permissions screen is next.
  static const permissions = 'permissions';

  /// The permissions are answered; the rehearsal's question is next.
  static const rehearsal = 'rehearsal';

  /// The first launch came from a blessing file ("Read first"): the permissions and the rehearsal
  /// are offered at the next launch.
  static const rest = 'rest';

  /// Through the whole flow. The recording screen never asks a system question after this.
  static const done = 'done';

  /// An install that had blessings before the first run existed: it never sees it, and the
  /// recording screen asks as it always has.
  static const existing = 'existing';
}

/// Where a launch begins.
enum FirstRunStart {
  /// No first run: the sky (and the lock) as always.
  none,

  /// The opening, the welcome, then the permissions.
  opening,

  /// Opened by a blessing file on a fresh install: the short opening, one line, the blessing.
  shared,

  /// Resumed at the permissions screen (killed there, or the rest after a shared first launch).
  permissions,

  /// Resumed at the rehearsal's question.
  rehearsal,
}

/// Where this launch begins, from what the settings file says and what the phone holds.
FirstRunStart firstRunStart(String? saved, {required bool hasBlessings, required bool fileWaiting}) {
  switch (saved) {
    case null:
      if (hasBlessings) return FirstRunStart.none;
      return fileWaiting ? FirstRunStart.shared : FirstRunStart.opening;
    case FirstRun.permissions:
    case FirstRun.rest:
      return FirstRunStart.permissions;
    case FirstRun.rehearsal:
      return FirstRunStart.rehearsal;
    default:
      return FirstRunStart.none;
  }
}

/// The recording screen may put the system's questions only to someone who has not been through
/// the first run (an install from before it, or the rest still to come after a shared launch).
bool recordScreenMayAsk(String? saved) => saved != FirstRun.done;

// ---- the permissions screen ----

/// The four rows, in the order the phone asks.
enum PermissionKind { microphone, speech, location, lock }

enum RowStatus {
  /// Not yet asked.
  waiting,

  /// The system's question is up for this row now.
  asking,

  /// Allowed: a small quiet mark.
  allowed,

  /// Refused: "Off. You can turn it on in Settings."
  off,

  /// Nothing to ask on this phone (no Face ID, or no passcode): the Settings page's plain line.
  info,
}

/// What the phone has for the lock row (ios/Runner/Privacy.swift `biometry`).
class Biometry {
  const Biometry({required this.type, required this.state, required this.passcode});

  /// "faceID", "touchID", "opticID" or "none".
  final String type;

  /// "ok", "denied", "notEnrolled", "noPasscode" or "unavailable".
  final String state;
  final bool passcode;

  static Biometry of(Map<Object?, Object?>? m) => Biometry(
        type: m?['type'] as String? ?? 'none',
        state: m?['state'] as String? ?? 'unavailable',
        passcode: m?['passcode'] as bool? ?? false,
      );

  /// Face ID and Optic ID put a question; Touch ID has none.
  bool get asks => type == 'faceID' || type == 'opticID';
}

/// One row: what it is called, its status, and the line under its name.
class PermissionRow {
  const PermissionRow(this.kind, this.status, {this.name, this.note});
  final PermissionKind kind;
  final RowStatus status;

  /// The lock row is named for what the phone has ("Touch ID"); the others by [kind].
  final String? name;

  /// For [RowStatus.info]: the line shown instead of the reason.
  final String? note;

  String get title => name ?? switch (kind) {
        PermissionKind.microphone => Strings.microphone,
        PermissionKind.speech => Strings.speechRecognition,
        PermissionKind.location => Strings.location,
        PermissionKind.lock => 'Face ID',
      };

  String get reason => switch (kind) {
        PermissionKind.microphone => Strings.microphoneWhy,
        PermissionKind.speech => Strings.speechWhy,
        PermissionKind.location => Strings.locationWhy,
        PermissionKind.lock => Strings.faceIdWhy,
      };

  /// The line under the name now.
  String get line => switch (status) {
        RowStatus.off => kind == PermissionKind.location ? Strings.locationOff : Strings.permissionOff,
        RowStatus.info => note ?? reason,
        _ => reason,
      };

  /// What VoiceOver reads for the row.
  String get semantics => switch (status) {
        RowStatus.asking => '${Strings.rowAsking(title)}. $reason',
        RowStatus.allowed => '${Strings.rowOn(title)}. $reason',
        _ => '$title. $line',
      };

  PermissionRow withStatus(RowStatus s) => PermissionRow(kind, s, name: name, note: note);
}

RowStatus rowOfPermission(Permission p) => switch (p) {
      Permission.granted => RowStatus.allowed,
      Permission.denied => RowStatus.off,
      Permission.undetermined => RowStatus.waiting,
    };

/// [asked]: the first run already put the question. After "Allow Once" iOS reports the question
/// unanswered again at the next launch; that person said yes, and is not asked twice.
RowStatus rowOfLocation(LocationStatus s, {required bool asked}) => switch (s) {
      LocationStatus.granted => RowStatus.allowed,
      LocationStatus.denied || LocationStatus.restricted => RowStatus.off,
      LocationStatus.undetermined => asked ? RowStatus.allowed : RowStatus.waiting,
    };

/// The lock row for what the phone has. [asked]: the first run already put Face ID's question.
PermissionRow lockRow(Biometry b, {required bool asked}) {
  final name = switch (b.type) {
    'touchID' => 'Touch ID',
    'opticID' => 'Optic ID',
    'faceID' => 'Face ID',
    _ => Strings.appLock,
  };
  // no passcode: the app cannot lock at all
  if (!b.passcode || b.state == 'noPasscode') return PermissionRow(PermissionKind.lock, RowStatus.info, name: name, note: Strings.noPasscode);
  if (b.state == 'denied') return PermissionRow(PermissionKind.lock, RowStatus.off, name: name);
  // nothing enrolled, or no biometrics: the passcode opens the app, nothing to ask
  if (b.state != 'ok' || b.type == 'none') {
    return PermissionRow(PermissionKind.lock, RowStatus.info, name: Strings.appLock, note: Strings.lockHint(LockMethod.passcode));
  }
  // Touch ID has no question of its own
  if (!b.asks || asked) return PermissionRow(PermissionKind.lock, RowStatus.allowed, name: name);
  return PermissionRow(PermissionKind.lock, RowStatus.waiting, name: name);
}

/// The phone's questions, one at a time.
abstract class FirstRunAsker {
  Future<Permission> microphone();
  Future<Permission> askMicrophone();
  Future<Permission> speech();
  Future<Permission> askSpeech();
  Future<LocationStatus> location();
  Future<LocationStatus> askLocation();
  Future<Biometry> biometry();
  Future<Biometry> askBiometrics(String reason);
}

/// iOS: SpeechChannel.swift, Privacy.swift.
class NativeFirstRunAsker implements FirstRunAsker {
  NativeFirstRunAsker(this.locator);
  final Locator locator;

  static const _speech = MethodChannel('upon_thy_head/speech');
  static const _lock = MethodChannel('upon_thy_head/lock');

  static Permission _p(Object? s) => switch (s) {
        'granted' => Permission.granted,
        'denied' => Permission.denied,
        _ => Permission.undetermined,
      };

  Future<Map<Object?, Object?>?> _perms(String method) => _speech.invokeMethod<Map<Object?, Object?>>(method);

  @override
  Future<Permission> microphone() async => _p((await _perms('permissions'))?['microphone']);
  @override
  Future<Permission> askMicrophone() async => _p((await _perms('requestMicrophone'))?['microphone']);
  @override
  Future<Permission> speech() async => _p((await _perms('permissions'))?['speech']);
  @override
  Future<Permission> askSpeech() async => _p((await _perms('requestSpeech'))?['speech']);
  @override
  Future<LocationStatus> location() => locator.status();
  @override
  Future<LocationStatus> askLocation() => locator.request();
  @override
  Future<Biometry> biometry() async => Biometry.of(await _lock.invokeMethod<Map<Object?, Object?>>('biometry'));
  @override
  Future<Biometry> askBiometrics(String reason) async =>
      Biometry.of(await _lock.invokeMethod<Map<Object?, Object?>>('askBiometrics', {'reason': reason}));
}

/// The permissions screen's state: the four rows, read as the screen opens; then, on Continue,
/// iOS's own questions one after another, each row lit while its question is up, a short beat
/// between them. A row already decided is shown and not asked again.
class FirstRunPermissions extends ChangeNotifier {
  FirstRunPermissions({required this.asker, required this.settings, this.beat = const Duration(milliseconds: 700), this.announce});

  final FirstRunAsker asker;
  final Settings settings;

  /// The pause after an answer, before the next question.
  final Duration beat;

  /// Read aloud (VoiceOver), after each answer.
  final void Function(String)? announce;

  List<PermissionRow> rows = const [];
  bool get loaded => rows.isNotEmpty;

  /// Continue was pressed and the questions are going.
  bool get running => _running;
  bool _running = false;

  /// The row whose question is up, or null.
  PermissionKind? get asking => _asking;
  PermissionKind? _asking;

  bool get microphoneAllowed => rows.any((r) => r.kind == PermissionKind.microphone && r.status == RowStatus.allowed);

  Future<void> load() async {
    final out = <PermissionRow>[];
    Future<RowStatus> safe(Future<RowStatus> Function() f) async {
      try {
        return await f();
      } catch (e) {
        debugPrint('first run: $e');
        return RowStatus.info;
      }
    }

    out.add(PermissionRow(PermissionKind.microphone, await safe(() async => rowOfPermission(await asker.microphone()))));
    out.add(PermissionRow(PermissionKind.speech, await safe(() async => rowOfPermission(await asker.speech()))));
    out.add(PermissionRow(PermissionKind.location,
        await safe(() async => rowOfLocation(await asker.location(), asked: settings.locationAsked))));
    try {
      out.add(lockRow(await asker.biometry(), asked: settings.faceIdAsked));
    } catch (e) {
      debugPrint('first run: $e');
      out.add(const PermissionRow(PermissionKind.lock, RowStatus.info));
    }
    rows = out;
    notifyListeners();
  }

  void _set(PermissionKind k, RowStatus s) {
    rows = [for (final r in rows) r.kind == k ? r.withStatus(s) : r];
    notifyListeners();
  }

  /// Continue: each row not yet decided is asked, in order. Returns when the last is answered.
  Future<void> run() async {
    if (_running) return;
    if (!loaded) await load();
    _running = true;
    notifyListeners();
    for (final r in [...rows]) {
      if (r.status != RowStatus.waiting) continue;
      _asking = r.kind;
      _set(r.kind, RowStatus.asking);
      var s = RowStatus.off;
      try {
        s = await _ask(r);
      } catch (e) {
        debugPrint('first run: ${r.kind.name}: $e');
      }
      _asking = null;
      _set(r.kind, s);
      announce?.call(rows.firstWhere((x) => x.kind == r.kind).semantics);
      await Future<void>.delayed(beat);
    }
    _running = false;
    notifyListeners();
  }

  Future<RowStatus> _ask(PermissionRow r) async {
    switch (r.kind) {
      case PermissionKind.microphone:
        return rowOfPermission(await asker.askMicrophone());
      case PermissionKind.speech:
        return rowOfPermission(await asker.askSpeech());
      case PermissionKind.location:
        await settings.setLocationAsked();
        final s = await asker.askLocation();
        return s == LocationStatus.undetermined ? RowStatus.off : rowOfLocation(s, asked: true);
      case PermissionKind.lock:
        await settings.setFaceIdAsked();
        final b = await asker.askBiometrics(Strings.faceIdKeepReason);
        final row = lockRow(b, asked: true);
        return row.status == RowStatus.waiting ? RowStatus.allowed : row.status;
    }
  }
}
