import 'dart:convert';
import 'dart:typed_data';

import '../data/blessing.dart';
import '../place/where.dart';
import '../polish/change.dart';
import '../sky/astro.dart';
import '../strings.dart';

/// A blessing as one record that leaves the phone and comes back into the app on another one: the
/// `.blessing` file (docs/blessing-file.md), and the same record inside a link (share/links.dart, website/PROTOCOL.md).
///
/// It carries exactly what the receiver needs to read what the sender reads, and to open the
/// changes screen and restore the spoken words: id, title, the minute it was given and its clock
/// offset, the giver, the recipient, tags, the language, the spoken words, polish's changes
/// with which are kept, and the place it was given, rounded to a tenth of a degree as the app keeps
/// it (optional; files made before 2026-11-16 have none). Never the audio, the first transcript,
/// or anything about the sender's phone.
///
/// Reading is strict, because a file is something a stranger could have made: a size limit, every
/// field checked and length-limited, unknown fields ignored. Nothing in it is ever run or fetched;
/// it only ever becomes text on the screen.

/// What the record says it is, so a file of anything else is refused.
const blessingFormat = 'upon-thy-head/blessing';

/// The newest version this code reads. It writes version 1 for a blessing recorded on a known day,
/// exactly as before, so every app reads it; and version 2 for one entered from a written copy or
/// known only to its month or year, so an app from before those cannot show it as a recording on
/// July 2 and says instead that it was made with a newer version.
const blessingFormatVersion = 2;

/// The largest file read at all, in bytes. A 2,500-word blessing with its changes is about 17 KB.
const blessingFileMaxBytes = 512 * 1024;

/// Limits on each field, in UTF-16 code units (Dart string length).
abstract final class BlessingLimits {
  static const id = 64;
  static const title = 300;
  static const name = 200; // the giver, the recipient
  static const tags = 40;
  static const tag = 60;
  static const language = 20;
  static const words = 200000; // about 35,000 words
  static const changes = 5000;
  static const changeText = 2000; // was, now
  static const source = 40;
}

/// The record's fields, as a [Blessing] keeps them.
class BlessingRecord {
  BlessingRecord({
    required this.id,
    required this.title,
    required this.utc,
    required this.utcOffset,
    this.from = '',
    this.recipient = '',
    this.tags = const [],
    this.language = '',
    required this.spoken,
    this.changes = const [],
    this.place,
    this.precision = DatePrecision.day,
    this.entered = false,
  });

  /// How much of the date is known; [utc] is where its light sits (the 15th, or July 2, at noon).
  final DatePrecision precision;

  /// Entered from a written copy, not recorded.
  final bool entered;

  /// The version this record is written as: 1 unless it needs what came in 2.
  int get version => precision == DatePrecision.day && !entered ? 1 : 2;

  /// What [b] shares: the words as spoken and its changes as they stand, so the receiver's reading
  /// page shows what the sender's does.
  factory BlessingRecord.of(Blessing b) => BlessingRecord(
        id: b.id,
        title: b.title,
        utc: DateTime.fromMillisecondsSinceEpoch(b.utc.millisecondsSinceEpoch ~/ 60000 * 60000, isUtc: true),
        utcOffset: Duration(minutes: b.utcOffset.inMinutes),
        from: b.from,
        recipient: b.recipient,
        tags: [...b.tags],
        language: b.language,
        spoken: b.rawText,
        changes: [for (final c in [...b.changes]..sort((x, y) => x.start.compareTo(y.start))) c.copy()],
        place: roughly(b.place.lat, b.place.lon),
        // a draft with no date yet is never sent; were one to be, it would be its day
        precision: b.precision == DatePrecision.unset ? DatePrecision.day : b.precision,
        entered: b.entered,
      );

  final String id, title, from, recipient, language, spoken;

  /// The minute it was given (UTC), and the clock offset where it was given.
  final DateTime utc;
  final Duration utcOffset;
  final List<String> tags;
  final List<Change> changes;

  /// Where it was given, to a tenth of a degree; null in a file made before the place was carried.
  final Place? place;

