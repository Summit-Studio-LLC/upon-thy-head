import '../data/blessing.dart';
import '../strings.dart';
import 'change.dart';
import 'model.dart';
import 'rules.dart';
import 'words.dart';

/// Polishing a blessing's words, only ever when the person asks. The spoken words ([Blessing.rawText])
/// are never changed by it: the changes sit beside them, each kept or restored, and the polished
/// words are worked out from the two (see change.dart).
class Polish {
  const Polish._();

  /// Where changes come from at once: the rules. The phone's own model, when there is one, is a
  /// second, slower source ([runWithModel]); where both change the same words, the rules' change
  /// wins.
  static const List<ChangeSource> sources = [PolishRules()];

  /// Every change the sources find in [spoken], none overlapping, in order.
  static List<Change> find(String spoken, String language) {
    var out = <Change>[];
    for (final s in sources) {
      out = mergeChanges(out, s.find(spoken, language));
    }
    return out;
  }

  /// "Polish the words": the changes found are added (kept) to those [b] already has. The number
  /// added; 0 means there was nothing to polish.
  static int run(Blessing b) {
    b.polishAsked = true;
    final before = b.changes.length;
    b.changes = mergeChanges(b.changes, find(b.rawText, b.language));
    return b.changes.length - before;
  }

  /// "Polish the words" on a phone that may have its own model: the rules' changes, then the model's
  /// that touch none of them, added (kept) to those [b] already has. With no model this is [run].
  /// The model is asked only here, never after a correction ([refresh] is the rules alone).
  ///
  /// [work] stops it (leaving the page); then nothing is added and null is returned. Words corrected
  /// while the model worked carry its changes along where their words are untouched.
  static Future<int?> runWithModel(Blessing b, {required PhoneModel model, Set<String> names = const {}, PolishWork? work}) async {
    final spoken = b.rawText;
    final found = await ModelSource(model).find(spoken, b.language, names: names, work: work);
    if (work?.cancelled ?? false) return null;
    final fromModel = b.rawText == spoken ? found : rebaseChanges(spoken, b.rawText, found);
    final n = run(b);
    final before = b.changes.length;
    b.changes = mergeChanges(b.changes, fromModel);
    return n + b.changes.length - before;
  }

  /// The words of [b]'s details that may be names (who gave it, who it was for, its title, and
  /// [more], such as the family member's name), for the model's check.
  static Set<String> namesOf(Blessing b, [Iterable<String> more = const []]) => {
        for (final s in [b.from, b.recipient, if (!Strings.isUntitled(b.title)) b.title, ...more])
          for (final m in wordPattern.allMatches(s))
            if (m.group(0)!.length > 1 && m.group(0)![0] != m.group(0)![0].toLowerCase()) m.group(0)!,
      };

  /// The spoken words corrected by hand to [text]: changes whose words are untouched move with them
  /// and keep their state; changes whose words were edited are dropped.
  static void correct(Blessing b, String text) {
    if (b.changes.isNotEmpty) b.changes = rebaseChanges(b.rawText, text, b.changes);
    b.rawText = text;
  }

  /// After a correction has settled: if the person had asked for polish, the rules look again at the
  /// new words and anything new is added as kept. True when something was added.
  static bool refresh(Blessing b) {
    if (!b.polishAsked) return false;
    final before = b.changes.length;
    b.changes = mergeChanges(b.changes, find(b.rawText, b.language));
    return b.changes.length != before;
  }
}
