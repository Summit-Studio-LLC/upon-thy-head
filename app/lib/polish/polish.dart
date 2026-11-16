import '../data/blessing.dart';
import 'change.dart';
import 'rules.dart';

/// Polishing a blessing's words, only ever when the person asks. The spoken words ([Blessing.rawText])
/// are never changed by it: the changes sit beside them, each kept or restored, and the polished
/// words are worked out from the two (see change.dart).
class Polish {
  const Polish._();

  /// Where changes come from. The rules for now; a model on the phone can be added here later and
  /// its changes are handled the same way.
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
