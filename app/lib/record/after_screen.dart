import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/balanced_text.dart';
import '../widgets/buttons.dart';
import '../widgets/scrims.dart';
import 'session.dart';

/// After Amen: the new light alone in the sky, and what to do with the words.
class AfterLayer extends StatefulWidget {
  const AfterLayer({
    super.key,
    required this.palette,
    required this.blessing,
    required this.on,
    required this.onReview,
    required this.onSave,
    this.words = WordsState.done,
    this.heard = true,
  });

  final Palette palette;
  final Blessing? blessing;

  /// Whether the words are still being written, written, or could not be.
  final WordsState words;

  /// Some words came back (when [words] is done).
  final bool heard;
  final bool on;
  final VoidCallback onReview, onSave;

  @override
  State<AfterLayer> createState() => _AfterLayerState();
}

class _AfterLayerState extends State<AfterLayer> {
  /// The finger that held Amen is resting where the buttons appear; they wait
  /// a moment before taking touches.
  bool _fresh = false;
  Timer? _timer;

  @override
  void didUpdateWidget(AfterLayer old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on) {
      _fresh = true;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _fresh = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = widget.blessing;
    final writing = widget.words == WordsState.writing || widget.words == WordsState.none;
    final (title, body) = switch (widget.words) {
      WordsState.unavailable => (Strings.recordingKept, Strings.wordsNotWrittenYet),
      WordsState.later => (Strings.recordingKept, Strings.wordsLater),
      WordsState.failed => (Strings.recordingKept, Strings.wordsNotWritten),
      WordsState.done when !widget.heard => (Strings.noWordsHeard, Strings.recordingKeptBody),
      _ => (Strings.wordsKept, Strings.recordingKeptBody),
    };
    return Stack(children: [
      Positioned(left: 0, right: 0, bottom: 0, height: 440, child: BottomScrim(palette: p)),
      // From the bottom up. At the largest text and display sizes (Spanish is the longest) it is
      // taller than the screen: it then stops under the status bar and scrolls, the buttons in view.
      Positioned(
        left: 24,
        right: 24,
        top: MediaQuery.viewPaddingOf(context).top + 16,
        bottom: 50,
        child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: SingleChildScrollView(
              key: const Key('after-scroll'),
              reverse: true,
              child: _content(p, b, writing, title, body),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _content(Palette p, Blessing? b, bool writing, String title, String body) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(b == null ? '' : Strings.dayAndTime(b.local), key: const Key('after-meta'), style: sans(13, 18, p.ink2, tracking: .005)),
          const SizedBox(height: 8),
          // the title settles once the words are written; until then a quiet line in its place
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: easeOut,
            switchOutCurve: easeOut,
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
            child: writing
                ? Text(Strings.writingWords, key: const Key('after-writing'), style: serif(34, 38, p.ink3, italic: true, tracking: -.012))
                : BalancedText(title, key: ValueKey(title), textKey: const Key('after-title'), style: serif(34, 38, p.ink, tracking: -.012)),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: Text(body, key: ValueKey(body), style: sans(17, 25, p.ink2)),
            ),
          ),
          const SizedBox(height: 36),
          IgnorePointer(
            ignoring: _fresh,
            child: Column(children: [
              PillBtn(
                key: const Key('review-now'),
                label: Strings.reviewNow,
                palette: p,
                kind: PillKind.primary,
                onTap: widget.onReview,
              ),
              const SizedBox(height: 8),
              PillBtn(
                key: const Key('save-later'),
                label: Strings.saveForLater,
                palette: p,
                kind: PillKind.quiet,
                onTap: widget.onSave,
              ),
            ]),
          ),
        ]);
}
