import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which phone this is: iPhone (and iPad) or Android. Everything else (tests on the host, macOS)
/// is neither, and gets the silent stand-ins the widget tests use.
abstract final class Phone {
  static bool get ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  /// The real platform, not [defaultTargetPlatform]: Flutter's widget tests report Android by
  /// default, and must keep the silent stand-ins (tests opt in with [NotYet.debugAndroid]).
  static bool get android => !kIsWeb && Platform.isAndroid;

  /// A phone with a native side answering the app's channels (ios/Runner, android/app).
  static bool get native => ios || android;
}

/// What the Android app cannot do yet. Each is a stand-in that says so plainly and is replaced by
/// its task in docs/android-plan.md ("Stand-ins"); the native side answers the same channels
/// safely meanwhile (android/app/src/main/kotlin/.../MainActivity.kt, `NotYet`). Never true on
/// iPhone.
abstract final class NotYet {
  /// Tests: behave as Android does now, on any platform.
  static bool debugAndroid = false;
  static bool get _a => Phone.android || debugAndroid;

  /// Android's own shape where it differs by design, not by being unfinished: Notifications in the
  /// first run in place of speech recognition (which Android does not have), the microphone asked
  /// when Begin is pressed, Android's wording for a refused microphone, and the Screen lock row,
  /// which has no system question (its Allow proves the lock with one unlock). The app lock, the
  /// recent-apps cover and approximate location are real on Android (tasks 11 and 12).
  static bool get android => _a;

  /// Listening back with the phone locked is built (PlaybackService). Kept so a caller can still
  /// ask; it is no longer a stand-in.
  static bool get lockedListening => false;
}
