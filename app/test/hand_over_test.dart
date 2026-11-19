// Handing a family member's whole ring to their own phone (design/entry-and-rings, B1 rows 9–16):
// the bundle's round trip, older readers, the size limits, an old single-blessing link still read,
// keeping a ring (joins "For me" by date, the same blessing kept once), "Kept for you by", the store
// migration, and the two sheets at the largest text and in Spanish.
//
//   flutter test test/hand_over_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/sent_link.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/hand_over_sheet.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/hand_over.dart';
import 'package:upon_thy_head/share/link_crypto.dart';
import 'package:upon_thy_head/share/link_format.dart';
import 'package:upon_thy_head/share/link_service.dart';
import 'package:upon_thy_head/share/links.dart';
import 'package:upon_thy_head/share/receive.dart';
import 'package:upon_thy_head/share/ring_arrival.dart';
import 'package:upon_thy_head/share/ring_file.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';

import 'support/node_crypto.dart';

class _Service implements LinkService {
  final Map<String, Uint8List> copies = {};
  final List<Uint8List> sent = [];
  var _n = 0;

  @override
  Future<CreateResult> create(Uint8List locked) async {
    sent.add(locked);
    final id = 'R${(_n++).toString().padLeft(21, '0')}';
    copies[id] = locked;
    return Created(id: id, expires: DateTime.utc(2026, 12, 18), stop: 'S' * 43);
  }

  @override
  Future<ReadResult> read(String id) async {
    final c = copies[id];
    return c == null ? const ReadGone() : ReadCopy(c);
  }

