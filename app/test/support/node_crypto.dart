import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:upon_thy_head/share/link_crypto.dart';

/// AES-256-GCM on the host, for unit tests only: Node's own (the same as website/scripts/make-vectors.mjs),
/// so the Dart around the cipher is checked against the vectors without the phone. The phones' own
/// (CryptoKit, javax.crypto) are checked against the same vectors in integration_test/link_test.dart.
class NodeLinkCrypto implements LinkCrypto {
  static const _script = r'''
const c = require('crypto');
let s = ''; process.stdin.on('data', d => s += d).on('end', () => {
  const a = JSON.parse(s), key = Buffer.from(a.key, 'base64');
  if (a.op === 'seal') {
    const nonce = Buffer.from(a.nonce, 'base64');
    const e = c.createCipheriv('aes-256-gcm', key, nonce); e.setAAD(Buffer.from([1]));
    const ct = Buffer.concat([e.update(Buffer.from(a.plain, 'base64')), e.final()]);
    process.stdout.write(Buffer.concat([Buffer.from([1]), nonce, ct, e.getAuthTag()]).toString('base64'));
  } else {
    const b = Buffer.from(a.locked, 'base64');
    if (b.length < 29) return process.stdout.write('!');
    try {
      const d = c.createDecipheriv('aes-256-gcm', key, b.subarray(1, 13)); d.setAAD(b.subarray(0, 1));
      d.setAuthTag(b.subarray(b.length - 16));
      process.stdout.write(Buffer.concat([d.update(b.subarray(13, b.length - 16)), d.final()]).toString('base64'));
    } catch (e) { process.stdout.write('!'); }
  }
});''';

  static Future<String> _node(Map<String, String> args) async {
    final p = await Process.start('node', ['-e', _script]);
    p.stdin.write(jsonEncode(args));
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    await p.exitCode;
    return out;
  }

  final _r = Random.secure();

  @override
  Future<Uint8List> random(int count) async => Uint8List.fromList(List.generate(count, (_) => _r.nextInt(256)));

  @override
  Future<Uint8List> seal(Uint8List plain, Uint8List key, Uint8List nonce) async =>
      base64.decode(await _node({'op': 'seal', 'key': base64.encode(key), 'nonce': base64.encode(nonce), 'plain': base64.encode(plain)}));

  @override
  Future<Uint8List?> open(Uint8List locked, Uint8List key) async {
    final out = await _node({'op': 'open', 'key': base64.encode(key), 'locked': base64.encode(locked)});
    return out == '!' ? null : base64.decode(out);
  }
}

/// website/protocol-vectors.json.
Map<String, Object?> protocolVectors() =>
    jsonDecode(File('../website/protocol-vectors.json').readAsStringSync()) as Map<String, Object?>;
