import 'dart:math' as math;

import '../polish/change.dart';
import '../sky/astro.dart';
import '../strings.dart';
import 'given.dart';

export 'given.dart';

/// Whose blessing this is: given to the person keeping the record, or one they
/// are keeping for someone else to pass along.
enum Ownership { forMe, passingOn }

/// Whether the words of a recorded blessing have been written from its audio.
enum WordsStatus {
  /// Not yet: the app was closed before they were written. They are written at the next launch.
  pending('pending'),

  /// Written (possibly empty, if nothing was heard), or typed, or never needed (no recording).
  written('written'),

  /// No engine on this phone could write the language; the audio is kept.
  unavailable('unavailable'),

  /// The engine failed; the audio is kept.
  failed('failed'),

  /// Recorded on a phone that could not write the words yet (Android, before its one-time download
  /// of the speech model): the audio is kept, even after review is finished, until the phone has
  /// written words from it. The words may be typed meanwhile.
  later('later');

  const WordsStatus(this.code);

  /// What the store keeps.
  final String code;

  static WordsStatus fromCode(String? code) => values.firstWhere((v) => v.code == code, orElse: () => written);
}

/// One blessing, as it is kept.
class Blessing {
  Blessing({
    required this.id,
    required this.title,
    required this.from,
    required this.utc,
    required this.utcOffset,
    required this.place,
    this.recipient = '',
    this.ownership = Ownership.forMe,
    this.personId = '',
    this.rawText = '',
    this.firstText = '',
    List<Change>? changes,
    this.polishAsked = false,
    this.tags = const [],
    this.draft = true,
    this.audio = '',
    this.language = '',
    this.wordsStatus = WordsStatus.written,
    this.sent,
    this.precision = DatePrecision.day,
    this.entered = false,
    this.keptBy = '',
    DateTime? created,
    DateTime? updated,
  })  : changes = changes ?? [],
        created = created ?? DateTime.now().toUtc(),
        updated = updated ?? created ?? DateTime.now().toUtc();

  final String id;

  /// [from] (the giver) is empty until the person giving it is known (a new recording).
  String title, from;

  /// Who it was given to ("for").
  String recipient;

  Ownership ownership;

  /// The family member whose ring it is on (people/person.dart), or '' for the person keeping the
  /// record. Always '' for one being passed along. Not part of what is sent.
  String personId;

  /// The minute it was given; a draft's is set again when its recording begins.
  DateTime utc;

  /// The clock offset where it was given, so its date never shifts when the phone travels.
  Duration utcOffset;

  Place place;

  /// The spoken words: as the phone wrote them, with the person's corrections. Polish never changes
  /// them. Paragraphs are separated by a blank line.
  String rawText;

  /// The changes polish proposed to [rawText], each kept or restored (polish/change.dart).
  List<Change> changes;

  /// The person asked for the words to be polished (so a later correction is looked at again).
  bool polishAsked;

  /// The spoken words with the kept changes applied.
  String get polishedText => applyChanges(rawText, changes);

  /// How many changes are kept.
  int get keptChanges => changes.where((c) => c.kept).length;

  /// The words exactly as the phone first wrote them from the recording, before anyone corrected
  /// them. Set once; the store never changes it afterwards, so a bad correction can be undone.
  String firstText;

  List<String> tags;

  /// Not yet reviewed.
  bool draft;

  /// The recording's file name in the audio folder (see data/audio.dart); '' when there is none.
  /// Kept on the phone until the blessing has been reviewed, then erased.
  String audio;

  /// The language it was spoken in: "en", "es", or '' for blessings from before recording.
  String language;

  /// Whether the words have been written from the recording yet.
  WordsStatus wordsStatus;

  /// When a blessing being passed along was sent (a link made and handed to the share sheet, or the
  /// file sent); null until then. Not part of what is sent.
  DateTime? sent;

  /// When this record was made and last changed (UTC).
  DateTime created, updated;

  /// How much of the date is known: a recording's is the day (and minute); an entered one may know
  /// only the month or the year ([utc] is then its light's place: the 15th, or July 2, at noon), or
  /// not yet have one ([DatePrecision.unset]: an entry still being written, on no ring).
  DatePrecision precision;

