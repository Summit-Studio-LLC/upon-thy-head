import 'change.dart';
import 'words.dart';

/// Something that proposes changes to the spoken words. The rules below are the first; a model on
/// the phone could be another. Whatever the source, its changes are measured, stored, shown and
/// undone the same way (change.dart), and each must replace one stretch of the spoken words.
abstract class ChangeSource {
  /// Stored with each change it makes.
  String get name;

  /// Changes to [spoken] (in the language [language], "en" or "es"), in order, none overlapping.
  List<Change> find(String spoken, String language);
}

/// Cleanup by rule, on the phone: filler sounds left out and stumbled-over words said once. Nothing
/// else: no rewording, grammar or punctuation. When unsure, the words are left alone. The word lists
/// are in words.dart.
class PolishRules implements ChangeSource {
  const PolishRules();

  @override
  String get name => Change.rulesSource;

  @override
  List<Change> find(String spoken, String language) {
    final lang = rulesLanguage(language);
    final toks = [for (final m in wordPattern.allMatches(spoken)) _Tok(m.start, m.end, m.group(0)!)];
    final out = <Change>[];
    var i = 0;
    while (i < toks.length) {
      final c = _filler(spoken, toks, i, lang) ?? _betweenCommas(spoken, toks, i, lang) ?? _repeat(spoken, toks, i, lang);
      if (c == null) {
        i++;
        continue;
      }
      if (out.isEmpty || !out.last.overlaps(c.$1)) out.add(c.$1);
      i = c.$2;
    }
    return out;
  }

  // A word stands alone when nothing joins it to the next word (a hyphen, a slash): what is before
  // and after it is a space, the edge of the text, or ordinary punctuation.
  static final _before = RegExp(r'[\s"“‘(¿¡]');
  static final _after = RegExp(r'[\s,.;:!?…"”’)]');
  static final _terminal = RegExp(r'[.!?…]');

  static bool _alone(String s, int start, int end) =>
      (start == 0 || _before.hasMatch(s[start - 1])) && (end == s.length || _after.hasMatch(s[end]));

  /// Between two words: only spaces, with at most one comma (or semicolon), and no line break.
  static bool _softGap(String gap) => RegExp(r'^\s*[,;]?\s*$').hasMatch(gap) && !gap.contains('\n') && gap.isNotEmpty;

  /// A filler sound, or several in a row ("um, uh,"), left out with what it leaves behind: the
  /// comma after it, and a capital for the word that now begins the sentence. A comma or full stop
  /// before it stays: "head, um, to give" → "head, to give"; "your body, um." → "your body.".
  (Change, int)? _filler(String s, List<_Tok> t, int i, String lang) {
    final set = fillers[lang]!;
    if (!set.contains(t[i].lower) || !_alone(s, t[i].start, t[i].end)) return null;
    var k = i;
    while (k + 1 < t.length && set.contains(t[k + 1].lower) && _softGap(s.substring(t[k].end, t[k + 1].start)) && _alone(s, t[k + 1].start, t[k + 1].end)) {
      k++;
    }
    final runStart = t[i].start, runEnd = t[k].end;
    final prevEnd = i > 0 ? t[i - 1].end : null;
    final next = k + 1 < t.length ? t[k + 1] : null;
    final before = s.substring(prevEnd ?? 0, runStart);
    final after = s.substring(runEnd, next?.start ?? s.length);
    final startsSentence = prevEnd == null || _terminal.hasMatch(before) || before.contains('\n');
    final endsSentence = next == null || _terminal.hasMatch(after) || after.contains('\n');
    final Change c;
    if (endsSentence && !startsSentence && !RegExp(r'["“‘(¿¡]').hasMatch(before)) {
      // "body, um. Strength" → "body. Strength": what came before it up to the filler goes
      c = Change(start: prevEnd, was: s.substring(prevEnd, runEnd), now: '', kind: ChangeKind.filler);
    } else {
      final span = _afterSpan(after, stopAtNewline: startsSentence && endsSentence && after.contains('\n'));
      if (next != null && span == after.length && startsSentence && _lowerFirst(next.text)) {
        // "Um, your strength" → "Your strength"
        c = Change(start: runStart, was: s.substring(runStart, next.end), now: _capitalise(next.text), kind: ChangeKind.filler);
      } else {
        c = Change(start: runStart, was: s.substring(runStart, runEnd + span), now: '', kind: ChangeKind.filler);
      }
    }
    return (c, k + 1);
  }