  /// The JSON object, keys in a fixed order (the same blessing always gives the same bytes).
  Map<String, Object> toJson() => {
        'format': blessingFormat,
        'version': version,
        'id': id,
        'title': title,
        'given': _iso(utc),
        'offset': utcOffset.inMinutes,
        'from': from,
        'for': recipient,
        'tags': tags,
        'language': language,
        'words': spoken,
        'changes': [
          for (final c in changes) {'at': c.start, 'was': c.was, 'now': c.now, 'kind': c.kind.code, 'source': c.source, 'kept': c.kept},
        ],
        if (place != null) 'place': {'lat': place!.lat, 'lon': place!.lon},
        if (precision != DatePrecision.day) 'precision': precision.code,
        if (entered) 'entered': true,
      };

  /// The file's bytes: UTF-8 JSON, indented so a person who opens it in a text editor can read it.
  Uint8List toFileBytes() => Uint8List.fromList(utf8.encode('${const JsonEncoder.withIndent(' ').convert(toJson())}\n'));

  /// The same without spaces (the link).
  Uint8List toCompactBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Whether [b] already says exactly this: what the reader sees and can restore. Ownership,
  /// draft, place and dates of the record itself do not count.
  bool sameAs(Blessing b) {
    final o = BlessingRecord.of(b);
    if (o.id != id || o.title != title || o.utc != utc || o.utcOffset != utcOffset || o.from != from || o.recipient != recipient) return false;
    if (o.precision != precision || o.entered != entered) return false;
    if (o.language != language || o.spoken != spoken || o.tags.length != tags.length || o.changes.length != changes.length) return false;
    for (var i = 0; i < tags.length; i++) {
      if (o.tags[i] != tags[i]) return false;
    }
    for (var i = 0; i < changes.length; i++) {
      final a = o.changes[i], c = changes[i];
      if (a.start != c.start || a.was != c.was || a.now != c.now || a.kind != c.kind || a.source != c.source || a.kept != c.kept) return false;
    }
    return true;
  }

  /// A finished blessing of the person's own, at the place it was given; for a file that carries
  /// none (made before the place was carried), at [place] (the receiver's).
  Blessing toBlessing({required Place place, DateTime? now, String keptBy = ''}) {
    final t = (now ?? DateTime.now()).toUtc();
    return Blessing(
      keptBy: keptBy,
      id: id,
      title: title,
      from: from,
      recipient: recipient,
      utc: utc,
      utcOffset: utcOffset,
      place: this.place ?? place,
      ownership: Ownership.forMe,
      rawText: spoken,
      // what arrived is the first writing this phone has of it
      firstText: spoken,
      changes: [for (final c in changes) c.copy()],
      polishAsked: changes.isNotEmpty,
      tags: [...tags],
      draft: false,
      language: language,
      wordsStatus: WordsStatus.written,
      precision: precision,
      entered: entered,
      created: t,
      updated: t,
    );
  }

  /// [b] made to say exactly this (Replace mine), keeping when it was made, its own draft state and
  /// any recording kept with it (the caller decides about those); the place is the file's when it
  /// carries one.
  void writeOver(Blessing b) {
    b
      ..title = title
      ..from = from
      ..recipient = recipient
      ..utc = utc
      ..utcOffset = utcOffset
      ..rawText = spoken
      ..changes = [for (final c in changes) c.copy()]
      ..polishAsked = changes.isNotEmpty
      ..tags = [...tags]
      ..language = language
      ..ownership = Ownership.forMe
      ..precision = precision
      ..entered = entered
      ..wordsStatus = WordsStatus.written;
    if (place != null) b.place = place!;
    if (b.firstText.isEmpty) b.firstText = spoken;
  }
}

String _iso(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}Z';
}

/// What reading a file came to.
sealed class BlessingRead {
  const BlessingRead();
}

/// A blessing.
class BlessingReadOk extends BlessingRead {
  const BlessingReadOk(this.record);
  final BlessingRecord record;
}

/// Made by a newer version of the app: its version is above [blessingFormatVersion].
class BlessingReadNewer extends BlessingRead {
  const BlessingReadNewer(this.version);
  final int version;
}

