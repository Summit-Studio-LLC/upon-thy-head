// Sending by link, on the host: making a link (only the locked copy leaves; the stop token kept with
// the secrets, never the key), "Your links" and its states, stopping, deleting, opening a link into
// each arrival, ownership in the store, and the service's answers over real HTTP.
//
//   flutter test test/links_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/sent_link.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart' show countLine;
import 'package:upon_thy_head/share/link_crypto.dart';
import 'package:upon_thy_head/share/link_format.dart';
import 'package:upon_thy_head/share/link_service.dart';
import 'package:upon_thy_head/share/links.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/place/where.dart';

import 'support/node_crypto.dart';

/// The service in memory, keeping what it was sent.
class FakeService implements LinkService {
  final Map<String, Uint8List> copies = {};
  final Map<String, String> tokens = {};
  final List<Uint8List> sent = [];
  LinkTrouble? createTrouble, readTrouble;
  StopResult? stopAnswer;
  var _n = 0;

  @override
  Future<CreateResult> create(Uint8List locked) async {
    sent.add(locked);
    if (createTrouble != null) return CreateFailed(createTrouble!);
    final id = 'L${(_n++).toString().padLeft(21, '0')}';
    copies[id] = locked;
    tokens[id] = 'T' * 42 + '$_n'.substring(0, 1);
    return Created(id: id, expires: DateTime.utc(2026, 12, 16, 10), stop: tokens[id]!);
  }

  @override
  Future<ReadResult> read(String id) async {
    if (readTrouble != null) return ReadFailed(readTrouble!);
    final c = copies[id];
    return c == null ? const ReadGone() : ReadCopy(c);
  }

  @override
  Future<StopResult> stop(String id, String stopToken) async {
    if (stopAnswer != null) return stopAnswer!;
    if (tokens[id] != stopToken) return StopResult.failed;
    copies.remove(id);
    return StopResult.stopped;
  }
}

