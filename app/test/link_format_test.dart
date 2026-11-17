// A blessing sent by link, against website/protocol-vectors.json: the link's form, the fragment
// refusals, the record inside, and (with Node's AES-256-GCM standing in for the phone's) sealing
// and opening in the contract's order, refusals included.
//
//   flutter test test/link_format_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/share/link_format.dart';
import 'package:upon_thy_head/share/links.dart';
import 'package:upon_thy_head/share/receive.dart';

import 'support/node_crypto.dart';

Uint8List hex(String h) => Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

void main() {
  final v = protocolVectors();
  final vectors = (v['vectors'] as List).cast<Map<String, Object?>>();
  final refusals = (v['refusals'] as List).cast<Map<String, Object?>>();
  final fragments = (v['fragments'] as List).cast<Map<String, Object?>>();
  final records = (v['records'] as List).cast<Map<String, Object?>>();
  final crypto = NodeLinkCrypto();

  test('the format the app builds is the one the vectors are made for', () {
    final f = v['format'] as Map;
    expect(f['version'], linkVersion);
    expect(f['nonceBytes'], linkNonceBytes);
    expect(f['tagBytes'], linkTagBytes);
    expect(f['maxBytes'], linkMaxBytes);
  });

  group('the fragment', () {
    for (final f in fragments) {
      test('refused: "${f['fragment']}" (${f['why'] ?? 'length'})', () => expect(keyOfFragment(f['fragment']! as String), isNull));
    }
    test('a key is read back to its bytes, and written the same way', () {
      for (final x in vectors) {
        final k = x['key']! as Map;
        expect(keyOfFragment(k['base64url']! as String), hex(k['hex']! as String));
        expect(fragmentOfKey(hex(k['hex']! as String)), k['base64url']);
      }
    });
  });

  for (final x in vectors) {
    group('vector "${x['name']}"', () {
      final key = hex((x['key']! as Map)['hex']! as String);
      final nonce = hex((x['nonce']! as Map)['hex']! as String);
      final plain = Uint8List.fromList(utf8.encode((x['plaintext']! as Map)['utf8']! as String));
      final locked = base64.decode((x['locked']! as Map)['base64']! as String);

      test('the record, written as the app writes it, is the plaintext byte for byte', () {
        final r = readBlessingFile(utf8.encode(jsonEncode(x['record'])));
        expect(r, isA<BlessingReadOk>());
        expect((r as BlessingReadOk).record.toCompactBytes(), plain);
      });

      test('the link is built from the id and the key, and read back', () {
        expect(linkOf(x['id']! as String, key, site: 'https://uponthyhead.app'), x['link']);
        final parts = linkPartsOf(x['link']! as String)!;
        expect(parts.id, x['id']);
        expect(keyOfFragment(parts.fragment), key);
        expect(x['link'].toString().length, 92);
      });

      test('sealed: exactly the locked copy', () async {
        expect(await crypto.seal(plain, key, nonce), locked);
      });

      test('opened: the record, as the reading page shows it', () async {
        final (error, record) = await openError(crypto, locked, key);
        expect(error, isNull);
        final shown = x['shown']! as Map;
        final b = record!.toBlessing(place: const Place(0, 0));
        expect(b.title, shown['title']);
        expect(b.words, shown['polished']);
        expect(b.keptChanges, shown['keptChanges']);
        expect(await openLocked(crypto, locked, key, (_) async => null), isA<ArrivalNew>());
      });
    });
  }

  group('refusals, each for its own reason and in the contract\'s order', () {
    for (final r in [...refusals, ...records]) {
      test('${r['name']} → ${r['error']}', () async {
        final key = keyOfFragment(r['key']! as String)!;
        final locked = base64.decode(r['locked']! as String);
        final (error, record) = await openError(crypto, locked, key);
        expect(error?.name, r['error']);
        expect(record, isNull);
      });
    }
  });

  group('links handed to the app', () {
    const id = 'CRAXHiUsMzpBSE9WXWRrcg', key = 'AQgPFh0kKzI5QEdOVVxjanF4f4aNlJuiqbC3vsXM09o';
    test('the site, with or without www, and a trailing slash', () {
      for (final u in ['https://uponthyhead.app/b/$id#$key', 'https://www.uponthyhead.app/b/$id#$key', 'https://uponthyhead.app/b/$id/#$key']) {
        expect(linkPartsOf(u), (id: id, fragment: key), reason: u);
      }
    });
    test('the test scheme only in debug builds', () {
      expect(linkPartsOf('uponthyhead-test://b/$id#$key'), isNull);
      expect(linkPartsOf('uponthyhead-test://b/$id#$key', debug: true), (id: id, fragment: key));
    });
    test('no fragment: the id, and an empty key (the sheet says the link is not complete)', () {
      expect(linkPartsOf('https://uponthyhead.app/b/$id'), (id: id, fragment: ''));
    });
    test('anything else is not a blessing link', () {
      for (final u in [
        'http://uponthyhead.app/b/$id#$key',
        'https://evil.example/b/$id#$key',
        'https://uponthyhead.app/c/$id#$key',
        'https://uponthyhead.app/b/short#$key',
        'https://uponthyhead.app/b/$id/more#$key',
        'not a url at all',
      ]) {
        expect(linkPartsOf(u), isNull, reason: u);
      }
    });
    test('the frame is checked before any cryptography', () {
      expect(frameError(Uint8List(30)..[0] = 1), LinkError.damaged);
      expect(frameError(Uint8List(31)), LinkError.damaged);
      expect(frameError(Uint8List(31)..[0] = 2), LinkError.newer);
      expect(frameError(Uint8List(65537)..[0] = 1), LinkError.damaged);
      expect(frameError(Uint8List(65536)..[0] = 1), isNull);
    });
  });
}
