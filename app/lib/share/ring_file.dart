import 'dart:convert';
import 'dart:typed_data';

import '../data/blessing.dart';
import 'blessing_file.dart';
import 'link_format.dart';

/// A family member's whole ring, handed to their own phone (design/entry-and-rings, B1 rows 9–16):
/// every blessing on it, each as the record a `.blessing` file carries (blessing_file.dart), so a
/// date known only to its month and "entered from a written copy" travel as they do one at a time.
/// Locked and sent as one link exactly as a single blessing is (website/PROTOCOL.md); only the
/// record inside differs:
///
///     {"format":"upon-thy-head/blessing","version":3,"kind":"ring","keptBy":"Dad","blessings":[{…},{…}]}
///
/// Version 3 is the first version a ring can have. Every app and page from before it reads the
/// format, sees a version above 2 and says the blessing "was made with a newer version", which is
/// the polite failure an older app gives. A single blessing is still written as 1 or 2.
///
/// Nothing about the sender's phone is in it: not the family member's id, birth date or name (the
/// receiver is that person), only the name the parent chose to be known by ("Kept by").
const ringFormatVersion = 3;

/// What the record's `kind` says.
const ringKind = 'ring';

/// The most blessings one ring carries (far above any family's; a bound for what a stranger made).
const ringMaxBlessings = 2000;

/// A ring as it travels.
class RingBundle {
  RingBundle({required this.keptBy, required this.records});

  /// The name the parent typed on the sending sheet ("Dad"); may be ''.
  final String keptBy;

  /// Oldest first.
  final List<BlessingRecord> records;

  /// The ring's finished blessings, oldest first. Drafts and entries without a date never travel.
  factory RingBundle.of(Iterable<Blessing> ring, {required String keptBy}) {
    final list = [for (final b in ring) if (!b.draft && b.placed) b]..sort((a, b) => a.utc.compareTo(b.utc));
    return RingBundle(keptBy: keptBy.trim(), records: [for (final b in list) BlessingRecord.of(b)]);
  }

  Map<String, Object> toJson() => {
        'format': blessingFormat,
        'version': ringFormatVersion,
        'kind': ringKind,
        'keptBy': keptBy,
        'blessings': [for (final r in records) r.toJson()],
      };

  /// Compact UTF-8 JSON, as a link carries it.
  Uint8List toCompactBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// The earliest and latest of them (by when they were given).
  BlessingRecord get first => records.first;
  BlessingRecord get last => records.last;
}

/// What reading shared bytes came to: one blessing (as before), a ring, or neither.
sealed class SharedRead {
  const SharedRead();
}

class SharedBlessing extends SharedRead {
  const SharedBlessing(this.record);
  final BlessingRecord record;
}

class SharedRing extends SharedRead {
  const SharedRing(this.ring);
  final RingBundle ring;
}

class SharedNewer extends SharedRead {
  const SharedNewer();
}

class SharedBad extends SharedRead {
  const SharedBad(this.why);
  final String why;
}

/// Read what a link opened to, or a file's bytes: a blessing or a ring, strictly. A ring may be as
/// large as a locked copy may ([linkMaxBytes]); a single blessing keeps its own limit.
SharedRead readShared(List<int> bytes, {DateTime? now}) {
  if (bytes.length > linkMaxBytes) return SharedBad('${bytes.length} bytes, over the limit');
  if (bytes.isEmpty) return const SharedBad('empty');
  final Object? json;
  try {
    var text = const Utf8Decoder(allowMalformed: false).convert(bytes);
    if (text.startsWith('﻿')) text = text.substring(1);
    json = jsonDecode(text);
  } on FormatException {
    return const SharedBad('not UTF-8 JSON');
  }
  if (json is Map<String, Object?> && json['format'] == blessingFormat && json['kind'] == ringKind) return _ring(json, now ?? DateTime.now());
  if (bytes.length > blessingFileMaxBytes) return SharedBad('${bytes.length} bytes, over the limit');
  return switch (readBlessingObject(json, now: now)) {
    BlessingReadOk(:final record) => SharedBlessing(record),
    BlessingReadNewer() => const SharedNewer(),
    BlessingReadBad(:final why) => SharedBad(why),
  };
}

SharedRead _ring(Map<String, Object?> j, DateTime now) {
  final version = j['version'];
  if (version is! int || version < ringFormatVersion) return const SharedBad('ring version');
  if (version > ringFormatVersion) return const SharedNewer();
  final keptBy = j['keptBy'];
  if (keptBy != null && (keptBy is! String || keptBy.length > BlessingLimits.name || !isCleanText(keptBy))) {
    return const SharedBad('keptBy');
  }
  final list = j['blessings'];
  if (list is! List || list.isEmpty || list.length > ringMaxBlessings) return const SharedBad('blessings');
  final records = <BlessingRecord>[];
  final seen = <String>{};
  for (final o in list) {
    switch (readBlessingObject(o, now: now)) {
      case BlessingReadOk(:final record):
        // the same blessing twice in one ring is kept once
        if (seen.add(record.id)) records.add(record);
      case BlessingReadNewer():
        return const SharedNewer();
      case BlessingReadBad(:final why):
        return SharedBad('a blessing in the ring: $why');
    }
  }
  records.sort((a, b) => a.utc.compareTo(b.utc));
  return SharedRing(RingBundle(keptBy: (keptBy as String? ?? '').trim(), records: records));
}

/// What keeping a ring on this phone would do: the blessings it does not have yet, oldest first,
/// and how many it already has (kept once: the phone's own copy stays as it is).
({List<BlessingRecord> fresh, int had}) ringNews(RingBundle ring, Set<String> haveIds) {
  final fresh = [for (final r in ring.records) if (!haveIds.contains(r.id)) r];
  return (fresh: fresh, had: ring.records.length - fresh.length);
}