/// Not a blessing this app can read; [why] is for the log and the tests, never shown.
class BlessingReadBad extends BlessingRead {
  const BlessingReadBad(this.why);
  final String why;
  @override
  String toString() => 'unreadable: $why';
}

class _Bad implements Exception {
  _Bad(this.why);
  final String why;
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _languagePattern = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$');
final _givenPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})Z$');

/// Read a `.blessing` file's [bytes], strictly.
BlessingRead readBlessingFile(List<int> bytes) {
  if (bytes.length > blessingFileMaxBytes) return BlessingReadBad('${bytes.length} bytes, over the limit');
  if (bytes.isEmpty) return const BlessingReadBad('empty');
  final String text;
  try {
    text = const Utf8Decoder(allowMalformed: false).convert(bytes);
  } on FormatException {
    return const BlessingReadBad('not UTF-8');
  }
  return readBlessingJson(text);
}

/// Read the record from its JSON [text], strictly.
BlessingRead readBlessingJson(String text) {
  final Object? json;
  try {
    json = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
  } on FormatException {
    return const BlessingReadBad('not JSON');
  }
  try {
    return readBlessingObject(json);
  } on _Bad catch (e) {
    return BlessingReadBad(e.why);
  }
}

/// Read the record from decoded JSON. The format and the version are looked at first, so a newer
/// file is recognised whatever else has changed in it.
BlessingRead readBlessingObject(Object? json, {DateTime? now}) {
  try {
    if (json is! Map<String, Object?>) throw _Bad('not an object');
    if (json['format'] != blessingFormat) throw _Bad('not a blessing');
    final version = json['version'];
    if (version is! int || version < 1) throw _Bad('no version');
    if (version > blessingFormatVersion) return BlessingReadNewer(version);
    return BlessingReadOk(_record(json, now ?? DateTime.now()));
  } on _Bad catch (e) {
    return BlessingReadBad(e.why);
  }
}

BlessingRecord _record(Map<String, Object?> j, DateTime now) {
  final id = _text(j, 'id', BlessingLimits.id, required: true);
  if (!_idPattern.hasMatch(id)) throw _Bad('id');
  // a title left out or empty is the untitled blessing's ("Blessing"), as the app names one
  var title = _text(j, 'title', BlessingLimits.title).trim();
  if (title.isEmpty) title = Strings.untitled;
  final given = _given(j['given'], now);
  final offset = j['offset'];
  if (offset is! int || offset.abs() > 18 * 60) throw _Bad('offset');
  final from = _text(j, 'from', BlessingLimits.name);
  final recipient = _text(j, 'for', BlessingLimits.name);
  final language = _text(j, 'language', BlessingLimits.language);
  if (language.isNotEmpty && !_languagePattern.hasMatch(language)) throw _Bad('language');
  final spoken = _text(j, 'words', BlessingLimits.words, required: true, lines: true);
  final tags = <String>[];
  final rawTags = j['tags'];
  if (rawTags != null) {
    if (rawTags is! List || rawTags.length > BlessingLimits.tags) throw _Bad('tags');
    for (final t in rawTags) {
      if (t is! String || t.length > BlessingLimits.tag || !_clean(t)) throw _Bad('tag');
      final s = t.trim();
      if (s.isNotEmpty && !tags.contains(s)) tags.add(s);
    }
  }
  final changes = <Change>[];
  final rawChanges = j['changes'];
  if (rawChanges != null) {
    if (rawChanges is! List || rawChanges.length > BlessingLimits.changes) throw _Bad('changes');
    for (final c in rawChanges) {
      if (c is! Map<String, Object?>) throw _Bad('change');
      final at = c['at'];
      final was = _text(c, 'was', BlessingLimits.changeText, required: true, lines: true);
      final now0 = _text(c, 'now', BlessingLimits.changeText, lines: true);
      final kindCode = _text(c, 'kind', 20, required: true);
      final kind = ChangeKind.values.where((k) => k.code == kindCode).firstOrNull;
      final source = _text(c, 'source', BlessingLimits.source);
      final kept = c['kept'];
      if (at is! int || at < 0 || was.isEmpty || kind == null || kept is! bool) throw _Bad('change');
      // it must stand on the spoken words, after the one before it, touching none
      if (at + was.length > spoken.length || spoken.substring(at, at + was.length) != was) throw _Bad('change not in the words');
      if (changes.isNotEmpty && at < changes.last.end) throw _Bad('changes overlap');
      changes.add(Change(start: at, was: was, now: now0, kind: kind, source: source.isEmpty ? Change.rulesSource : source, kept: kept));
    }
  }
  return BlessingRecord(
    id: id,
    title: title,
    utc: given,
    utcOffset: Duration(minutes: offset),
    from: from.trim(),
    recipient: recipient.trim(),
    tags: tags,
    language: language,
    spoken: spoken,
    changes: changes,
    place: _place(j['place']),
    precision: _precision(j['precision']),
    entered: _entered(j['entered']),
  );
}

