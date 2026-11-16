import 'dart:math' as math;

import 'words.dart';

/// How large a change is, measured from the words before and after it (see [measureSize]); never
/// declared by whatever made the change.
enum ChangeSize {
  light('light'),
  moderate('moderate'),
  heavy('heavy');

  const ChangeSize(this.code);
  final String code;
}

/// What kind of change it is. The rules make only the first two; other sources of changes (an
/// on-device model, later) may make the rest. Stored by [code]; the words shown are in Strings.
enum ChangeKind {
  filler('filler'),
  repeat('repeat'),
  reworded('reworded'),
  grammar('grammar'),
  punctuation('punctuation');

  const ChangeKind(this.code);
  final String code;

  static ChangeKind fromCode(String code) => values.firstWhere((k) => k.code == code, orElse: () => reworded);
}

/// One change polish proposes to the spoken words: the words at [start] in the spoken words ([was])
/// and what replaces them ([now], '' when they are left out). The person keeps it or restores the
/// original; the polished words are the spoken words with the kept changes applied.
///
/// The span [start, end) covers everything the change touches, including whatever it tidies (the
/// comma after a removed "um", the capital of the word that now starts a sentence), so a change is
/// always one replacement and restoring it gives back the spoken words exactly.
class Change {
  Change({required this.start, required this.was, required this.now, required this.kind, this.source = rulesSource, this.kept = true})
      : assert(was.isNotEmpty);

  /// Where it sits in the spoken words (UTF-16 offset), and the words it replaces there.
  int start;
  final String was;

  /// What replaces them; '' when they are left out.
  final String now;
  final ChangeKind kind;

  /// What made it: [rulesSource] for the rules in this app; other sources name themselves.
  final String source;

  /// Kept (applied to the polished words) or restored (the spoken words stand here).
  bool kept;

  static const rulesSource = 'rules';

  int get end => start + was.length;

  /// Measured from [was] and [now].
  ChangeSize get size => measureSize(was, now);

  bool overlaps(Change o) => start < o.end && o.start < end;

  Change copy({int? start, bool? kept}) =>
      Change(start: start ?? this.start, was: was, now: now, kind: kind, source: source, kept: kept ?? this.kept);

  /// The original words as the sheet shows them: without the spaces at the ends, and without the
  /// commas a removal also took away.
  String get shownWas => _shown(was, trimCommas: now.isEmpty);
  String get shownNow => _shown(now, trimCommas: false);

  static String _shown(String s, {required bool trimCommas}) {
    var t = s.trim();
    if (trimCommas) t = t.replaceAll(RegExp(r'^[\s,;:]+|[\s,;:]+$'), '');
    return t.isEmpty ? s.trim() : t;
  }

  @override
  String toString() => 'Change($start, "$was" → "$now", ${kind.code}, ${kept ? 'kept' : 'restored'})';
}

/// The spoken words with the kept changes applied. Changes must not overlap.
String applyChanges(String spoken, List<Change> changes) {
  final kept = [for (final c in changes) if (c.kept) c]..sort((a, b) => a.start.compareTo(b.start));
  final out = StringBuffer();
  var at = 0;
  for (final c in kept) {
    if (c.start < at || c.end > spoken.length || spoken.substring(c.start, c.end) != c.was) continue;
    out
      ..write(spoken.substring(at, c.start))
      ..write(c.now);
    at = c.end;
  }
  out.write(spoken.substring(at));
  return out.toString();
}

/// How large the change from [was] to [now] is, by the words in them:
///  - only words left out, at most two of them besides filler sounds: light;
///  - only words left out, more than that: moderate;
///  - words replaced or added, five word-steps or fewer (a word in, out or swapped): moderate;
///  - more: heavy.
/// The sample's five changes measure as the prototype shows them: light, moderate, light,
/// moderate, heavy.
ChangeSize measureSize(String was, String now) {
  final a = wordsOf(was), b = wordsOf(now);
  if (_isSubsequence(b, a)) {
    final fillersLeftOut = a.where(isAnyFiller).length - b.where(isAnyFiller).length;
    final leftOut = a.length - b.length - math.max(0, fillersLeftOut);
    return leftOut <= 2 ? ChangeSize.light : ChangeSize.moderate;
  }
  return _wordDistance(a, b) <= 5 ? ChangeSize.moderate : ChangeSize.heavy;
}

/// The words of [s], lower case, without punctuation.
List<String> wordsOf(String s) => [for (final m in wordPattern.allMatches(s)) m.group(0)!.toLowerCase()];

bool _isSubsequence(List<String> small, List<String> big) {
  var i = 0;
  for (final w in big) {
    if (i < small.length && small[i] == w) i++;
  }
  return i == small.length;
}

int _wordDistance(List<String> a, List<String> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

/// The changes after the spoken words were corrected by hand from [before] to [after]: a change
/// whose words are still there, untouched, moves with them and keeps its state; one whose words
/// were edited is dropped.
List<Change> rebaseChanges(String before, String after, List<Change> changes) {
  if (before == after) return [for (final c in changes) c.copy()];
  // the edit: what lies between the longest common start and the longest common end
  var p = 0;
  final most = math.min(before.length, after.length);
  while (p < most && before.codeUnitAt(p) == after.codeUnitAt(p)) {
    p++;
  }
  var s = 0;
  while (s < most - p && before.codeUnitAt(before.length - 1 - s) == after.codeUnitAt(after.length - 1 - s)) {
    s++;
  }
  final oldEnd = before.length - s, delta = after.length - before.length;
  final out = <Change>[];
  for (final c in changes) {
    final int start;
    if (c.end <= p) {
      start = c.start;
    } else if (c.start >= oldEnd) {
      start = c.start + delta;
    } else {
      continue; // its words were edited
    }
    if (start < 0 || start + c.was.length > after.length || after.substring(start, start + c.was.length) != c.was) continue;
    // a word typed onto its edge makes it part of another word: its words are no longer untouched
    bool sameEdge(int oldAt, int newAt) =>
        (oldAt < 0 || oldAt >= before.length ? null : before[oldAt]) == (newAt < 0 || newAt >= after.length ? null : after[newAt]);
    if (!sameEdge(c.start - 1, start - 1) || !sameEdge(c.end, start + c.was.length)) continue;
    out.add(c.copy(start: start));
  }
  return out;
}

/// [existing] with each of [found] added (kept) that touches none of them.
List<Change> mergeChanges(List<Change> existing, List<Change> found) {
  final out = [for (final c in existing) c];
  for (final f in found) {
    if (out.any((c) => c.overlaps(f))) continue;
    out.add(f.copy(kept: true));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The kind an earlier polish named in words ("Filler removed", "Reworded", ...).
ChangeKind kindOfLegacy(String what) => switch (what) {
      'Filler removed' => ChangeKind.filler,
      'Repeated word removed' => ChangeKind.repeat,
      _ => ChangeKind.reworded,
    };

/// Changes given as words and replacements with no positions (as earlier versions stored them),
/// placed in [spoken]: each is found after the one before it. One that cannot be found, or would
/// overlap another, is left out. All are kept, as they were applied before.
List<Change> locateChanges(String spoken, List<({ChangeKind kind, String was, String now})> edits, {String source = 'earlier'}) {
  final out = <Change>[];
  var from = 0;
  for (final e in edits) {
    if (e.was.isEmpty) continue;
    final at = spoken.indexOf(e.was, from);
    if (at < 0) continue;
    out.add(Change(start: at, was: e.was, now: e.now, kind: e.kind, source: source));
    from = at + e.was.length;
  }
  return out;
}
