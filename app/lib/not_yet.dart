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
  /// when Begin is pressed, and Android's wording for a refused microphone.
  static bool get android => _a;

  /// Writing the words on the phone (tasks 8 to 10). Recording is real; an Android recording is kept
  /// with its sound and no words, as a draft marked `WordsStatus.later`, and its recording is kept
  /// until words are written from it. The first run's practice is skipped (it shows only the words).
  static bool get words => _a;

  /// The app lock and the recent-apps cover (task 11).
  static bool get lock => _a;

  /// Approximate location (task 12): every blessing uses the Salt Lake Temple meanwhile.
  static bool get location => _a;

  /// Sending a blessing (task 13): the reading page has no share button meanwhile.
  static bool get sharing => _a;

  /// Listening back with the phone locked (task 18). The review page's player works on screen;
  /// leaving the app pauses it.
  static bool get lockedListening => _a;
}