  @override
  Future<StopResult> stop(String id, String stopToken) async => StopResult.stopped;
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

/// Emma's ring on Dad's phone: the five samples, given in a shuffled order, on Emma's ring.
List<Blessing> emmasRing() => [for (final b in sampleBlessings().reversed) b..personId = 'emma'];

void main() {
  late Directory dir;
  late SqliteBlessingStore store;
  final crypto = NodeLinkCrypto();
  const place = Place(40.2, -111.6);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hand_over');
    store = SqliteBlessingStore.open('${dir.path}/blessings.sqlite');
  });
  tearDown(() async {
    Strings.use(UiLanguage.english);
    await store.close();
    dir.deleteSync(recursive: true);
  });

  group('the bundle', () {
    test('round trip: every blessing, oldest first, words, changes, date precision and entered kept', () {
      final ring = emmasRing();
      ring[0]
        ..precision = DatePrecision.year
        ..entered = true;
      ring.add(Blessing(id: 'draft', title: 'Half', from: 'Dad', utc: DateTime.utc(2026), utcOffset: Duration.zero, place: place));
      final bundle = RingBundle.of(ring, keptBy: ' Dad ');
      final read = readShared(bundle.toCompactBytes()) as SharedRing;
      expect(read.ring.keptBy, 'Dad');
      expect([for (final r in read.ring.records) r.id], ['fever', 'baby', 'primary', 'surgery', 'job'], reason: 'oldest first; the draft stays behind');
      final job = read.ring.records.last;
      expect(job.precision, DatePrecision.year);
      expect(job.entered, isTrue);
      final surgery = read.ring.records.firstWhere((r) => r.id == 'surgery');
      expect(surgery.sameAs(ring.firstWhere((b) => b.id == 'surgery')), isTrue);
      expect(applyKept(surgery), applyChanges(surgery.spoken, surgery.changes));
    });

    test('an older app reading a ring says "made with a newer version", not damaged', () {
      final bytes = RingBundle.of(emmasRing(), keptBy: 'Dad').toCompactBytes();
      expect(readBlessingFile(bytes), isA<BlessingReadNewer>());
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect((j['format'], j['version'], j['kind']), ('upon-thy-head/blessing', 3, 'ring'));
    });

    test('a single blessing still reads as one; a damaged or strange ring is refused', () {
      final one = sampleBlessings().first;
      expect(readShared(utf8.encode(jsonEncode(BlessingRecord.of(one).toJson()))), isA<SharedBlessing>());
      Map<String, Object?> ring() => RingBundle.of(emmasRing(), keptBy: 'Dad').toJson();
      expect(readShared(utf8.encode(jsonEncode(ring()..['version'] = 4))), isA<SharedNewer>());
      expect(readShared(utf8.encode(jsonEncode(ring()..['blessings'] = 'x'))), isA<SharedBad>());
      expect(readShared(utf8.encode(jsonEncode(ring()..['keptBy'] = 'Da\u0000d'))), isA<SharedBad>());
      expect(readShared(utf8.encode('{"format":"upon-thy-head/blessing"')), isA<SharedBad>());
    });

    test('the same blessing twice in a bundle is kept once', () {
      final j = RingBundle.of(emmasRing(), keptBy: 'Dad').toJson();
      final list = j['blessings'] as List;
      j['blessings'] = [...list, list.first];
      final read = readShared(utf8.encode(jsonEncode(j))) as SharedRing;
      expect(read.ring.records, hasLength(5));
    });
  });

  group('the size limits', () {
    test('the link frame takes up to 512 KiB, and no more', () {
      Uint8List frame(int n) => Uint8List(n)..[0] = 1;
      expect(linkMaxBytes, 524288);
      expect(frameError(frame(524288)), isNull);
      expect(frameError(frame(524289)), LinkError.damaged);
    });

    test('a ring too big for a link is refused before anything is sent; an empty one is not made', () async {
      final service = _Service();
      final links = Links(store: store, crypto: crypto, secrets: MemorySecrets(), service: service, now: () => DateTime.utc(2026, 11, 18));
      final huge = [
        for (var i = 0; i < 40; i++)
          Blessing(id: 'big$i', title: 'Big $i', from: 'Dad', utc: DateTime.utc(2000 + i), utcOffset: Duration.zero, place: place, rawText: 'word ' * 9000, draft: false),
      ];
      expect((await links.makeRing('emma', huge, keptBy: 'Dad', title: 'Emma')) as NotMade, isA<NotMade>().having((n) => n.trouble, 'trouble', LinkTrouble.tooBig));
      expect((await links.makeRing('emma', const [], keptBy: 'Dad', title: 'Emma')), isA<NotMade>());
      expect(service.sent, isEmpty);
      expect(await store.links(), isEmpty);
    });

    test('sixty ordinary blessings fit easily', () {
      final many = [for (var i = 0; i < 12; i++) ...emmasRing().map((b) => Blessing(id: '${b.id}$i', title: b.title, from: b.from, utc: b.utc.add(Duration(days: i)), utcOffset: b.utcOffset, place: place, rawText: b.rawText, changes: b.changes, draft: false))];
      expect(RingBundle.of(many, keptBy: 'Dad').toCompactBytes().length, lessThan(linkMaxBytes ~/ 4));
    });
  });

  group('by link', () {
    test('a ring link: only locked bytes leave, kept in "Your links" as the ring, and it opens to the new ones', () async {
      final service = _Service();
      final links = Links(store: store, crypto: crypto, secrets: MemorySecrets(), service: service, now: () => DateTime.utc(2026, 11, 18));
      final made = await links.makeRing('emma', emmasRing(), keptBy: 'Dad', title: 'Emma’s ring') as Made;
      final sent = service.sent.single;
      for (final secret in ['Dad', 'Emma', 'Comfort before surgery', 'Grandpa Ruiz', 'ring']) {
        expect(_contains(sent, utf8.encode(secret)), isFalse, reason: secret);
      }
      expect(made.url, isNot(contains('Emma')));
      final kept = (await store.links()).single;
      expect((kept.blessingId, kept.title), (ringLinkId('emma'), 'Emma’s ring'));

      // Emma's phone already has one of them
      await store.create(sampleBlessings().firstWhere((b) => b.id == 'baby'));
      final parts = linkPartsOf(made.url)!;
      final a = await openLocked(crypto, sent, keyOfFragment(parts.fragment)!, store.get) as ArrivalRing;
      expect([for (final r in a.fresh) r.id], ['fever', 'primary', 'surgery', 'job']);
      expect(a.had, 1);
      expect(a.ring.keptBy, 'Dad');
    });

    test('an old single-blessing link still opens as before', () async {
      final service = _Service();
      final links = Links(store: store, crypto: crypto, secrets: MemorySecrets(), service: service, now: () => DateTime.utc(2026, 11, 18));
      final b = sampleBlessings().firstWhere((b) => b.id == 'surgery');
      final made = await links.make(b) as Made;
      final parts = linkPartsOf(made.url)!;
      final a = await openLocked(crypto, service.sent.single, keyOfFragment(parts.fragment)!, (_) async => null);
      expect(a, isA<ArrivalNew>());
      expect((a as ArrivalNew).record.sameAs(b), isTrue);
    });
  });

  group('keeping a ring', () {
    ArrivalRing arrival(String keptBy, Set<String> have) {
      final bundle = RingBundle.of(emmasRing(), keptBy: keptBy);
      final n = ringNews(bundle, have);
      return ArrivalRing(bundle, n.fresh, n.had);
    }

    test('it joins "For me" by date, each kept by the sender', () async {
      // Emma's own blessing, given between two of Dad's
      await store.create(Blessing(id: 'mine', title: 'Mine', from: 'Bishop', utc: DateTime.utc(2025, 3, 1), utcOffset: Duration.zero, place: place, draft: false));
      final ids = await keepRing(store, arrival('Dad', {'mine'}), place: place, now: DateTime.utc(2026, 11, 18));
      expect(ids, ['fever', 'baby', 'primary', 'surgery', 'job']);
      final f = Family(await store.people(), await store.list(ownership: Ownership.forMe));
      expect([for (final b in f.on('')) b.id], ['fever', 'baby', 'mine', 'primary', 'surgery', 'job']);
      final job = (await store.get('job'))!;
      expect((job.keptBy, job.ownership, job.personId), ('Dad', Ownership.forMe, ''));
      expect((await store.get('mine'))!.keptBy, '');
    });

    test('the same blessing is kept once: a second hand-over adds only what is new, and names both', () async {
      await keepRing(store, arrival('Dad', {}), place: place, now: DateTime.utc(2026, 11, 18));
      final before = (await store.get('surgery'))!;
      // Mom hands over the same ring, plus one more, a week later
      final bundle = RingBundle.of([...emmasRing(), Blessing(id: 'late', title: 'Late', from: 'Mom', utc: DateTime.utc(2026, 11, 1), utcOffset: Duration.zero, place: place, draft: false)], keptBy: 'Mom');
      final n = ringNews(bundle, {for (final b in await store.list()) b.id});
      expect(n.had, 5);
      final ids = await keepRing(store, ArrivalRing(bundle, n.fresh, n.had), place: place, now: DateTime.utc(2026, 11, 25));
      expect(ids, ['late']);
      final all = await store.list();
      expect(all, hasLength(6));
      expect((await store.get('surgery'))!.keptBy, before.keptBy, reason: 'the copy kept first stays as it was');
      expect(keptByNames(all), ['Dad', 'Mom']);
    });

    test('meanwhile come to have: kept once, as it is', () async {
      final a = arrival('Dad', {});
      await store.create(sampleBlessings().firstWhere((b) => b.id == 'job'));
      final ids = await keepRing(store, a, place: place);
      expect(ids, isNot(contains('job')));
      expect((await store.list()), hasLength(5));
      expect((await store.get('job'))!.keptBy, '');
    });
  });

  group('the words', () {
    test('"Kept for you by" with one and two names, and "Kept by", in both languages', () {
      Strings.use(UiLanguage.english);
      expect(Strings.keptForYouBy(['Dad']), 'Kept for you by Dad');
      expect(Strings.keptForYouBy(['Dad', 'Mom']), 'Kept for you by Dad and Mom');
      expect(Strings.keptByLine('Dad'), 'Kept by Dad');
      Strings.use(UiLanguage.spanish);
      expect(Strings.keptForYouBy(['Dad']), 'Guardadas para ti por Dad');
      expect(Strings.keptForYouBy(['Dad', 'Mom']), 'Guardadas para ti por Dad y Mom');
      expect(Strings.keptByLine('Dad'), 'Guardada por Dad');
    });

    test('the "Kept by" name: remembered, else the most common From, else empty', () {
      final ring = emmasRing();
      expect(suggestedKeptBy(ring), 'Dad');
      expect(suggestedKeptBy(ring, remembered: ' Mom '), 'Mom');
      expect(suggestedKeptBy(ring, remembered: '  '), 'Dad');
      expect(suggestedKeptBy([for (final b in ring) b..from = '']), '');
      // a tie: the one met first, oldest first
      expect(suggestedKeptBy(sampleBlessings().take(2)), 'Grandpa Ruiz');
    });
  });

  group('the store', () {
    test('a version 9 file gains "kept by" and "handed over", losing nothing', () async {
      await store.close();
      final path = '${dir.path}/old.sqlite';
      var db = sqlite3.open(path);
      SqliteBlessingStore.migrateTo(db, 9);
      db.execute("INSERT INTO blessings (id, title, giver, recipient, ownership, given_utc_minute, utc_offset_minutes, latitude, longitude, "
          "raw_text, polished_text, draft, created_at_ms, updated_at_ms, audio, language, first_text, person_id) VALUES "
          "('old', 'Comfort', 'Dad', 'Emma', 'for_me', 29000000, -420, 40.2, -111.6, 'I bless you', 'I bless you', 0, 5, 6, '', 'en', 'I bless you', '')");
      db.close();
      store = SqliteBlessingStore.open(path);
      final old = (await store.get('old'))!;
      expect((old.title, old.rawText, old.keptBy), ('Comfort', 'I bless you', ''));
      db = sqlite3.open(path);
      expect(db.userVersion, SqliteBlessingStore.schemaVersion);
      expect(SqliteBlessingStore.schemaVersion, 10);
      db.close();

      // both round trip
      await store.create(Blessing(id: 'k', title: 'K', from: 'Dad', utc: DateTime.utc(2020), utcOffset: Duration.zero, place: place, keptBy: 'Dad', draft: false));
      expect((await store.get('k'))!.keptBy, 'Dad');
      final b = (await store.get('k'))!..keptBy = 'Mom';
      await store.update(b);
      expect((await store.get('k'))!.keptBy, 'Mom');
      final emma = Person(id: 'emma', name: 'Emma');
      await store.addPerson(emma);
      expect((await store.people()).single.handed, isNull);
      emma.handed = DateTime.utc(2026, 11, 18, 9);
      await store.updatePerson(emma);
      expect((await store.people()).single.handed, DateTime.utc(2026, 11, 18, 9));
    });
  });

  group('the sheets', () {
    Future<void> show(WidgetTester t, Widget child, {double scale = 1}) async {
      t.view.physicalSize = const Size(402, 874) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(
            size: const Size(402, 874), devicePixelRatio: 3, padding: const EdgeInsets.only(top: 62), viewPadding: const EdgeInsets.only(top: 62), textScaler: TextScaler.linear(scale)),
        child: CupertinoApp(
          localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          home: ColoredBox(color: Palette.lamplight.ground, child: child),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
    }

    Made made() => Made(
        url: 'https://uponthyhead.app/b/R000000000000000000000#${'k' * 43}',
        link: SentLink(id: 'R000000000000000000000', blessingId: 'ring:emma', title: 'Emma’s ring', sent: DateTime.utc(2026, 11, 18), expires: DateTime.utc(2026, 12, 18)));

    for (final lang in [UiLanguage.english, UiLanguage.spanish]) {
      for (final scale in [1.0, 3.1]) {
        testWidgets('the sending sheet: ${lang.name}, text ×$scale — nothing overflows; send, then Keep or Delete', (t) async {
          Strings.use(lang);
          final shared = <String>[], keptBy = <String>[];
          var closed = 0, deleted = 0;
          await show(
            t,
            HandOverSheet(
              palette: Palette.lamplight,
              on: true,
              person: Person(id: 'emma', name: 'Emma'),
              countLine: countLine(emmasRing()),
              keptBy: 'Dad',
              onMake: (k) async => made(),
              onShare: (url, title) async {
                shared.add(url);
                return true;
              },
              onSent: keptBy.add,
              onClose: () => closed++,
              onDelete: () => deleted++,
            ),
            scale: scale,
          );
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('hand-over-note')), findsOneWidget);
          expect(find.text(Strings.ringKeepNote('Emma')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('hand-over-send')));
          await t.tap(find.byKey(const Key('hand-over-send')));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
          expect(t.takeException(), isNull);
          expect(shared, hasLength(1));
          expect(keptBy, ['Dad']);
          expect(find.byKey(const Key('hand-over-keep')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('hand-over-delete')));
          await t.tap(find.byKey(const Key('hand-over-delete')));
          await t.pump();
          expect(deleted, 1);
          expect(closed, 0);
          await t.pumpWidget(const SizedBox());
        });

        testWidgets('the receiving screen: ${lang.name}, text ×$scale — welcome, read oldest first, Keep them', (t) async {
          Strings.use(lang);
          final bundle = RingBundle.of(emmasRing(), keptBy: 'Dad');
          final n = ringNews(bundle, {});
          var kept = 0, notNow = 0;
          await show(
            t,
            RingArrivalLayer(palette: Palette.lamplight, arrival: ArrivalRing(bundle, n.fresh, n.had), more: false, onKeep: () => kept++, onNotNow: () => notNow++),
            scale: scale,
          );
          expect(t.takeException(), isNull);
          expect(find.text(Strings.ringWelcome), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('ring-arrival-continue')));
          await t.tap(find.byKey(const Key('ring-arrival-continue')));
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          expect(find.text('Healing, the night of the fever'), findsOneWidget, reason: 'oldest first');
          expect(find.text(Strings.ofTotal(1, 5)), findsOneWidget);
          await t.tap(find.byKey(const Key('ring-arrival-later')));
          await t.pump();
          expect(find.text('When the baby came early'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.tap(find.byKey(const Key('ring-arrival-keep')));
          expect(kept, 1);
          await t.tap(find.byKey(const Key('ring-arrival-not-now')));
          expect(notNow, 1);
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  });
}
