import 'dart:async';

import 'package:flutter/services.dart';

/// Proof that a request to make a link comes from this app (website/PROTOCOL.md §4, "Proof of the
/// app"): Apple's App Attest on iPhone and iPad, Google's Play Integrity on Android, on
/// `upon_thy_head/proof` (ios/Runner/Proof.swift, android …/ProofChannel.kt). The native side also
/// keeps the pass the service gives for a proof (Keychain on iOS, the app's private preferences on
/// Android), so a pass outlives a launch. Nothing here is logged: no challenge, key, token or pass.
abstract class AppProver {
  /// A proof for [challenge], as the JSON fields the service's POST /api/proof takes besides the
  /// challenge (`platform` and `keyId` + `attestation`, or `platform` and `token`), or null where
  /// none can be had: the simulator, an Android build with no Cloud project to ask with
  /// ([androidProject] null), or Apple or Google refusing.
  Future<Map<String, String>?> prove(String challenge, {String? androidProject});

  /// The pass kept from the last proof, or null.
  Future<String?> keptPass();

  /// Keep [pass] (null forgets it).
  Future<void> keepPass(String? pass);
}

class NativeAppProver implements AppProver {
  const NativeAppProver();
  static const _channel = MethodChannel('upon_thy_head/proof');

  @override
  Future<Map<String, String>?> prove(String challenge, {String? androidProject}) async {
    try {
      final r = await _channel.invokeMapMethod<String, String>('prove', {'challenge': challenge, 'project': androidProject});
      return r == null || r.isEmpty ? null : r;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> keptPass() async {
    try {
      return await _channel.invokeMethod<String>('passGet');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> keepPass(String? pass) async {
    try {
      await _channel.invokeMethod<void>('passPut', {'value': pass});
    } on PlatformException {
      // a pass not kept is only proven again next time
    } on MissingPluginException {
      // the same
    }
  }
}