/// The optional `precision`: "day" (or missing, as in every file before version 2), "month", "year".
DatePrecision _precision(Object? v) => switch (v) {
      null || 'day' => DatePrecision.day,
      'month' => DatePrecision.month,
      'year' => DatePrecision.year,
      _ => throw _Bad('precision'),
    };

/// The optional `entered`: true for a blessing entered from a written copy; missing is false.
bool _entered(Object? v) => switch (v) {
      null => false,
      bool b => b,
      _ => throw _Bad('entered'),
    };

/// The optional place: `{"lat": 40.8, "lon": -111.9}`, kept to a tenth of a degree whatever was
/// written. Missing or null is no place (a file made before it was carried).
Place? _place(Object? v) {
  if (v == null) return null;
  if (v is! Map<String, Object?>) throw _Bad('place');
  final lat = v['lat'], lon = v['lon'];
  if (lat is! num || lon is! num || !lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) throw _Bad('place');
  return roughly(lat.toDouble(), lon.toDouble());
}

/// A string field: [max] long at most, no control characters (but line breaks and tabs where
/// [lines]), no broken characters. Missing is '' unless [required].
String _text(Map<String, Object?> j, String key, int max, {bool required = false, bool lines = false}) {
  final v = j[key];
  if (v == null) {
    if (required) throw _Bad('no $key');
    return '';
  }
  if (v is! String) throw _Bad(key);
  if (v.length > max) throw _Bad('$key too long');
  if (!_clean(v, lines: lines)) throw _Bad('$key has characters that cannot be shown');
  return v;
}

/// No control characters (but \n, \r and \t where [lines]) and no lone surrogates.
bool _clean(String s, {bool lines = false}) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x20 || (c >= 0x7f && c < 0xa0)) {
      if (lines && (c == 0x0a || c == 0x0d || c == 0x09)) continue;
      return false;
    }
    if (c >= 0xd800 && c <= 0xdbff) {
      if (i + 1 >= s.length) return false;
      final d = s.codeUnitAt(i + 1);
      if (d < 0xdc00 || d > 0xdfff) return false;
      i++;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

/// "2026-03-03T16:40Z": a real minute, from the year 1900 to two days from now.
DateTime _given(Object? v, DateTime now) {
  if (v is! String) throw _Bad('no given');
  final m = _givenPattern.firstMatch(v);
  if (m == null) throw _Bad('given');
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!), h = int.parse(m[4]!), mi = int.parse(m[5]!);
  final t = DateTime.utc(y, mo, d, h, mi);
  // DateTime rolls 2026-02-30 over to March; a real date comes back as written
  if (t.year != y || t.month != mo || t.day != d || t.hour != h || t.minute != mi) throw _Bad('given');
  if (y < 1900 || t.isAfter(now.toUtc().add(const Duration(days: 2)))) throw _Bad('given out of range');
  return t;
}

/// "Comfort before surgery, March 3, 2026.blessing": named as the PDF is.
String blessingFileName(String pdfName) => '${pdfName.replaceFirst(RegExp(r'\.pdf$'), '')}.blessing';
