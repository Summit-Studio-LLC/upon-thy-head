// The phone's own cryptography and keychain for links (ios/Runner/Link.swift: CryptoKit and the
// Keychain; android/…/LinkChannel.kt: javax.crypto and the Android Keystore), on
// `upon_thy_head/link`, against every vector in website/protocol-vectors.json, refusals included.
//
//   flutter test integration_test/link_test.dart -d <simulator or emulator>

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/share/link_crypto.dart';
import 'package:upon_thy_head/share/link_format.dart';
import 'package:upon_thy_head/share/links.dart';

import 'protocol_vectors.dart';

Uint8List hex(String h) => Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = NativeLinkCrypto();
  final v = jsonDecode(protocolVectorsJson) as Map<String, Object?>;

  testWidgets('every vector seals to its locked copy and opens to its plaintext', (tester) async {
    for (final x in (v['vectors']! as List).cast<Map<String, Object?>>()) {
      final key = hex((x['key']! as Map)['hex']! as String), nonce = hex((x['nonce']! as Map)['hex']! as String);
      final plain = Uint8List.fromList(utf8.encode((x['plaintext']! as Map)['utf8']! as String));
      final locked = base64.decode((x['locked']! as Map)['base64']! as String);
      expect(await native.seal(plain, key, nonce), locked, reason: '${x['name']} sealed');
      expect(await native.open(locked, key), plain, reason: '${x['name']} opened');
      final (error, record) = await openError(native, locked, key);
      expect((error, record?.title), (null, (x['shown']! as Map)['title']), reason: '${x['name']} read');
      debugPrint('link vectors: ${x['name']} ok');
    }
  });

  testWidgets('every refusal, for its own reason, in the contract\'s order', (tester) async {
    final all = [...(v['refusals']! as List), ...(v['records']! as List)].cast<Map<String, Object?>>();
    for (final r in all) {
      final key = keyOfFragment(r['key']! as String)!;
      final (error, _) = await openError(native, base64.decode(r['locked']! as String), key);
      expect(error?.name, r['error'], reason: r['name'] as String);
    }
    for (final f in (v['fragments']! as List).cast<Map<String, Object?>>()) {
      expect(keyOfFragment(f['fragment']! as String), isNull);
    }
    debugPrint('link vectors: ${all.length} refusals ok');
  });

  testWidgets('a new key and nonce each time, from the system', (tester) async {
    final a = await native.random(32), b = await native.random(32);
    expect((a.length, b.length), (32, 32));
    expect(a, isNot(b));
    final plain = Uint8List.fromList(utf8.encode('{"a":1}'));
    final (:locked, :key) = await lockForLink(native, plain);
    expect(locked[0], 1);
    expect(locked.length, 1 + 12 + plain.length + 16);
    expect(await native.open(locked, key), plain);
  });

  testWidgets('stop tokens: kept, read back, listed and removed', (tester) async {
    for (final n in await native.names()) {
      if (n.startsWith('test.')) await native.delete(n);
    }
    await native.put('test.one', 'S' * 43);
    await native.put('test.two', 'T' * 43);
    await native.put('test.one', 'U' * 43);
    expect(await native.get('test.one'), 'U' * 43);
    expect((await native.names()).where((n) => n.startsWith('test.')).toList()..sort(), ['test.one', 'test.two']);
    await native.delete('test.one');
    await native.delete('test.two');
    expect(await native.get('test.one'), isNull);
    expect((await native.names()).where((n) => n.startsWith('test.')), isEmpty);
    debugPrint('link secrets: ok');
  });
}
