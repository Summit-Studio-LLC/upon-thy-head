import 'dart:math' as math;

import '../polish/change.dart';
import '../sky/astro.dart';
import '../strings.dart';

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

  String get longDate => Strings.longDate(local);

  /// "Mar 3, 2026"
  String get shortDate => Strings.shortDate(local);
}

final _random = math.Random.secure();

/// A new random id: 128 bits as hex.
String newBlessingId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// A new blessing as its recording starts: given now, at [place] ("the place blessings are given",
/// place/where.dart), for me.
Blessing draftBlessing(DateTime now, {required Place place}) => Blessing(
      id: newBlessingId(),
      title: Strings.untitled,
      from: '',
      utc: now.toUtc(),
      utcOffset: now.timeZoneOffset,
      place: place,
      ownership: Ownership.forMe,
      draft: true,
    );

/// The sample blessings' home (data/samples.dart and tests). Real recordings never use it.
const samplePlace = Place(40.23, -111.66);