  /// How far into [after] a filler at the start of a sentence may take with it: never across a
  /// line break when it also ends its sentence (so `\n\n` paragraph breaks stay), and never past an
  /// unpaired quote or bracket.
  static int _afterSpan(String after, {required bool stopAtNewline}) {
    var limit = after.length;
    if (stopAtNewline) {
      final nl = after.indexOf('\n');
      if (nl >= 0) {
        limit = nl;
        if (limit > 0 && after.codeUnitAt(limit - 1) == 0x0d) limit--;
      }
    }
    const pairs = {'“': '”', '‘': '’', '(': ')'};
    const closers = {'”', '’', ')'};
    final open = <String>[];
    for (var j = 0; j < limit; j++) {
      final ch = after[j];
      if (ch == '"' || ch == "'") {
        if (open.isNotEmpty && open.last == ch) {
          open.removeLast();
        } else if (after.substring(j + 1, limit).contains(ch)) {
          open.add(ch);
        } else {
          return j;
        }
      } else if (pairs.containsKey(ch)) {
        final close = pairs[ch]!;
        if (!after.substring(j + 1, limit).contains(close)) return j;
        open.add(close);
      } else if (closers.contains(ch)) {
        if (open.isEmpty || open.last != ch) return j;
        open.removeLast();
      } else if (ch == '¿' || ch == '¡') {
        return j;
      }
    }
    return limit;
  }

  /// "este", "you know" and the like, only when they stand alone between two commas:
  /// "y, este, te bendigo" → "y, te bendigo". The comma before them stays.
  (Change, int)? _betweenCommas(String s, List<_Tok> t, int i, String lang) {
    if (i == 0) return null;
    for (final phrase in fillersBetweenCommas[lang]!) {
      final words = phrase.split(' ');
      final k = i + words.length - 1;
      if (k + 1 >= t.length) continue;
      var match = true;
      for (var j = 0; j < words.length && match; j++) {
        match = t[i + j].lower == words[j] && (j == 0 || s.substring(t[i + j - 1].end, t[i + j].start) == ' ');
      }
      if (!match) continue;
      final before = s.substring(t[i - 1].end, t[i].start), after = s.substring(t[k].end, t[k + 1].start);
      if (!RegExp(r'^,\s+$').hasMatch(before) || !RegExp(r'^,\s+$').hasMatch(after)) continue;
      return (Change(start: t[i].start, was: s.substring(t[i].start, t[k + 1].start), now: '', kind: ChangeKind.filler), k + 1);
    }
    return null;
  }

  /// A short function word said twice or more ("with with", "I, I", "de de") said once.
  (Change, int)? _repeat(String s, List<_Tok> t, int i, String lang) {
    if (!repeatable[lang]!.contains(t[i].lower) || !_alone(s, t[i].start, t[i].end)) return null;
    var k = i;
    while (k + 1 < t.length && t[k + 1].lower == t[i].lower && _softGap(s.substring(t[k].end, t[k + 1].start)) && _alone(s, t[k + 1].start, t[k + 1].end)) {
      k++;
    }
    if (k == i) return null;
    return (Change(start: t[i].start, was: s.substring(t[i].start, t[k].end), now: t[i].text, kind: ChangeKind.repeat), k + 1);
  }

  static bool _lowerFirst(String w) {
    final f = String.fromCharCode(w.runes.first);
    return f != f.toUpperCase();
  }

  static String _capitalise(String w) {
    final f = String.fromCharCode(w.runes.first);
    return f.toUpperCase() + w.substring(f.length);
  }
}

class _Tok {
  _Tok(this.start, this.end, this.text) : lower = text.toLowerCase();
  final int start, end;
  final String text, lower;
}
