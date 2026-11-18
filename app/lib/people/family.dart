import '../data/blessing.dart';
import '../strings.dart';
import '../widgets/pull_down.dart';
import 'person.dart';

/// The rings kept on this phone: the person's own ('') and one for each family member, with the
/// blessings on each. Built from the store's lists; nothing here is stored.
class Family {
  Family(this.people, List<Blessing> onRings) {
    final known = {for (final p in people) p.id};
    for (final b in onRings) {
      if (b.ownership == Ownership.passingOn) continue;
      // a ring this phone does not know (never written by this app): kept with the person's own
      // rather than lost from sight
      final ring = known.contains(b.personId) ? b.personId : '';
      (_rings[ring] ??= []).add(b);
    }
    for (final l in _rings.values) {
      l.sort((a, b) => a.utc.compareTo(b.utc));
    }
  }

  /// In the order they were added.
  final List<Person> people;
  final Map<String, List<Blessing>> _rings = {};

  /// The blessings on [ring], oldest first.
  List<Blessing> on(String ring) => [...?_rings[ring]];


  Person? person(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// [ring] when it is the person's own or a family member's still here; else the person's own.
  String known(String ring) => ring.isEmpty || person(ring) == null ? '' : ring;

  /// "For me", "For Emma".
  String title(String ring) {
    final p = ring.isEmpty ? null : person(ring);
    return p == null ? Strings.forMe : Strings.forPerson(p.name);
  }

  /// The menu under the capsule: "For me" and each family member with their count line, the one
  /// showing ticked; then "Add a family member" and "Manage family".
  /// (Drafts waiting are not counted here: the badge on home says so.)
  List<PullDownItem> menu(String showing) {
    String sub(String ring) => countLine(on(ring));

    return [
      PullDownItem(code: SkyMenu.me, label: Strings.forMe, sub: sub(''), ticked: showing.isEmpty),
      for (final p in people)
        PullDownItem(code: SkyMenu.person(p.id), label: Strings.forPerson(p.name), sub: sub(p.id), ticked: showing == p.id),
      PullDownItem(code: SkyMenu.add, label: Strings.addFamilyMember, mark: PullDownMark.plus, groupStart: true),
      if (people.isNotEmpty) PullDownItem(code: SkyMenu.manage, label: Strings.manageFamily),
    ];
  }
}

/// The codes of the sky menu's rows.
abstract final class SkyMenu {
  static const me = 'me', add = 'add', manage = 'manage';
  static String person(String id) => 'p:$id';

  /// The ring a row chose ('' for mine), or null for a row that is not a ring.
  static String? ringOf(String code) => code == me ? '' : (code.startsWith('p:') ? code.substring(2) : null);
}

/// "Five blessings since June 2024".
String countLine(List<Blessing> blessings) {
  if (blessings.isEmpty) return Strings.countLine(0, DateTime(0));
  final first = blessings.map((b) => b.local).reduce((a, b) => a.isBefore(b) ? a : b);
  return Strings.countLine(blessings.length, first);
}
