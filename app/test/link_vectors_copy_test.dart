// The vectors the phones are tested against (integration_test/protocol_vectors.dart) are exactly the
// website's (website/protocol-vectors.json). If this fails, copy the file's text between the r''' '''.
//
//   flutter test test/link_vectors_copy_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/protocol_vectors.dart';

void main() {
  test('the phones\' copy of the vectors is the website\'s', () {
    expect(protocolVectorsJson, File('../website/protocol-vectors.json').readAsStringSync());
  });
}
