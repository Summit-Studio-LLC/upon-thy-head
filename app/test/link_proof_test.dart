// Proof of the app in the link client: a pass is got, kept until it expires, renewed once when the
// service refuses it, and sharing still works when no proof can be had.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/share/link_service.dart';
import 'package:upon_thy_head/share/proof.dart';

class FakeProver implements AppProver {
  FakeProver({this.fields = const {'platform': 'ios', 'keyId': 'K', 'attestation': 'QQ=='}});
  Map<String, String>? fields;
  Duration delay = Duration.zero;
  String? kept;
  final asked = <(String, String?)>[];

  @override
  Future<Map<String, String>?> prove(String challenge, {String? androidProject}) async {
    asked.add((challenge, androidProject));
    await Future<void>.delayed(delay);
    return fields;
  }

  @override
  Future<String?> keptPass() async => kept;

  @override
  Future<void> keepPass(String? pass) async => kept = pass;
}

String passEnding(DateTime t, [String id = 'AAAAAAAAAAAAAAAAAAAAAA']) => 'p1.$id.${t.millisecondsSinceEpoch ~/ 1000}.${'S' * 43}';

void main() {
  late HttpServer server;
  late List<({String path, String pass, Map<String, dynamic>? json})> seen;
  late Future<void> Function(HttpRequest r, String path) answer;
  late int passesGiven;

  Future<void> json(HttpRequest r, int status, Object body) async {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await r.response.close();
  }

  /// The service, as far as these tests need it. [refuse] passes are answered 401 "pass".
  Future<void> service(HttpRequest r, String path, {Set<String> refuse = const {}, bool requireProof = false, String? project}) async {
    if (path == '/api/proof/challenge') return json(r, 200, {'challenge': 'c1.9.CHALLENGE', 'expires': '2026-11-18T10:00:00Z', if (project != null) 'android': {'project': project}});
    if (path == '/api/proof') {
      passesGiven++;
      return json(r, 200, {'pass': passEnding(DateTime.now().add(const Duration(days: 7)), 'P${'$passesGiven'.padLeft(21, '0')}'), 'expires': '2026-11-25T10:00:00Z'});
    }
    final pass = r.headers.value('blessing-pass');
    if (pass != null && refuse.contains(pass)) return json(r, 401, {'error': 'pass'});
    if (pass == null && requireProof) return json(r, 403, {'error': 'proof'});
    return json(r, 201, {'id': 'CRAXHiUsMzpBSE9WXWRrcg', 'expires': '2026-12-16T10:00:00Z', 'stop': 'S' * 43});
  }

  setUp(() async {
    seen = [];
    passesGiven = 0;
    answer = (r, path) => service(r, path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final body = await r.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      final bytes = body.takeBytes();
      Map<String, dynamic>? j;
      if (r.headers.contentType?.mimeType == 'application/json' && bytes.isNotEmpty) j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      seen.add((path: r.uri.path, pass: r.headers.value('blessing-pass') ?? '', json: j));
      await answer(r, r.uri.path);
    });
  });
  tearDown(() => server.close(force: true));

  HttpLinkService http(AppProver? prover, {Duration proofTimeout = const Duration(seconds: 2)}) =>
      HttpLinkService(base: 'http://127.0.0.1:${server.port}', timeout: const Duration(seconds: 5), prover: prover, proofTimeout: proofTimeout);
  final locked = Uint8List(41)..[0] = 1;

  test('with no pass kept, the app proves itself, sends the pass, and keeps it for the next link', () async {
    final prover = FakeProver();
    final s = http(prover);
    expect(await s.create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/proof/challenge', '/api/proof', '/api/b']);
    expect(seen[1].json, {'platform': 'ios', 'keyId': 'K', 'attestation': 'QQ==', 'challenge': 'c1.9.CHALLENGE'});
    expect(seen[2].pass, prover.kept);
    expect(prover.kept, startsWith('p1.'));

    seen.clear();
    expect(await s.create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/b'], reason: 'the kept pass is used again');
    // a new service object (a new launch) finds the pass the native side kept
    seen.clear();
    expect(await http(prover).create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/b']);
    expect(prover.asked, hasLength(1));
  });

  test('an expired pass, or one with under an hour left, is renewed before it is sent', () async {
    final prover = FakeProver()..kept = passEnding(DateTime.now().add(const Duration(minutes: 30)));
    expect(await http(prover).create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/proof/challenge', '/api/proof', '/api/b']);
    expect(seen.last.pass, isNot(passEnding(DateTime.now().add(const Duration(minutes: 30)))));
  });

  test('a pass the service refuses is renewed once and the link asked for again', () async {
    final old = passEnding(DateTime.now().add(const Duration(days: 3)));
    final prover = FakeProver()..kept = old;
    answer = (r, path) => service(r, path, refuse: {old});
    expect(await http(prover).create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/b', '/api/proof/challenge', '/api/proof', '/api/b']);
    expect(seen.last.pass, prover.kept);
    expect(prover.kept, isNot(old));
  });

  test('renewed only once: refused again, it is "could not make a link"', () async {
    final prover = FakeProver()..kept = passEnding(DateTime.now().add(const Duration(days: 3)));
    answer = (r, path) async {
      if (path.startsWith('/api/proof')) return service(r, path);
      return json(r, 401, {'error': 'pass'});
    };
    expect((await http(prover).create(locked) as CreateFailed).trouble, LinkTrouble.unavailable);
    expect(prover.asked, hasLength(1));
    expect(seen.where((e) => e.path == '/api/b'), hasLength(2));
  });

  test('no proof to be had (the simulator): the link is still made, without a pass', () async {
    final prover = FakeProver(fields: null);
    expect(await http(prover).create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/proof/challenge', '/api/b']);
    expect(seen.last.pass, '');
  });

  test('no proof service (an older site): the link is still made', () async {
    answer = (r, path) async {
      if (path.startsWith('/api/proof')) return json(r, 404, {'error': 'not_found'});
      return service(r, path);
    };
    expect(await http(FakeProver()).create(locked), isA<Created>());
  });

  test('a proof that takes too long does not hold up sharing', () async {
    final prover = FakeProver()..delay = const Duration(seconds: 5);
    final watch = Stopwatch()..start();
    expect(await http(prover, proofTimeout: const Duration(milliseconds: 300)).create(locked), isA<Created>());
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(seen.last.pass, '');
  });

  test('when the service requires proof and none could be had: "could not make a link"', () async {
    answer = (r, path) => service(r, path, requireProof: true);
    expect((await http(FakeProver(fields: null)).create(locked) as CreateFailed).trouble, LinkTrouble.unavailable);
  });

  test("Android: the Cloud project the service names is handed to the prover", () async {
    answer = (r, path) => service(r, path, project: '123456789012');
    final prover = FakeProver(fields: {'platform': 'android', 'token': 'T'});
    await http(prover).create(locked);
    expect(prover.asked.single, ('c1.9.CHALLENGE', '123456789012'));
    expect(seen[1].json, {'platform': 'android', 'token': 'T', 'challenge': 'c1.9.CHALLENGE'});
  });

  test('a pass expiry is read from the pass itself', () {
    expect(HttpLinkService.passExpiry('p1.${'A' * 22}.1800000000.${'S' * 43}'), DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true));
    expect(HttpLinkService.passExpiry('nonsense'), isNull);
  });

  test('with no prover (tests, a local site) nothing changes', () async {
    expect(await http(null).create(locked), isA<Created>());
    expect(seen.map((e) => e.path), ['/api/b']);
  });
}