void main() {
  late Directory dir;
  late SqliteBlessingStore store;
  late FakeService service;
  late MemorySecrets secrets;
  late DateTime now;
  late Links links;
  final crypto = NodeLinkCrypto();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('links');
    store = SqliteBlessingStore.open('${dir.path}/blessings.sqlite');
    service = FakeService();
    secrets = MemorySecrets();
    now = DateTime.utc(2026, 11, 16, 10);
    links = Links(store: store, crypto: crypto, secrets: secrets, service: service, now: () => now);
  });
  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  Blessing surgery() => sampleBlessings().firstWhere((b) => b.id == 'surgery')..draft = false;

  group('making a link', () {
    test('only the locked copy is sent; the link holds the key; the token is kept as a secret, never the key', () async {
      final b = surgery();
      await store.create(b);
      final r = await links.make(b) as Made;
      expect(r.url.length, linkService.length + 3 + 22 + 1 + 43);
      final parts = linkPartsOf(r.url)!;
      final key = keyOfFragment(parts.fragment)!;
      // what left: the frame, never the key or the words
      final sent = service.sent.single;
      expect(sent[0], 1);
      expect(frameError(sent), isNull);
      expect(_contains(sent, key), isFalse);
      expect(_contains(sent, utf8.encode('Comfort before surgery')), isFalse);
      // it opens with the key, to the same record
      final (error, record) = await openError(crypto, sent, key);
      expect(error, isNull);
      expect(record!.sameAs(b), isTrue);
      // kept: the token in the secrets; the link (no key) in the store
      expect(await secrets.names(), ['link.${parts.id}']);
      expect(await secrets.get('link.${parts.id}'), service.tokens[parts.id]);
      expect(secrets.kept.values.any((v) => v.contains(parts.fragment)), isFalse);
      final kept = (await store.links()).single;
      expect((kept.id, kept.blessingId, kept.title, kept.sent, kept.stopped), (parts.id, b.id, b.title, now, null));
      expect(await File('${dir.path}/blessings.sqlite').readAsString(encoding: latin1), isNot(contains(parts.fragment)));
    });

    test('each link has its own key and nonce', () async {
      final b = surgery();
      final a = await links.make(b) as Made, c = await links.make(b) as Made;
      expect(linkPartsOf(a.url)!.fragment, isNot(linkPartsOf(c.url)!.fragment));
      expect(service.sent[0].sublist(1, 13), isNot(service.sent[1].sublist(1, 13)));
    });

    test('no internet: nothing kept, and the reason', () async {
      service.createTrouble = LinkTrouble.offline;
      final r = await links.make(surgery());
      expect((r as NotMade).trouble, LinkTrouble.offline);
      expect(await store.links(), isEmpty);
      expect(await secrets.names(), isEmpty);
    });

    test('too long for a link: refused before anything is sent', () async {
      final b = surgery()..rawText = 'word ' * 14000;
      b.changes.clear();
      expect((await links.make(b) as NotMade).trouble, LinkTrouble.tooBig);
      expect(service.sent, isEmpty);
    });
  });

  group('your links', () {
    SentLink link(String id, {required DateTime sent, DateTime? stopped}) =>
        SentLink(id: id.padRight(22, 'x'), blessingId: 'b', title: id, sent: sent, expires: sent.add(const Duration(days: 30)), stopped: stopped);

    test('newest first, each in its state', () async {
      await store.addLink(link('old', sent: now.subtract(const Duration(days: 31))));
      await store.addLink(link('stopped', sent: now.subtract(const Duration(days: 3)), stopped: now.subtract(const Duration(days: 1))));
      await store.addLink(link('live', sent: now.subtract(const Duration(days: 1))));
      final l = await links.list();
      expect(l.map((x) => x.title), ['live', 'stopped', 'old']);
      expect(l.map((x) => x.stateAt(now)), [LinkState.live, LinkState.stopped, LinkState.expired]);
    });

    test('an ended link loses its token at once and is cleared 30 days after it ended', () async {
      final gone = link('gone', sent: now.subtract(const Duration(days: 61)));
      final stays = link('stays', sent: now.subtract(const Duration(days: 59)));
      for (final l in [gone, stays]) {
        await store.addLink(l);
        await secrets.put('link.${l.id}', 'token');
      }
      final l = await links.list();
      expect(l.map((x) => x.title), ['stays']);
      expect(await secrets.names(), isEmpty);
      expect((await store.links()).map((x) => x.title), ['stays']);
    });

    test('stop: at the service, then here, and the token goes', () async {
      final made = await links.make(surgery()) as Made;
      expect(await links.stop(made.link), StopResult.stopped);
      final l = (await store.links()).single;
      expect(l.stateAt(now), LinkState.stopped);
      expect(l.stopped, now);
      expect(await secrets.names(), isEmpty);
      expect(service.copies, isEmpty);
    });

    test('stop with no internet: nothing changes, and it still works', () async {
      final made = await links.make(surgery()) as Made;
      service.stopAnswer = StopResult.offline;
      expect(await links.stop(made.link), StopResult.offline);
      expect((await store.links()).single.stateAt(now), LinkState.live);
      expect(await secrets.names(), hasLength(1));
    });

    test('no token (a cleared Keychain): it cannot be stopped, and says so', () async {
      final made = await links.make(surgery()) as Made;
      secrets.kept.clear();
      expect(await links.stop(made.link), StopResult.failed);
    });

    test('deleting a blessing: every live link of it is stopped; the worst outcome is told', () async {
      final b = surgery();
      await links.make(b);
      await links.make(b);
      expect(await links.liveOf(b.id), hasLength(2));
      service.stopAnswer = StopResult.offline;
      expect(await links.stopAllOf(b.id), StopResult.offline);
      expect(await links.liveOf(b.id), hasLength(2));
      service.stopAnswer = null;
      expect(await links.stopAllOf(b.id), StopResult.stopped);
      expect(await links.liveOf(b.id), isEmpty);
    });
  });

  group('opening a link', () {
    test('new, the same, or different from the one kept here', () async {
      final b = surgery();
      final made = await links.make(b) as Made;
      final parts = linkPartsOf(made.url)!;
      expect(await links.open(parts), isA<ArrivalNew>());
      await store.create(surgery());
      expect(await links.open(parts), isA<ArrivalSame>());
      final mine = (await store.get(b.id))!..title = 'Changed here';
      await store.update(mine);
      expect(await links.open(parts), isA<ArrivalDifferent>());
    });

    test('the received blessing carries its place', () async {
      final b = surgery();
      final made = await links.make(b) as Made;
      final a = await links.open(linkPartsOf(made.url)!) as ArrivalNew;
      final kept = a.record.toBlessing(place: const Place(0, 0));
      final want = roughly(b.place.lat, b.place.lon);
      expect((kept.place.lat, kept.place.lon), (want.lat, want.lon));
      expect((kept.place.lat, kept.place.lon), isNot((0.0, 0.0)));
    });

    test('stopped or expired, no internet, busy, no key, the wrong key', () async {
      final made = await links.make(surgery()) as Made;
      final parts = linkPartsOf(made.url)!;
      service.readTrouble = LinkTrouble.offline;
      expect(await links.open(parts), isA<ArrivalOnItsWay>());
      service.readTrouble = LinkTrouble.slowDown;
      expect(await links.open(parts), isA<ArrivalNotNow>());
      service.readTrouble = null;
      expect(await links.open((id: parts.id, fragment: '')), isA<ArrivalNoKey>());
      expect(await links.open((id: parts.id, fragment: parts.fragment.substring(1))), isA<ArrivalNoKey>());
      final wrong = (id: parts.id, fragment: 'AgkQFx4lLDM6QUhPVl1ka3J5gIeOlZyjqrG4v8bN1Ns');
      expect((await links.open(wrong) as ArrivalUnreadable).why, 'link: locked');
      await links.stop(made.link);
      expect(await links.open(parts), isA<ArrivalStopped>());
    });
  });

  group('ownership', () {
    Blessing make(String id, Ownership o, {bool draft = false}) => Blessing(
          id: id,
          title: id,
          from: '',
          utc: DateTime.utc(2026, 3, int.parse(id.substring(1))),
          utcOffset: Duration.zero,
          place: samplePlace,
          ownership: o,
          draft: draft,
        );

    test('only "for me" is in the sky and the count; those passed along are listed apart', () async {
      await store.create(make('a1', Ownership.forMe));
      await store.create(make('a2', Ownership.passingOn));
      await store.create(make('a3', Ownership.passingOn, draft: true));
      final mine = await store.list(ownership: Ownership.forMe), along = await store.list(ownership: Ownership.passingOn);
      expect(mine.map((b) => b.id), ['a1']);
      expect(along.map((b) => b.id), ['a2', 'a3']);
      expect(countLine(mine), countLine([make('a1', Ownership.forMe)]));
    });

    test('moved either way at any time, and when it was sent is kept', () async {
      final b = make('a4', Ownership.forMe);
      await store.create(b);
      b
        ..ownership = Ownership.passingOn
        ..sent = DateTime.utc(2026, 11, 16, 9, 30);
      await store.update(b);
      var back = (await store.get('a4'))!;
      expect((back.ownership, back.sent), (Ownership.passingOn, DateTime.utc(2026, 11, 16, 9, 30)));
      back.ownership = Ownership.forMe;
      await store.update(back);
      back = (await store.get('a4'))!;
      expect(back.ownership, Ownership.forMe);
    });

    test('the link sent of a blessing passed along is not tied to its staying here', () async {
      final b = make('a5', Ownership.passingOn);
      await store.create(b);
      final made = await links.make(b) as Made;
      await store.delete(b.id);
      expect(await links.liveOf(b.id), hasLength(1));
      expect(await links.open(linkPartsOf(made.url)!), isA<ArrivalNew>());
    });
  });

  group('the service over HTTP', () {
    late HttpServer server;
    late List<({String method, String path, String auth, Uint8List body})> seen;
    late Future<void> Function(HttpRequest r) answer;

    setUp(() async {
      seen = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        final body = await r.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
        seen.add((method: r.method, path: r.uri.toString(), auth: r.headers.value('authorization') ?? '', body: body.takeBytes()));
        await answer(r);
      });
    });
    tearDown(() => server.close(force: true));

    HttpLinkService http() => HttpLinkService(base: 'http://127.0.0.1:${server.port}', timeout: const Duration(seconds: 5));
    Future<void> json(HttpRequest r, int status, Object body) async {
      r.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await r.response.close();
    }

    test('create: 201 and its answer', () async {
      answer = (r) => json(r, 201, {'id': 'CRAXHiUsMzpBSE9WXWRrcg', 'expires': '2026-12-16T10:00:00Z', 'stop': 'S' * 43});
      final r = await http().create(Uint8List.fromList([1, ...List.filled(40, 7)])) as Created;
      expect((r.id, r.expires, r.stop), ('CRAXHiUsMzpBSE9WXWRrcg', DateTime.utc(2026, 12, 16, 10), 'S' * 43));
      expect((seen.single.method, seen.single.path, seen.single.body.length), ('POST', '/api/b', 41));
    });

    test('each refusal is its own plain outcome', () async {
      for (final (status, error, trouble) in [
        (429, 'slow_down', LinkTrouble.slowDown),
        (503, 'full', LinkTrouble.full),
        (503, 'unavailable', LinkTrouble.unavailable),
        (413, 'too_large', LinkTrouble.tooBig),
        (415, 'not_a_locked_copy', LinkTrouble.unavailable),
      ]) {
        answer = (r) => json(r, status, {'error': error});
        expect((await http().create(Uint8List(41)..[0] = 1) as CreateFailed).trouble, trouble, reason: '$status $error');
      }
    });

    test('something that is not the service (no JSON error) counts as no internet', () async {
      answer = (r) async {
        r.response
          ..statusCode = 404
          ..headers.contentType = ContentType.html
          ..write('<html>not here</html>');
        await r.response.close();
      };
      expect((await http().create(Uint8List(41)..[0] = 1) as CreateFailed).trouble, LinkTrouble.offline);
      expect(await http().read('CRAXHiUsMzpBSE9WXWRrcg'), isA<ReadFailed>());
      expect(await http().stop('CRAXHiUsMzpBSE9WXWRrcg', 'S' * 43), StopResult.offline);
    });

    test('nothing there at all is no internet', () async {
      final port = server.port;
      await server.close(force: true);
      final s = HttpLinkService(base: 'http://127.0.0.1:$port', timeout: const Duration(seconds: 5));
      expect((await s.create(Uint8List(41)..[0] = 1) as CreateFailed).trouble, LinkTrouble.offline);
      expect((await s.read('CRAXHiUsMzpBSE9WXWRrcg') as ReadFailed).trouble, LinkTrouble.offline);
      expect(await s.stop('CRAXHiUsMzpBSE9WXWRrcg', 'S' * 43), StopResult.offline);
    });

    test('read: the bytes, or gone', () async {
      answer = (r) async {
        r.response.headers.contentType = ContentType.binary;
        r.response.add([1, 2, 3]);
        await r.response.close();
      };
      expect((await http().read('CRAXHiUsMzpBSE9WXWRrcg') as ReadCopy).locked, [1, 2, 3]);
      expect(seen.last.path, '/api/b/CRAXHiUsMzpBSE9WXWRrcg');
      answer = (r) => json(r, 410, {'error': 'gone'});
      expect(await http().read('CRAXHiUsMzpBSE9WXWRrcg'), isA<ReadGone>());
      // an id that is not one is never asked for
      final before = seen.length;
      expect(await http().read('../../etc'), isA<ReadGone>());
      expect(seen.length, before);
    });

    test('stop: the token in the Authorization header only; 204 and 410 are stopped', () async {
      answer = (r) async {
        r.response.statusCode = 204;
        await r.response.close();
      };
      expect(await http().stop('CRAXHiUsMzpBSE9WXWRrcg', 'S' * 43), StopResult.stopped);
      expect((seen.last.method, seen.last.path, seen.last.auth), ('DELETE', '/api/b/CRAXHiUsMzpBSE9WXWRrcg', 'Bearer ${'S' * 43}'));
      answer = (r) => json(r, 410, {'error': 'gone'});
      expect(await http().stop('CRAXHiUsMzpBSE9WXWRrcg', 'S' * 43), StopResult.stopped);
      answer = (r) => json(r, 403, {'error': 'forbidden'});
      expect(await http().stop('CRAXHiUsMzpBSE9WXWRrcg', 'S' * 43), StopResult.failed);
    });

    test('a whole link made and opened over HTTP: the key is in no request', () async {
      final copies = <String, List<int>>{};
      answer = (r) async {
        if (r.method == 'POST') {
          copies['CRAXHiUsMzpBSE9WXWRrcg'] = seen.last.body;
          return json(r, 201, {'id': 'CRAXHiUsMzpBSE9WXWRrcg', 'expires': '2026-12-16T10:00:00Z', 'stop': 'S' * 43});
        }
        r.response.headers.contentType = ContentType.binary;
        r.response.add(copies['CRAXHiUsMzpBSE9WXWRrcg']!);
        await r.response.close();
      };
      final l = Links(store: store, crypto: crypto, secrets: secrets, service: http(), now: () => now);
      final made = await l.make(surgery()) as Made;
      final parts = linkPartsOf(made.url)!;
      final a = await l.open(parts);
      expect(a, isA<ArrivalNew>());
      final key = keyOfFragment(parts.fragment)!;
      for (final s in seen) {
        expect(s.path.contains(parts.fragment) || s.auth.contains(parts.fragment), isFalse);
        expect(_contains(s.body, key) || _contains(s.body, utf8.encode(parts.fragment)), isFalse);
      }
    });
  });
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
