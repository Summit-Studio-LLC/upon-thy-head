/// The word lists the polish rules use (rules.dart). Kept here, on their own, so they are easy to
/// review and extend. Every word is lower case; the rules compare without regard to capitals.
///
/// The principle: when unsure, leave the words alone. A word goes on a list only when removing it
/// can never change what was said.
library;

/// A word, as the rules see one: letters, marks and digits, with apostrophes inside ("it’s").
final RegExp wordPattern = RegExp(r"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*", unicode: true);

/// Sounds that carry no meaning, removed wherever they stand as words of their own.
const Map<String, Set<String>> fillers = {
  'en': {
    'um', // hesitation
    'uh', // hesitation
    'uhm', // hesitation, as some recognisers spell it
    'er', // hesitation (British spelling of "uh")
    'erm', // hesitation (British spelling of "um")
    // not 'ah': it can be meant ("Ah, my daughter"); Noah, 2026-11-15
    'hmm', // thinking aloud
    'mm', // thinking aloud
  },
  'es': {
    'eh', // hesitation
    'em', // hesitation
    'mm', // thinking aloud
  },
};

/// Words and phrases that are filler only sometimes ("este día" means "this day"; "you know the
/// Lord" means what it says). Removed only when they stand alone between two commas, as in
/// "y, este, te bendigo", and never otherwise.
const Map<String, Set<String>> fillersBetweenCommas = {
  'en': {
    'you know', // "I bless you, you know, with peace"
    'like', // "and, like, the hands"
  },
  'es': {
    'este', // "y, este, te bendigo"; never "este día"
    'o sea', // "o sea" as a pause ("that is"), only between commas
    'pues', // "pues" as a pause ("well"), only between commas
  },
};

/// Short function words that, said twice or more in a row, are a stumble: "with with peace",
/// "I, I bless you", "de de". Left out of the lists on purpose, because repeating them can be
/// meant or is ordinary grammar:
///  - "that that", "had had", "is is" ("what it is is"), "her her" ("give her her blessing"),
///    "you you" ("you, you and your family"), "will" (also a name), "que" ("dice que, que…" is
///    usually a stumble, but "lo que, que" is not always), "very".
/// Words such as "holy", "verily", "amen", names and numbers are on no list and are never touched.
const Map<String, Set<String>> repeatable = {
  'en': {
    'a', 'an', 'the', // articles
    'and', 'but', 'or', // joining words
    'of', 'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'upon', // prepositions
    'i', 'we', 'he', 'she', 'they', // pronouns that begin a clause ("I, I bless you")
    'my', 'your', 'his', 'our', 'their', // possessives ("your your body")
  },
  'es': {
    'el', 'la', 'los', 'las', 'un', 'una', // artículos
    'y', 'o', // conjunciones
    'de', 'del', 'a', 'al', 'en', 'con', 'por', 'para', // preposiciones
    'yo', 'te', 'se', 'me', 'lo', 'le', // pronombres
    'mi', 'tu', 'su', // posesivos
  },
};

/// The language whose lists apply to a blessing spoken in [code] ("en", "es", or '' for one
/// typed before languages were recorded, taken as English).
String rulesLanguage(String code) => code == 'es' ? 'es' : 'en';

/// [w] (lower case) is a filler sound in any language: used when measuring a change's size.
bool isAnyFiller(String w) => fillers.values.any((s) => s.contains(w));
