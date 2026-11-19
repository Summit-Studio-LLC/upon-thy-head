import '../data/blessing.dart';

/// A family member whose blessings are kept on this phone: a child, most often, without a phone of
/// their own. Each has a ring of their own in a sky of their own (design/entry-and-rings, B1).
///
/// The id is 128 random bits, made once on this phone and never changed, so a later round can hand
/// a person's whole ring to another phone and join two parents' copies of the same child by it.
class Person {
  Person({required this.id, required this.name, this.born, this.handed, DateTime? created})
      : created = created ?? DateTime.now().toUtc();

  final String id;

  /// As typed, trimmed. Never empty.
  String name;

  /// The day they were born, as a calendar day (no time, no zone): their ring begins on it.
  /// Optional.
  Day? born;

  /// When their ring was last handed over to their own phone (share/ring_file.dart), sent through
  /// the share sheet; null when it never has been. Their page says "Handed to Emma on November 16".
  DateTime? handed;

  /// When they were added here (UTC); the menu lists them in this order.
  final DateTime created;

  Person copy() => Person(id: id, name: name, born: born, handed: handed, created: created);
}

/// A calendar day, the same wherever the phone is.
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  final int year, month, day;

  factory Day.of(DateTime d) => Day(d.year, d.month, d.day);

  /// "2008-08-03", as the store keeps it; null when [s] is not one.
  static Day? parse(String? s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s ?? '');
    if (m == null) return null;
    final d = Day(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    final check = DateTime(d.year, d.month, d.day);
    return check.year == d.year && check.month == d.month && check.day == d.day ? d : null;
  }

  /// Midnight at the start of the day, on this phone's clock.
  DateTime get local => DateTime(year, month, day);

  String get code => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(Day other) => code.compareTo(other.code);

  @override
  bool operator ==(Object other) => other is Day && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// A new family member with a new id.
Person newPerson(String name, {Day? born}) => Person(id: newBlessingId(), name: cleanName(name), born: born);

/// The longest name kept, in characters.
const int nameLimit = 60;

/// A name as it is kept: spaces at either end and runs of spaces inside are tidied, and it is cut
/// at [nameLimit].
String cleanName(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  final chars = t.runes.toList();
  return chars.length <= nameLimit ? t : String.fromCharCodes(chars.take(nameLimit)).trim();
}

/// Whose a blessing is: mine (the person keeping the record), one family member's, or one being
/// passed along to someone without a ring here.
sealed class Whose {
  const Whose();

  static const Whose me = WhoseMe._();
  static const Whose passing = WhosePassing._();
  static Whose of(String personId) => personId.isEmpty ? me : WhosePerson(personId);

  /// The blessing's own.
  static Whose ofBlessing(Blessing b) => b.ownership == Ownership.passingOn ? passing : of(b.personId);

  /// The ring it belongs to ('' for mine); null when it has none (passed along).
  String? get ring;

  /// Write onto [b].
  void apply(Blessing b) {
    final r = ring;
    if (r == null) {
      b
        ..ownership = Ownership.passingOn
        ..personId = '';
    } else {
      b
        ..ownership = Ownership.forMe
        ..personId = r;
    }
  }
}

final class WhoseMe extends Whose {
  const WhoseMe._();
  @override
  String get ring => '';
  @override
  bool operator ==(Object other) => other is WhoseMe;
  @override
  int get hashCode => 1;
}

final class WhosePassing extends Whose {
  const WhosePassing._();
  @override
  String? get ring => null;
  @override
  bool operator ==(Object other) => other is WhosePassing;
  @override
  int get hashCode => 2;
}

final class WhosePerson extends Whose {
  const WhosePerson(this.id);
  final String id;
  @override
  String get ring => id;
  @override
  bool operator ==(Object other) => other is WhosePerson && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// The "For" name on review after whose blessing it is changes to [to]. Chosen for a family member
/// with the field empty, it takes their name; switched away while it still holds only the name put
/// there that way ([filled]), it is cleared first. A name typed by the person is never touched.
/// Returns the field's words and the name now filled in (null when it is no longer one).
({String text, String? filled}) forAfterWhose({required String text, required String? filled, required Whose to, required List<Person> people}) {
  var t = text;
  String? f;
  if (filled != null && t.trim() == filled) t = '';
  if (to is WhosePerson && t.trim().isEmpty) {
    for (final p in people) {
      if (p.id == to.id) {
        t = p.name;
        f = p.name;
      }
    }
  }
  return (text: t, filled: f);
}
