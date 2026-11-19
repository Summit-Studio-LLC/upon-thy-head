import '../data/blessing.dart';
import '../data/store.dart';
import '../sky/astro.dart';
import 'receive.dart';

/// Handing a family member's ring to their own phone (design/entry-and-rings, B1 rows 9–16): the
/// parts that are not screens. The bundle is ring_file.dart; the link is Links.makeRing.

/// The "Kept by" name the sending sheet starts with: the one typed last time; else the From name
/// most of [ring] carry (on a tie, the one met first, oldest first); else ''.
String suggestedKeptBy(Iterable<Blessing> ring, {String? remembered}) {
  final r = remembered?.trim() ?? '';
  if (r.isNotEmpty) return r;
  final counts = <String, int>{};
  final list = [...ring]..sort((a, b) => a.utc.compareTo(b.utc));
  for (final b in list) {
    final f = b.from.trim();
    if (f.isNotEmpty) counts[f] = (counts[f] ?? 0) + 1;
  }
  String best = '';
  var most = 0;
  counts.forEach((name, n) {
    if (n > most) {
      best = name;
      most = n;
    }
  });
  return best;
}

/// Keep them: each blessing of [a] this phone does not have joins the person's own ring ("For me")
/// by its date, kept by the ring's sender. One the phone has meanwhile come to have is kept once,
/// as it is. Answers the ids kept, oldest first.
Future<List<String>> keepRing(BlessingStore store, ArrivalRing a, {required Place place, DateTime? now}) async {
  final kept = <String>[];
  for (final r in a.fresh) {
    if (await store.get(r.id) != null) continue;
    final b = r.toBlessing(place: place, now: now, keptBy: a.ring.keptBy)
      ..ownership = Ownership.forMe
      ..personId = '';
    await store.create(b);
    kept.add(b.id);
  }
  return kept;
}
