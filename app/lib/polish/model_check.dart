import 'dart:math' as math;

import 'change.dart';
import 'words.dart';

/// The check every suggestion from a model on the phone goes through (model.dart). The model is not
/// trusted: its text is compared with the spoken words, word by word, and turned into changes, and
/// a change is kept only if it is one of the kinds allowed:
///  - punctuation and capital letters;
///  - paragraph breaks;
///  - one word that was plainly misheard, replaced by one word ("there" for "their", or a name
///    spelled as the blessing's own details spell it).
/// Anything else is thrown away without a word to the person: words added, left out or moved, a
/// phrase for a phrase, a number or a name changed, and every change to scripture language. A piece
/// that comes back mostly rewritten is thrown away whole.
class ModelCheck {
  const ModelCheck._();

  /// Below this share of the spoken words coming back unchanged (capitals and accents aside), the
  /// piece is taken as rewritten and none of it is used.
  static const keepAtLeast = .7;

  /// The changes [suggested] makes to [spoken] that pass the check, at offsets in [spoken] plus
  /// [offset]. [names] are the words of the blessing's own details (who gave it, who it was for, its
  /// title, the family member's name), against which a corrected name is checked.
  static List<Change> changes(String spoken, String suggested, {required String language, Set<String> names = const {}, int offset = 0, String source = 'model'}) {
    final lang = rulesLanguage(language);
    final text = stripWrapping(suggested);
    final a = _tokens(spoken), b = _tokens(text);
    if (a.isEmpty || b.isEmpty) return const [];
    final ops = _align(a, b);
    final same = ops.where((o) => o.kind == _Op.same || o.kind == _Op.swap && _fold(a[o.i].text) == _fold(b[o.j].text)).length;
    if (same / math.max(a.length, b.length) < keepAtLeast) return const [];

    final nameSet = {for (final n in names) _fold(n)};
    // Each spoken word i gets a decision: its replacement (null: unchanged), and whether it borders
    // a word added or left out (then the gaps beside it stay as spoken).
    final word = List<String?>.filled(a.length, null);
    final rough = List<bool>.filled(a.length, false);
    // for each spoken word, the matching word in the suggestion (or -1)
    final pair = List<int>.filled(a.length, -1);
    for (var k = 0; k < ops.length; k++) {
      final o = ops[k];
      switch (o.kind) {
        case _Op.same:
          pair[o.i] = o.j;
          if (a[o.i].text != b[o.j].text && _capitalOk(spoken, text, a, b, o.i, o.j)) word[o.i] = b[o.j].text;
        case _Op.swap:
          pair[o.i] = o.j;
          final before = o.i == 0 ? null : spoken.substring(a[o.i - 1].end, a[o.i].start);
          if (_swapOk(a[o.i].text, b[o.j].text, lang, nameSet, before)) {
            word[o.i] = b[o.j].text;
          } else {
            rough[o.i] = true;
          }
        case _Op.added:
        case _Op.removed:
          // the spoken words either side keep their gaps
          if (o.i >= 0 && o.i < a.length) rough[o.i] = true;
          if (o.i - 1 >= 0) rough[o.i - 1] = true;
      }
    }

    // The gap after spoken word i (i = -1: before the first word), as spoken and as suggested.
    String spokenGap(int i) => spoken.substring(i < 0 ? 0 : a[i].end, i + 1 < a.length ? a[i + 1].start : spoken.length);
    String? suggestedGap(int i) {
      final l = i < 0 ? -1 : pair[i], r = i + 1 < a.length ? pair[i + 1] : b.length;
      if (i >= 0 && l < 0 || i + 1 < a.length && r < 0) return null;
      if (r != l + 1) return null; // a word was added between them
      return text.substring(l < 0 ? 0 : b[l].end, r < b.length ? b[r].start : text.length);
    }

    final gap = List<String?>.filled(a.length + 1, null); // gap[i + 1]: after word i
    for (var i = -1; i < a.length; i++) {
      if (i >= 0 && rough[i] || i + 1 < a.length && rough[i + 1]) continue;
      final was = spokenGap(i);
      final now = suggestedGap(i);
      if (now == null) continue;
      final g = _gapOk(was, now, edge: i < 0 || i + 1 >= a.length);
      if (g != null && g != was) gap[i + 1] = g;
    }

    // What changed, in order (gap 0, word 0, gap 1, word 1, ... gap n), each with the spoken words it
    // touches; those that share a word are one change, from the start of its first word to the end
    // of its last.
    final n = a.length;
    final runs = <List<int>>[]; // [lo, hi] word indices
    void touch(int lo, int hi) {
      lo = math.max(lo, 0);
      hi = math.min(hi, n - 1);
      if (runs.isNotEmpty && lo <= runs.last[1]) {
        runs.last[1] = math.max(runs.last[1], hi);
      } else {
        runs.add([lo, hi]);
      }
    }

    for (var g = 0; g <= n; g++) {
      if (gap[g] != null) touch(g - 1, g);
      if (g < n && word[g] != null) touch(g, g);
    }
    final out = <Change>[];
    for (final r in runs) {
      final lo = r[0], hi = r[1];
      final lead = lo == 0 && gap[0] != null, trail = hi == n - 1 && gap[n] != null;
      final from = lead ? 0 : a[lo].start, to = trail ? spoken.length : a[hi].end;
      final now = StringBuffer();
      if (lead) now.write(gap[0]);
      var touchesWord = false;
      for (var w = lo; w <= hi; w++) {
        now.write(word[w] ?? a[w].text);
        if (word[w] != null && _fold(word[w]!) != _fold(a[w].text)) touchesWord = true;
        if (word[w] != null && _fold(word[w]!) == _fold(a[w].text) && word[w]!.toLowerCase() != a[w].text.toLowerCase()) touchesWord = true;
        if (w < hi) now.write(gap[w + 1] ?? spokenGap(w));
      }
      if (trail) now.write(gap[n]);
      final was = spoken.substring(from, to), next = now.toString();
      if (next == was || was.isEmpty) continue;
      out.add(Change(start: offset + from, was: was, now: next, kind: touchesWord ? ChangeKind.grammar : ChangeKind.punctuation, source: source));
    }
    return out;
  }

