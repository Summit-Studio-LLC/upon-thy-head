import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import 'android_words.dart';
import 'words_model.dart';

/// Android's one-time download of the speech model (docs/android-plan.md 3.5), as the person sees
/// it wherever it is offered: the first run, After Amen, the review page. It follows the model as it
/// comes in; nothing is downloaded until Download is tapped.
///
/// [onLater] (the first run) adds the Later button beside Download, and becomes Continue once the
/// download has started or the model is here; elsewhere there is only Download.
class ModelOffer extends StatelessWidget {
  const ModelOffer({super.key, required this.palette, this.onLater, this.showBody = true, this.compact = false});

  final Palette palette;
  final VoidCallback? onLater;

  /// The sentence saying what the download is (the first run shows it; After Amen has its own).
  final bool showBody;

  /// A smaller Download button, for the review page.
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: WordsModel.instance,
        builder: (context, _) => _build(WordsModel.instance.status, WordsModel.instance.spec.megabytes),
      );

  Widget _build(ModelStatus s, int mb) {
    final p = palette;
    final line = _line(s);
    final started = s.busy || s.ready;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showBody) ...[
        Text(Strings.modelBody(mb), key: const Key('model-body'), style: sans(17, 25, p.ink2)),
        const SizedBox(height: 12),
      ],
      if (line != null)
        Semantics(
          liveRegion: true,
          child: Text(line, key: const Key('model-line'), style: sans(15, 21, s.problem == ModelProblem.none && !s.noRoom ? p.ink3 : p.ink2)),
        ),
      if (s.busy) ...[
        const SizedBox(height: 10),
        _Bar(palette: p, fraction: s.state == ModelState.checking ? 1 : s.fraction),
      ],
      SizedBox(height: compact ? 16 : 28),
      if (!started)
        PillBtn(
          key: const Key('model-download'),
          label: s.state == ModelState.failed ? Strings.tryAgain : Strings.download,
          palette: p,
          kind: compact ? PillKind.tonal : PillKind.primary,
          height: compact ? 44 : 52,
          fontSize: compact ? 15 : 17,
          onTap: WordsModel.instance.download,
        ),
      if (onLater != null) ...[
        if (!started) const SizedBox(height: 8),
        PillBtn(
          key: Key(started ? 'model-continue' : 'model-later'),
          label: started ? Strings.continueLabel : Strings.laterButton,
          palette: p,
          kind: started && s.ready ? PillKind.primary : PillKind.quiet,
          onTap: onLater,
        ),
      ],
    ]);
  }

  static int _mb(int bytes) => (bytes / 1000000).round();

  /// One quiet line under the offer: where the download is, or why it stopped.
  static String? _line(ModelStatus s) {
    if (s.ready) return Strings.modelReady;
    switch (s.state) {
      case ModelState.downloading:
        return Strings.modelProgress(_mb(s.got), _mb(s.total));
      case ModelState.waiting:
        return Strings.modelWaiting;
      case ModelState.checking:
        return Strings.modelChecking;
      default:
    }
    if (s.noRoom) return Strings.modelNoRoom(_mb(s.needed - s.free).clamp(1, 1 << 30));
    if (s.problem == ModelProblem.checksum) return Strings.modelChecksum;
    if (s.problem == ModelProblem.server) return Strings.modelServer;
    if (s.metered) return Strings.modelMetered;
    return null;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.palette, required this.fraction});
  final Palette palette;
  final double fraction;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: 3,
          child: LayoutBuilder(
            builder: (context, c) => Stack(children: [
              Positioned.fill(child: ColoredBox(color: palette.ink3.withValues(alpha: .25))),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                left: 0,
                top: 0,
                bottom: 0,
                width: c.maxWidth * fraction,
                child: ColoredBox(color: palette.ink2),
              ),
            ]),
          ),
        ),
      );
}

/// Android, while the words of the recording at [path] are written piece by piece: "3 of 8 parts
/// written", and one quiet line saying it goes on only while the app is open (or that it carried on
/// from where it stopped). Nothing until the first piece is under way.
class WritingProgress extends StatelessWidget {
  const WritingProgress({super.key, required this.palette, required this.path});

  final Palette palette;
  final String? path;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, WordsProgress>>(
        valueListenable: AndroidWords.instance.progress,
        builder: (context, all, _) {
          final w = path == null ? null : all[path];
          if (w == null || w.total == 0) return const SizedBox.shrink();
          final p = palette;
          return Column(key: const Key('writing-progress'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              liveRegion: true,
              child: Text(Strings.piecesWritten(w.done, w.total), key: const Key('writing-count'), style: sans(15, 21, p.ink2)),
            ),
            const SizedBox(height: 8),
            _Bar(palette: p, fraction: w.done / w.total),
            const SizedBox(height: 8),
            Text(w.resumed > 0 ? Strings.carriedOn(w.resumed + 1) : Strings.writingQuiet, key: const Key('writing-quiet'), style: sans(13, 18, p.ink3)),
          ]);
        },
      );
}
