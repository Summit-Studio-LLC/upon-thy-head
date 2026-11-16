import 'dart:typed_data';

/// ChaCha20-Poly1305 (RFC 8439), the AEAD Apple's CryptoKit offers as `ChaChaPoly`, so an App Clip
/// can open what this seals with no code of its own. Pure Dart, checked against the RFC's test
/// vectors (test/link_test.dart). Used only by share/link.dart.
class ChaChaPoly {
  const ChaChaPoly._();

  static const keyLength = 32, nonceLength = 12, tagLength = 16;

  /// [plain] sealed under [key] and [nonce]: the ciphertext followed by the 16-byte tag.
  static Uint8List seal(List<int> key, List<int> nonce, List<int> plain, {List<int> aad = const []}) {
    _check(key, nonce);
    final cipher = _xor(key, nonce, 1, plain);
    final tag = _tag(key, nonce, aad, cipher);
    return Uint8List(cipher.length + tagLength)
      ..setAll(0, cipher)
      ..setAll(cipher.length, tag);
  }

  /// The plain text, or null when [sealed] was not made with this key and nonce (or was changed).
  static Uint8List? open(List<int> key, List<int> nonce, List<int> sealed, {List<int> aad = const []}) {
    _check(key, nonce);
    if (sealed.length < tagLength) return null;
    final cipher = Uint8List.fromList(sealed.sublist(0, sealed.length - tagLength));
    final tag = sealed.sublist(sealed.length - tagLength);
    final want = _tag(key, nonce, aad, cipher);
    var diff = 0;
    for (var i = 0; i < tagLength; i++) {
      diff |= want[i] ^ tag[i];
    }
    if (diff != 0) return null;
    return _xor(key, nonce, 1, cipher);
  }

  static void _check(List<int> key, List<int> nonce) {
    if (key.length != keyLength) throw ArgumentError('key must be 32 bytes');
    if (nonce.length != nonceLength) throw ArgumentError('nonce must be 12 bytes');
  }

  // ---- ChaCha20 ----

  static int _rotl(int v, int n) => ((v << n) | (v >> (32 - n))) & 0xffffffff;

  static void _quarter(Uint32List s, int a, int b, int c, int d) {
    s[a] = s[a] + s[b];
    s[d] = _rotl(s[d] ^ s[a], 16);
    s[c] = s[c] + s[d];
    s[b] = _rotl(s[b] ^ s[c], 12);
    s[a] = s[a] + s[b];
    s[d] = _rotl(s[d] ^ s[a], 8);
    s[c] = s[c] + s[d];
    s[b] = _rotl(s[b] ^ s[c], 7);
  }

  static int _le32(List<int> b, int i) => b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24;

  /// One 64-byte block of key stream.
  static Uint8List block(List<int> key, List<int> nonce, int counter) {
    final init = Uint32List(16)
      ..[0] = 0x61707865
      ..[1] = 0x3320646e
      ..[2] = 0x79622d32
      ..[3] = 0x6b206574;
    for (var i = 0; i < 8; i++) {
      init[4 + i] = _le32(key, i * 4);
    }
    init[12] = counter & 0xffffffff;
    for (var i = 0; i < 3; i++) {
      init[13 + i] = _le32(nonce, i * 4);
    }
    final s = Uint32List.fromList(init);
    for (var i = 0; i < 10; i++) {
      _quarter(s, 0, 4, 8, 12);
      _quarter(s, 1, 5, 9, 13);
      _quarter(s, 2, 6, 10, 14);
      _quarter(s, 3, 7, 11, 15);
      _quarter(s, 0, 5, 10, 15);
      _quarter(s, 1, 6, 11, 12);
      _quarter(s, 2, 7, 8, 13);
      _quarter(s, 3, 4, 9, 14);
    }
    final out = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      final v = (s[i] + init[i]) & 0xffffffff;
      out[i * 4] = v & 0xff;
      out[i * 4 + 1] = (v >> 8) & 0xff;
      out[i * 4 + 2] = (v >> 16) & 0xff;
      out[i * 4 + 3] = (v >> 24) & 0xff;
    }
    return out;
  }

  static Uint8List _xor(List<int> key, List<int> nonce, int counter, List<int> data) {
    final out = Uint8List(data.length);
    for (var at = 0, n = counter; at < data.length; at += 64, n++) {
      final ks = block(key, nonce, n);
      final end = data.length - at < 64 ? data.length - at : 64;
      for (var i = 0; i < end; i++) {
        out[at + i] = data[at + i] ^ ks[i];
      }
    }
    return out;
  }

  // ---- Poly1305 ----

  static final _p = (BigInt.one << 130) - BigInt.from(5);
  static final _mask128 = (BigInt.one << 128) - BigInt.one;

  static BigInt _leNum(List<int> b) {
    var n = BigInt.zero;
    for (var i = b.length - 1; i >= 0; i--) {
      n = (n << 8) | BigInt.from(b[i]);
    }
    return n;
  }

  /// The one-time authenticator of [msg] under the 32-byte [oneTimeKey].
  static Uint8List poly1305(List<int> oneTimeKey, List<int> msg) {
    final rBytes = Uint8List.fromList(oneTimeKey.sublist(0, 16));
    // clamp r
    for (final i in [3, 7, 11, 15]) {
      rBytes[i] &= 15;
    }
    for (final i in [4, 8, 12]) {
      rBytes[i] &= 252;
    }
    final r = _leNum(rBytes), s = _leNum(oneTimeKey.sublist(16, 32));
    var acc = BigInt.zero;
    for (var at = 0; at < msg.length; at += 16) {
      final end = msg.length - at < 16 ? msg.length : at + 16;
      final chunk = [...msg.sublist(at, end), 1];
      acc = ((acc + _leNum(chunk)) * r) % _p;
    }
    acc = (acc + s) & _mask128;
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = ((acc >> (8 * i)) & BigInt.from(0xff)).toInt();
    }
    return out;
  }

  static Uint8List _tag(List<int> key, List<int> nonce, List<int> aad, List<int> cipher) {
    final otk = block(key, nonce, 0).sublist(0, 32);
    int pad(int n) => (16 - n % 16) % 16;
    final mac = BytesBuilder(copy: false)
      ..add(aad)
      ..add(Uint8List(pad(aad.length)))
      ..add(cipher)
      ..add(Uint8List(pad(cipher.length)));
    final lens = ByteData(16)
      ..setUint64(0, aad.length, Endian.little)
      ..setUint64(8, cipher.length, Endian.little);
    mac.add(lens.buffer.asUint8List());
    return poly1305(otk, mac.toBytes());
  }
}