  /// [s] without what a model sometimes puts around its answer: a line introducing it ("Here is the
  /// corrected text:"), quotation marks or a code fence around all of it, and a note after it.
  static String stripWrapping(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'^```[a-z]*\s*|\s*```$'), '');
    final lines = t.split('\n');
    if (lines.length > 1) {
      final head = lines.first.trim();
      if (_intro.hasMatch(head) || (head.endsWith(':') && wordsOf(head).length <= 12)) {
        t = lines.skip(1).join('\n').trim();
      }
    } else {
      final m = RegExp(r'^[^\n:]{0,80}:\s+').firstMatch(t);
      if (m != null && _intro.hasMatch(m.group(0)!)) t = t.substring(m.end).trim();
    }
    // a note after a blank line ("Note: ...", "I have corrected ...")
    final notes = RegExp(r'\n\s*\n\s*(\(?(note|nota)\b|i (have|made|corrected|changed|added|kept)|he (corregido|cambiado|añadido|mantenido))', caseSensitive: false).firstMatch(t);
    if (notes != null) t = t.substring(0, notes.start).trim();
    // quotation marks around the whole answer, when the inside holds none
    for (final (open, close) in const [('"', '"'), ('“', '”'), ('«', '»')]) {
      if (t.length > 2 && t.startsWith(open) && t.endsWith(close)) {
        final inside = t.substring(open.length, t.length - close.length);
        if (!inside.contains(open) && !inside.contains(close)) t = inside.trim();
      }
    }
    return t;
  }

  static final _intro = RegExp(
    r'^(here|below|sure|certainly|of course|the corrected|corrected|aquí|a continuación|claro|por supuesto|el texto corregido|texto corregido)\b.*(text|transcript|version|texto|transcripción|versión)?.*:\s*$',
    caseSensitive: false,
  );

  /// A gap as suggested, made the app's way, or null when it is not punctuation and spacing only.
  /// A line break becomes a blank line (the app's paragraph); a paragraph already in the spoken
  /// words stays.
  static String? _gapOk(String was, String now, {required bool edge}) {
    if (!_gapChars.hasMatch(now)) return null;
    if (was.contains('\n') && !now.contains('\n')) return null; // a paragraph is never joined
    var g = now.replaceAll(RegExp(r'[ \t]+'), ' ');
    if (g.contains('\n')) {
      // the punctuation before the break, a blank line, the punctuation after
      final before = g.substring(0, g.indexOf('\n')).trimRight();
      final after = g.substring(g.lastIndexOf('\n') + 1).trimLeft();
      g = '$before\n\n$after';
    }
    if (edge) g = g.trim();
    if (!edge && g.isEmpty && was.isNotEmpty) return null; // two words run together
    return g;
  }

  // punctuation and spaces only: no letters, digits, markup or symbols
  static final _gapChars = RegExp(r'^[\s.,;:!?¿¡…"“”‘’«»()\-–—]*$');

  /// A change of capital letters only, on words that are otherwise the same. Taking away a capital
  /// is allowed only from a word that, in the suggestion, does not begin a sentence, and never from
  /// "I" or from a name in the middle of a sentence.
  static bool _capitalOk(String spoken, String text, List<_Tok> a, List<_Tok> b, int i, int j) {
    final was = a[i].text, now = b[j].text;
    if (_fold(was) != _fold(now)) return false;
    if (_norm(was) == _norm(now)) return false; // only the apostrophe differs: leave it
    if (was.toLowerCase() != now.toLowerCase()) return false;
    final lowered = _upperCount(now) < _upperCount(was);
    if (!lowered) return true;
    if (was == 'I' || was.startsWith("I'") || was.startsWith('I’')) return false;
    // a capital mid-sentence in the spoken words is likely a name or the Lord's: it stays
    final startsSpoken = i == 0 || _sentenceBreak(spoken.substring(a[i - 1].end, a[i].start));
    return startsSpoken && !(j == 0 || _sentenceBreak(text.substring(b[j - 1].end, b[j].start)));
  }

  static bool _sentenceBreak(String gap) => RegExp(r'[.!?…]').hasMatch(gap) || gap.contains('\n');

  static int _upperCount(String w) => w.runes.where((r) {
    final c = String.fromCharCode(r);
    return c != c.toLowerCase();
  }).length;

  /// One word for another: allowed when it was plainly misheard, and it is no number, no scripture
  /// word, and no name the blessing's details do not hold.
  /// [before] is the spoken gap before the word, null at the start.
  static bool _swapOk(String was, String now, String lang, Set<String> names, String? before) {
    final w = _fold(was), n = _fold(now);
    if (w == n) return true; // only accents: "esta" → "está"
    if (isScripture(was, lang) || isScripture(now, lang)) return false;
    if (isNumber(was) || isNumber(now)) return false;
    final nameNow = names.contains(n);
    final wasName = names.contains(w);
    if (wasName) return false; // a name as the details spell it stays
    // a capital word that is not at a sentence start is a name; it may change only to a name in the
    // details
    final capNow = _startsUpper(now), capWas = _startsUpper(was) && was != 'I';
    final midSentence = before != null && !_sentenceBreak(before);
    if ((capNow || capWas) && midSentence && !nameNow) return false;
    if (nameNow) return _distance(w, n) <= math.max(2, (math.max(w.length, n.length) * .5).floor());
    if (homophones[lang]!.any((set) => set.contains(w) && set.contains(n))) return true;
    final d = _distance(w, n), len = math.max(w.length, n.length);
    return d <= 1 && len >= 3 || d <= 2 && len >= 5 && d / len <= .34;
  }

  static bool _startsUpper(String w) {
    final f = String.fromCharCode(w.runes.first);
    return f != f.toLowerCase();
  }

  /// Scripture language that must come through untouched (in either direction).
  static bool isScripture(String word, String lang) {
    final w = _norm(word).toLowerCase();
    if (scripture[lang]!.contains(w) || scripture.values.any((s) => s.contains(w))) return true;
    if (lang == 'en' || RegExp(r'^[a-z]+$').hasMatch(w)) {
      // -eth and -est verb forms: "giveth", "knowest", "blesseth"
      if (w.length > 4 && (w.endsWith('eth') || w.endsWith('est'))) return true;
    }
    if (lang == 'es') {
      // the vosotros verb forms: "tenéis", "sois", "estáis", "habéis", "fuisteis"
      if (w.length > 3 && RegExp(r'(áis|éis|ais|eis|ís)$').hasMatch(w)) return true;
    }
    return false;
  }

  /// A number, in figures or in words.
  static bool isNumber(String word) {
    final w = _fold(word);
    return RegExp(r'\d').hasMatch(w) || numberWords.contains(w);
  }

  /// Lower case, without accents, with one kind of apostrophe.
  static String _fold(String s) {
    var t = _norm(s).toLowerCase();
    const from = 'áàâäãéèêëíìîïóòôöõúùûüñç', to = 'aaaaaeeeeiiiiooooouuuunc';
    final out = StringBuffer();
    for (final r in t.runes) {
      final c = String.fromCharCode(r);
      final k = from.indexOf(c);
      out.write(k >= 0 ? to[k] : c);
    }
    t = out.toString();
    return t;
  }

  static String _norm(String s) => s.replaceAll('’', "'");

  static int _distance(String a, String b) {
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

  static List<_Tok> _tokens(String s) => [for (final m in wordPattern.allMatches(s)) _Tok(m.start, m.end, m.group(0)!)];

  /// The two lists of words lined up: the same word (capitals and accents aside), one word for
  /// another, a word added, a word left out. Fewest steps; the same word preferred.
  static List<_Step> _align(List<_Tok> a, List<_Tok> b) {
    final n = a.length, m = b.length;
    final fa = [for (final t in a) _fold(t.text)], fb = [for (final t in b) _fold(t.text)];
    // cost table, row by row (n and m are small: a piece is a few hundred words at most)
    final cost = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      cost[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      cost[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final same = fa[i - 1] == fb[j - 1] || _norm(a[i - 1].text).toLowerCase() == _norm(b[j - 1].text).toLowerCase();
        cost[i][j] = math.min(math.min(cost[i - 1][j] + 1, cost[i][j - 1] + 1), cost[i - 1][j - 1] + (same ? 0 : 1));
      }
    }
    final out = <_Step>[];
    var i = n, j = m;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        final same = fa[i - 1] == fb[j - 1];
        if (same && cost[i][j] == cost[i - 1][j - 1]) {
          // accents differ but the letters fold the same: treat as one word for another, checked
          final exact = a[i - 1].text.toLowerCase() == b[j - 1].text.toLowerCase() || _norm(a[i - 1].text).toLowerCase() == _norm(b[j - 1].text).toLowerCase();
          out.add(_Step(exact ? _Op.same : _Op.swap, i - 1, j - 1));
          i--;
          j--;
          continue;
        }
        if (!same && cost[i][j] == cost[i - 1][j - 1] + 1) {
          out.add(_Step(_Op.swap, i - 1, j - 1));
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
        out.add(_Step(_Op.removed, i - 1, -1));
        i--;
      } else {
        // a word added before spoken word i
        out.add(_Step(_Op.added, i, j - 1));
        j--;
      }
    }
    return out.reversed.toList();
  }

  /// Old words of scripture, kept exactly as spoken.
  static const Map<String, Set<String>> scripture = {
    'en': {
      'thee', 'thou', 'thy', 'thine', 'ye', 'unto', 'hast', 'hath', 'art', 'shalt', 'shall', 'doth', //
      'dost', 'wilt', 'canst', 'couldst', 'wouldst', 'shouldst', 'mayest', 'mightest', 'wast', 'wert', //
      'saith', 'spake', 'ere', 'hither', 'thither', 'whither', 'wherefore', 'whence', 'yea', 'nay', //
      'verily', 'behold', 'lo', 'amen', 'thyself', 'yourselves', 'mine', 'hearken', 'naught', 'aught',
    },
    'es': {
      'vosotros', 'vosotras', 'os', 'vuestro', 'vuestra', 'vuestros', 'vuestras', 'vos', //
      'sois', 'sed', 'id', 'venid', 'amad', 'oíd', 'mirad', 'bendecid', 'guardad', 'orad', 'buscad', //
      'recibid', 'escuchad', 'haced', 'andad', 'tened', 'sabed', 'he', 'aquí', 'amén', 'empero', 'mas',
    },
  };

  /// Words a recogniser often writes for one another because they sound alike.
  static const Map<String, List<Set<String>>> homophones = {
    'en': [
      {'there', 'their', "they're"},
      {'your', "you're"},
      {'its', "it's"},
      {'to', 'too'},
      {'here', 'hear'},
      {'whole', 'hole'},
      {'peace', 'piece'},
      {'prophet', 'profit'},
      {'pray', 'prey'},
      {'morning', 'mourning'},
      {'know', 'no'},
      {'knew', 'new'},
      {'right', 'write', 'rite'},
      {'whose', "who's"},
      {'weather', 'whether'},
      {'heal', 'heel'},
      {'soul', 'sole'},
      {'patience', 'patients'},
      {'presence', 'presents'},
      {'role', 'roll'},
      {'wait', 'weight'},
      {'week', 'weak'},
    ],
    'es': [
      {'haya', 'halla', 'aya'},
      {'hay', 'ay', 'ahí'},
      {'echo', 'hecho'},
      {'tuvo', 'tubo'},
      {'vaya', 'valla', 'baya'},
      {'votar', 'botar'},
      {'hola', 'ola'},
      {'si', 'sí'},
      {'el', 'él'},
      {'tu', 'tú'},
      {'mi', 'mí'},
      {'se', 'sé'},
      {'te', 'té'},
      {'mas', 'más'},
      {'aun', 'aún'},
      {'solo', 'sólo'},
      {'que', 'qué'},
      {'como', 'cómo'},
      {'donde', 'dónde'},
      {'cuando', 'cuándo'},
    ],
  };

  /// Numbers in words, English and Spanish, folded (no accents).
  static const Set<String> numberWords = {
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', //
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', //
    'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand', 'million', //
    'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'twice', 'once',
    'cero', 'uno', 'una', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez',
    /* 'once' is in the English list */
    //
    'doce', 'trece', 'catorce', 'quince', 'dieciseis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte', //
    'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa', 'cien', 'ciento', 'mil', //
    'millon', 'primero', 'primera', 'segundo', 'segunda', 'tercero', 'tercera', 'cuarto', 'cuarta', 'quinto',
  };
}

enum _Op { same, swap, added, removed }

class _Step {
  _Step(this.kind, this.i, this.j);
  final _Op kind;

  /// The spoken word (for [_Op.added]: the spoken word it comes before) and the suggested word.
  final int i, j;
}

class _Tok {
  _Tok(this.start, this.end, this.text);
  final int start, end;
  final String text;
}
