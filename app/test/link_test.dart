import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/chacha.dart';
import 'package:upon_thy_head/share/link.dart';

Uint8List hex(String s) {
  final t = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  return Uint8List.fromList([for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16)]);
}

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

const sunscreen = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";

void main() {
  group('ChaCha20-Poly1305 against RFC 8439', () {
    test('2.3.2: the block function', () {
      final key = hex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
      final out = ChaChaPoly.block(key, hex('000000090000004a00000000'), 1);
      expect(toHex(out), '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e'
          'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e');
    });

    test('2.5.2: Poly1305', () {
      final key = hex('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b');
      expect(toHex(ChaChaPoly.poly1305(key, utf8.encode('Cryptographic Forum Research Group'))), 'a8061dc1305136c6c22b8baf0c0127a9');
    });

    test('2.8.2: the AEAD', () {
      final key = hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
      final nonce = hex('070000004041424344454647');
      final aad = hex('50515253c0c1c2c3c4c5c6c7');
      final sealed = ChaChaPoly.seal(key, nonce, utf8.encode(sunscreen), aad: aad);
      expect(toHex(sealed.sublist(0, 16)), 'd31a8d34648e60db7b86afbc53ef7ec2');
      expect(toHex(sealed.sublist(sealed.length - 16)), '1ae10b594f09e26a7e902ecbd0600691');
      expect(utf8.decode(ChaChaPoly.open(key, nonce, sealed, aad: aad)!), sunscreen);
      // one bit changed anywhere: refused
      final changed = Uint8List.fromList(sealed)..[5] ^= 1;
      expect(ChaChaPoly.open(key, nonce, changed, aad: aad), isNull);
    });
  });

  group('the link', () {
    final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    final rec = BlessingRecord.of(surgery);
    final key = List<int>.generate(32, (i) => i * 7 % 256);

    test('round trip: the same record comes back', () {
      final link = blessingLink(rec);
      expect(link, startsWith('https://uponthyhead.app/b#1'));
      final r = readBlessingLink(link);
      expect(r, isA<BlessingReadOk>());
      expect((r as BlessingReadOk).record.sameAs(surgery), isTrue);
    });

    test('web-safe characters only, no padding', () {
      final f = blessingFragment(rec);
      expect(RegExp(r'^1[A-Za-z0-9_-]+$').hasMatch(f), isTrue, reason: f);
    });

    test('a fresh key every time: the same blessing never makes the same link', () {
      expect(blessingFragment(rec), isNot(blessingFragment(rec)));
      expect(blessingFragment(rec, key: key), blessingFragment(rec, key: key));
    });

    test('the words are not readable in the link', () {
      final f = blessingFragment(rec, key: key);
      final bytes = base64Url.decode(f.substring(1).padRight((f.length - 1 + 3) ~/ 4 * 4, '='));
      expect(latin1.decode(bytes, allowInvalid: true).contains('Emma'), isFalse);
    });

    test('cut short, changed, wrong version, rubbish: refused', () {
      final f = blessingFragment(rec, key: key);
      expect(readBlessingLink(f.substring(0, f.length - 3)), isA<BlessingReadBad>());
      final flipped = '${f.substring(0, 60)}${f[60] == 'A' ? 'B' : 'A'}${f.substring(61)}';
      expect(readBlessingLink(flipped), isA<BlessingReadBad>());
      expect(readBlessingLink('2${f.substring(1)}'), isA<BlessingReadNewer>());
      expect(readBlessingLink('x${f.substring(1)}'), isA<BlessingReadBad>());
      expect(readBlessingLink('https://uponthyhead.app/b'), isA<BlessingReadBad>());
      expect(readBlessingLink('1hello world'), isA<BlessingReadBad>());
      expect(readBlessingLink('1${'A' * 10}'), isA<BlessingReadBad>());
    });

    test('a link that would unpack past the size limit is refused', () {
      // a valid record padded with a megabyte of one letter compresses to almost nothing
      final json = utf8.encode(jsonEncode({...rec.toJson(), 'padding': 'x' * (1024 * 1024)}));
      final packed = ZLibCodec(raw: true, level: 9).encode(json);
      final sealed = ChaChaPoly.seal(key, Uint8List(12), packed);
      final f = '1${base64UrlEncode([...key, ...sealed]).replaceAll('=', '')}';
      expect(f.length, lessThan(3000));
      final r = readBlessingLink(f);
      expect(r, isA<BlessingReadBad>());
      expect((r as BlessingReadBad).why, contains('limit'));
    });

    test('decoding is as strict as a file: a bad field inside is refused', () {
      final json = utf8.encode(jsonEncode({...rec.toJson(), 'id': 'has spaces'}));
      final packed = ZLibCodec(raw: true, level: 9).encode(json);
      final f = '1${base64UrlEncode([...key, ...ChaChaPoly.seal(key, Uint8List(12), packed)]).replaceAll('=', '')}';
      expect(readBlessingLink(f), isA<BlessingReadBad>());
    });

    test('accents and emoji survive', () {
      final b = Blessing(id: 'e1', title: 'Para Lucía 🙏', from: 'Abuelo', utc: DateTime.utc(2025, 1, 1), utcOffset: Duration.zero, place: samplePlace, rawText: 'Bendición, corazón — ¡amén! 🌟', draft: false);
      final r = readBlessingLink(blessingLink(BlessingRecord.of(b))) as BlessingReadOk;
      expect(r.record.spoken, 'Bendición, corazón — ¡amén! 🌟');
      expect(r.record.title, 'Para Lucía 🙏');
    });
  });
}
