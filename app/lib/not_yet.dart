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

  /// Recording, and writing the words (tasks 4 to 10): Begin stays dimmed with a plain line.
  static bool get recording => _a;

  /// The app lock and the recent-apps cover (task 11).
  static bool get lock => _a;

  /// Approximate location (task 12): every blessing uses the Salt Lake Temple meanwhile.
  static bool get location => _a;

  /// Sending a blessing (task 13): the reading page has no share button meanwhile.
  static bool get sharing => _a;

  /// Listening back on the review page (task 18 and the plain player before it).
  static bool get playback => _a;
}
