import 'package:flutter/services.dart';

import 'link_format.dart';

/// Locking and opening a blessing for a link, and keeping each link's stop token: the platform's own
/// cryptography and keychain, on `upon_thy_head/link` (ios/Runner/Link.swift: CryptoKit and the
/// Keychain; android/…/LinkChannel.kt: javax.crypto and the Android Keystore). Nothing here
/// implements a cipher.
///
/// Methods (Dart → native):
///  - `random` {count} → that many bytes from the system's secure generator
///  - `seal` {plain, key, nonce} → the whole locked copy, 0x01 ‖ nonce ‖ ciphertext ‖ tag
///  - `open` {locked, key} → the plaintext, or the error `locked` when it does not authenticate
///  - `secretPut` {name, value}, `secretGet` {name} → value or null, `secretDelete` {name},
///    `secretNames` → every name kept (tests, and clearing stopped links)
abstract class LinkCrypto {
  Future<Uint8List> random(int count);

  /// Lock [plain] under [key] and [nonce]: the locked copy (link_format.dart).
  Future<Uint8List> seal(Uint8List plain, Uint8List key, Uint8List nonce);

  /// Open a locked copy whose frame has been checked ([frameError]): the plaintext, or null when it
  /// does not authenticate.
  Future<Uint8List?> open(Uint8List locked, Uint8List key);
}

/// Where stop tokens are kept: the Keychain on iPhone (this device only, after first unlock, so
/// never in a backup restored elsewhere), the Android Keystore on Android. Never the database.
abstract class SecretStore {
  Future<void> put(String name, String value);
  Future<String?> get(String name);
  Future<void> delete(String name);
  Future<List<String>> names();
}

class NativeLinkCrypto implements LinkCrypto, SecretStore {
  const NativeLinkCrypto();
  static const _channel = MethodChannel('upon_thy_head/link');

  @override
  Future<Uint8List> random(int count) async => (await _channel.invokeMethod<Uint8List>('random', {'count': count}))!;

  @override
  Future<Uint8List> seal(Uint8List plain, Uint8List key, Uint8List nonce) async =>
      (await _channel.invokeMethod<Uint8List>('seal', {'plain': plain, 'key': key, 'nonce': nonce}))!;

  @override
  Future<Uint8List?> open(Uint8List locked, Uint8List key) async {
    try {
      return await _channel.invokeMethod<Uint8List>('open', {'locked': locked, 'key': key});
    } on PlatformException catch (e) {
      if (e.code == 'locked') return null;
      rethrow;
    }
  }

  @override
  Future<void> put(String name, String value) => _channel.invokeMethod<void>('secretPut', {'name': name, 'value': value});

  @override
  Future<String?> get(String name) => _channel.invokeMethod<String>('secretGet', {'name': name});

  @override
  Future<void> delete(String name) => _channel.invokeMethod<void>('secretDelete', {'name': name});

  @override
  Future<List<String>> names() async => [...?await _channel.invokeListMethod<String>('secretNames')];
}

/// Secrets in memory (host tests).
class MemorySecrets implements SecretStore {
  final Map<String, String> kept = {};
  @override
  Future<void> put(String name, String value) async => kept[name] = value;
  @override
  Future<String?> get(String name) async => kept[name];
  @override
  Future<void> delete(String name) async => kept.remove(name);
  @override
  Future<List<String>> names() async => kept.keys.toList();
}

/// Lock [plain] with a new random key and nonce: the locked copy and the key.
Future<({Uint8List locked, Uint8List key})> lockForLink(LinkCrypto crypto, Uint8List plain) async {
  final key = await crypto.random(linkKeyBytes);
  final nonce = await crypto.random(linkNonceBytes);
  if (key.length != linkKeyBytes || nonce.length != linkNonceBytes) throw StateError('the system gave too few random bytes');
  final locked = await crypto.seal(plain, key, nonce);
  return (locked: locked, key: key);
}
