import '../data/blessing.dart';
import '../share/share.dart';

// What the lock allows on home (home_screen.dart), kept apart so it can be tested on its own.

/// A shortcut waiting to be followed, as far as the lock goes. Record a blessing goes while locked,
/// as the locked New blessing button does (lockedRecording); Open my blessings waits for the unlock.
/// Neither goes while the phone is asking, so nothing opens behind its sheet.
bool shortcutPassesLock(ShortcutPlace place, {required bool locked, required bool asking}) =>
    !asking && (!locked || place == ShortcutPlace.record);

/// Whose a new recording is: the sky showing, or, locked, the person's own until unlocked and said
/// otherwise.
String recordingPerson({required bool locked, required String ring}) => locked ? '' : ring;

/// The lights in the sky while recording: locked, only the new recording's own; nothing of any
/// earlier blessing or family member.
List<Blessing> recordingLights({required bool locked, required List<Blessing> blessings, required Blessing draft}) =>
    locked ? [draft] : [...blessings, draft];
