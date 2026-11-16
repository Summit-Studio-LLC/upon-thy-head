/// The rules for a blessing's tags, kept apart from the page so they can be tested alone.
///
/// A tag is a short word or phrase. Spaces are tidied, its first letter is made a capital
/// ("healing" becomes "Healing"; later words are left as typed), and two tags that differ only in
/// capitals are the same tag (the first one written wins).
class TagRules {
  const TagRules._();

  /// The longest tag kept, in characters.
  static const maxLength = 40;

  /// [raw] tidied: no spaces at the ends, single spaces inside, no leading '#', no commas at the
  /// ends, a capital first letter; '' when nothing is left.
  static String clean(String raw) {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^[#,\s]+|[,\s]+$'), '');
    if (t.length > maxLength) t = t.substring(0, maxLength).trimRight();
    return capitalise(t);
  }

  /// [t] with its first letter a capital; the rest as it is.
  static String capitalise(String t) {
    if (t.isEmpty) return t;
    final first = String.fromCharCode(t.runes.first);
    return first.toUpperCase() + t.substring(first.length);
  }

  static bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// [tags] with what was typed added at the end. A comma separates several at once.
  /// Empty or repeated tags are not added. [tags] itself is not changed.
  static List<String> add(List<String> tags, String typed) {
    final out = [...tags];
    for (final part in typed.split(',')) {
      final t = clean(part);
      if (t.isEmpty || out.any((x) => same(x, t))) continue;
      out.add(t);
    }
    return out;
  }

  /// [tags] without [tag] (in any capitals).
  static List<String> remove(List<String> tags, String tag) => [for (final t in tags) if (!same(t, tag)) t];

  /// Tags used on other blessings ([known], most used first) worth offering: not already on this
  /// one, and, once something is typed, those that start with it (or have a word that does).
  static List<String> suggest(List<String> known, List<String> current, String typed, {int max = 6}) {
    final q = clean(typed).toLowerCase();
    final out = <String>[];
    for (final k in known) {
      if (out.length >= max) break;
      if (current.any((c) => same(c, k)) || out.any((o) => same(o, k))) continue;
      final lower = k.toLowerCase();
      if (q.isNotEmpty && !lower.startsWith(q) && !lower.split(' ').any((w) => w.startsWith(q))) continue;
      out.add(k);
    }
    return out;
  }
}
