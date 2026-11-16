import 'dart:convert';
import 'dart:io' show ZLibCodec, ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'blessing_file.dart';
import 'chacha.dart';

/// A whole blessing inside a link, after the `#`, so no server ever holds it (the product brief's
/// design; docs/blessing-file.md, "In a link"). Not offered in the app yet: this is the encoder and
/// the strict decoder, measured.
///
///     https://uponthyhead.app/b#1<base64url(key ‖ sealed)>
///
///  - "1": the link format's version.
///  - The record is the `.blessing` file's (share/blessing_file.dart), as compact JSON, compressed
///    with raw DEFLATE (RFC 1951) at the highest level.
///  - Then sealed with ChaCha20-Poly1305 (RFC 8439) under a random 256-bit key used for this one
///    link only, so the nonce is twelve zero bytes. The key travels in the same fragment.
///  - base64url without padding (RFC 4648 §5): letters, digits, "-" and "_" only.
///
/// What the encryption does and does not do: a browser never sends the part after `#` to a server,
/// so a server log, a proxy, or a filter that only records the address it was asked for sees no
/// words. Anything that holds the whole link (the Messages thread, a mail archive, a chat app's
/// link preview, a screenshot of a QR code, a browser's history) holds the key with it and can read
/// the blessing. The tag also makes a link that was cut short or changed fail cleanly instead of
/// showing half a blessing.

/// Where the App Clip will live. The domain is not registered yet; the length is what matters here.
const linkBase = 'https://uponthyhead.app/b';

/// The link format's version (the first character after `#`).
const linkVersion = '1';

/// The longest fragment read at all, in characters.
const linkMaxFragment = 256 * 1024;

final _zero = Uint8List(ChaChaPoly.nonceLength);

/// The link for [record], under a fresh random key (or [key], for tests).
String blessingLink(BlessingRecord record, {List<int>? key, String base = linkBase}) =>
    '$base#${blessingFragment(record, key: key)}';

/// The part after `#`.
String blessingFragment(BlessingRecord record, {List<int>? key}) {
  final k = key ?? _randomKey();
  final packed = ZLibCodec(raw: true, level: 9, memLevel: 9, windowBits: 15).encode(record.toCompactBytes());
  final sealed = ChaChaPoly.seal(k, _zero, packed);
  final all = Uint8List(k.length + sealed.length)
    ..setAll(0, k)
    ..setAll(k.length, sealed);
  return '$linkVersion${base64UrlEncode(all).replaceAll('=', '')}';
}

Uint8List _randomKey() {
  final r = math.Random.secure();
  return Uint8List.fromList(List.generate(ChaChaPoly.keyLength, (_) => r.nextInt(256)));
}

final _b64url = RegExp(r'^[A-Za-z0-9_-]*$');

/// Read a link, or just its fragment (with or without the `#`), as strictly as a file.
BlessingRead readBlessingLink(String link) {
  final hash = link.indexOf('#');
  final f = hash >= 0 ? link.substring(hash + 1) : link;
  if (f.isEmpty) return const BlessingReadBad('no fragment');
  if (f.length > linkMaxFragment) return const BlessingReadBad('fragment too long');
  final v = f[0];
  if (v != linkVersion) {
    // a later link format is a newer app's; anything else is not a link of ours
    final n = int.tryParse(v);
    return n != null && n > 1 ? BlessingReadNewer(n) : const BlessingReadBad('link version');
  }
  final body = f.substring(1);
  if (!_b64url.hasMatch(body) || body.length % 4 == 1) return const BlessingReadBad('not base64url');
  final Uint8List all;
  try {
    all = base64Url.decode(body.padRight((body.length + 3) ~/ 4 * 4, '='));
  } on FormatException {
    return const BlessingReadBad('not base64url');
  }
  if (all.length < ChaChaPoly.keyLength + ChaChaPoly.tagLength + 1) return const BlessingReadBad('too short');
  final key = all.sublist(0, ChaChaPoly.keyLength);
  final packed = ChaChaPoly.open(key, _zero, all.sublist(ChaChaPoly.keyLength));
  if (packed == null) return const BlessingReadBad('does not open (cut short or changed)');
  final Uint8List json;
  try {
    json = _inflate(packed, blessingFileMaxBytes);
  } on _TooBig {
    return const BlessingReadBad('unpacks past the limit');
  } catch (_) {
    return const BlessingReadBad('does not unpack');
  }
  return readBlessingFile(json);
}

class _TooBig implements Exception {}

/// Raw DEFLATE, refusing to make more than [max] bytes (so a small link cannot unpack to a huge one).
Uint8List _inflate(Uint8List packed, int max) {
  final out = BytesBuilder(copy: false);
  final sink = ByteConversionSink.withCallback((_) {});
  final counting = _Counting(out, max, sink);
  final d = ZLibDecoder(raw: true).startChunkedConversion(counting);
  for (var at = 0; at < packed.length; at += 4096) {
    d.add(packed.sublist(at, math.min(packed.length, at + 4096)));
  }
  d.close();
  return out.toBytes();
}

class _Counting implements Sink<List<int>> {
  _Counting(this.out, this.max, this.inner);
  final BytesBuilder out;
  final int max;
  final ByteConversionSink inner;
  @override
  void add(List<int> data) {
    if (out.length + data.length > max) throw _TooBig();
    out.add(data);
  }

  @override
  void close() => inner.close();
}
