import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the screen from dimming and locking while a recording listens.
/// iOS only (UIApplication.isIdleTimerDisabled, see ios/Runner/AppDelegate.swift);
/// a no-op where the channel is not answered.
class KeepAwake {
  KeepAwake._();

  static const _channel = MethodChannel('upon_thy_head/keep_awake');

  /// The last value asked for, for tests.
  static bool on = false;

  /// What the system holds now; null where there is no answer.
  static Future<bool?> get() async {
    try {
      return await _channel.invokeMethod<bool>('get');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> set(bool value) async {
    on = value;
    try {
      await _channel.invokeMethod<void>('set', value);
    } on MissingPluginException {
      // macOS and tests: nothing to keep awake
    } on PlatformException catch (e) {
      debugPrint('keep awake: $e');
    }
  }
}