  /// Entered from a written copy (typed or pasted), not recorded. Its words are never polished.
  bool entered;

  /// Who kept it before it came to this phone with a whole ring handed over ("Dad", share/ring_file.dart);
  /// '' for every other blessing. Its reading page says "Kept by Dad", and the person's own sky
  /// "Kept for you by Dad". Not part of what is sent.
  String keptBy;

  /// It has a date, so a light and a place on its ring.
  bool get placed => precision != DatePrecision.unset;

  /// Its place in the sky, set by the placement rule (see sky/placement.dart). Not stored.
  double ra = 0, dec = 0;
  Vec3 v = const Vec3(1, 0, 0);

  DateTime get local => utc.add(utcOffset);

  /// The words to read: the polished ones when any change is kept, else the spoken ones.
  String get words => keptChanges > 0 ? polishedText : rawText;
  bool get hasWords => words.trim().isNotEmpty;

  /// "Tuesday, March 3, 2026"
  /// The title as shown: one never given reads "Blessing" or "Bendición" in the phone's language,
  /// whichever language it was made in. A title the person typed is shown exactly as typed.
  String get shownTitle => Strings.isUntitled(title) ? Strings.untitled : title;

  /// "Tuesday, March 3, 2026", "August 1998" or "1998", as much as is known.
  String get longDate => Strings.givenLong(local, precision);

  /// "Mar 3, 2026", "Aug 1998" or "1998".
  String get shortDate => Strings.givenShort(local, precision);

  /// The words in paragraphs, as the reading page and what is shared show them. A recording's
  /// paragraphs are separated by a blank line; words entered from a written copy are kept exactly
  /// as typed or pasted, where a single line break (as Notes and mail write one) also ends one.
  List<String> get paragraphs =>
      words.split(entered ? RegExp(r'\n') : RegExp(r'\n\s*\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

final _random = math.Random.secure();

/// A new random id: 128 bits as hex.
String newBlessingId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// A new blessing as its recording starts: given now, at [place] ("the place blessings are given",
/// place/where.dart), for me, or for the family member [personId].
Blessing draftBlessing(DateTime now, {required Place place, String personId = ''}) => Blessing(
      id: newBlessingId(),
      title: Strings.untitled,
      from: '',
      utc: now.toUtc(),
      utcOffset: now.timeZoneOffset,
      place: place,
      ownership: Ownership.forMe,
      personId: personId,
      draft: true,
    );

/// A blessing entered from a written copy, as its entry page opens: no date yet, no words, for me
/// or for the family member [personId], at [place] (the place blessings are given, as a recording's).
/// It is a draft from the start, so nothing typed is lost.
Blessing enteredBlessing(DateTime now, {required Place place, String personId = ''}) => Blessing(
      id: newBlessingId(),
      title: Strings.untitled,
      from: '',
      utc: now.toUtc(),
      utcOffset: now.timeZoneOffset,
      place: place,
      ownership: Ownership.forMe,
      personId: personId,
      draft: true,
      entered: true,
      precision: DatePrecision.unset,
    );

/// An entry opened and left with nothing in it: no date, no words, no title, names or tags.
bool isEmptyEntry(Blessing b) =>
    b.entered &&
    b.draft &&
    !b.placed &&
    b.rawText.trim().isEmpty &&
    Strings.isUntitled(b.title) &&
    b.from.isEmpty &&
    b.recipient.isEmpty &&
    b.tags.isEmpty;

/// [b] given on a date known to [p]; its light sits at noon of the day, the 15th, or July 2, on the
/// phone's clock for that date.
void setGiven(Blessing b, DatePrecision p, int year, [int month = 1, int day = 1]) {
  final at = givenAnchor(p, year, month, day);
  b
    ..precision = p
    ..utcOffset = at.timeZoneOffset
    ..utc = at.toUtc();
}

/// The sample blessings' home (data/samples.dart and tests). Real recordings never use it.
const samplePlace = Place(40.23, -111.66);
