import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../not_yet.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/sheet.dart';
import 'blessing_file.dart';
import 'link_service.dart';
import 'links.dart';
import 'share.dart';

/// How a blessing leaves the phone (design/share, layout S3 with the link of V2): a card of the
/// blessing, "Send this blessing" (a link), and "Only the words" as text or a PDF. Once the link is
/// made, the sheet shows it, what it means, and "Send the link". With no internet, or no service,
/// one line and "Send as a file": the only place the file is offered.
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.palette,
    required this.on,
    required this.blessing,
    required this.share,
    required this.links,
    required this.onClose,
    required this.onSent,
    this.onYourLinks,
  });

  final Palette palette;
  final bool on;
  final Blessing? blessing;
  final ShareApi share;

  /// Null where links cannot be made at all (tests without a service): straight to the file.
  final Links? links;
  final VoidCallback onClose;

  /// The blessing left the phone: a link handed to the share sheet, or the file sent; [completed]
  /// when the system sheet says something was done with it (not cancelled).
  final void Function(Blessing b, bool completed) onSent;

  /// "Your links", from the link-made sheet.
  final VoidCallback? onYourLinks;

  @override
  State<ShareSheet> createState() => ShareSheetState();
}

enum ShareStep { choose, making, made, offline, trouble }

class ShareSheetState extends State<ShareSheet> {
  ShareStep step = ShareStep.choose;
  String? _url;
  LinkTrouble? _trouble;
  bool _copied = false, _busy = false;
  Timer? _copiedTimer;

  /// Tests: the link on the sheet.
  String? get debugUrl => _url;

  @override
  void didUpdateWidget(ShareSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // each time it opens it starts again (a link is made only when asked)
    if (widget.on && !oldWidget.on) _reset();
  }

  void _reset() {
    step = ShareStep.choose;
    _url = null;
    _trouble = null;
    _copied = false;
    _busy = false;
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _makeLink() async {
    final b = widget.blessing, links = widget.links;
    if (b == null || _busy) return;
    if (links == null) return setState(() => step = ShareStep.offline);
    setState(() {
      _busy = true;
      step = ShareStep.making;
    });
    final started = DateTime.now();
    MakeResult r;
    try {
      r = await links.make(b);
    } catch (e) {
      debugPrint('link: could not make one (${e.runtimeType})');
      r = const NotMade(LinkTrouble.offline);
    }
    // long enough to be read as a step, never a wait
    final shown = DateTime.now().difference(started);
    if (shown < const Duration(milliseconds: 500)) await Future<void>.delayed(const Duration(milliseconds: 500) - shown);
    if (!mounted || !widget.on) return;
    setState(() {
      _busy = false;
      switch (r) {
        case Made(:final url):
          _url = url;
          step = ShareStep.made;
          SemanticsService.sendAnnouncement(View.of(context), Strings.linkMade, TextDirection.ltr);
        case NotMade(:final trouble):
          _trouble = trouble;
          step = trouble == LinkTrouble.offline ? ShareStep.offline : ShareStep.trouble;
      }
    });
  }

  Future<void> _sendLink() async {
    final b = widget.blessing, url = _url;
    if (b == null || url == null || _busy) return;
    _busy = true;
    var done = false;
    try {
      done = await widget.share.link(url, shareTitle(b, Strings.wordsFor(Strings.language)));
    } catch (e) {
      debugPrint('share: $e');
    }
    _busy = false;
    if (!mounted) return;
    widget.onClose();
    widget.onSent(b, done);
  }

  Future<void> _sendFile() async {
    final b = widget.blessing;
    if (b == null || _busy) return;
    _busy = true;
    final w = Strings.wordsFor(Strings.language);
    // the app's sheet goes; the system's opens with the one file
    widget.onClose();
    var done = false;
    try {
      done = await widget.share.file(blessingFileName(shareFileName(b, w)), BlessingRecord.of(b).toFileBytes(), shareTitle(b, w));
    } catch (e) {
      debugPrint('share: $e');
    }
    _busy = false;
    widget.onSent(b, done);
  }

  Future<void> _words({required bool pdf}) async {
    final b = widget.blessing;
    if (b == null) return;
    widget.onClose();
    try {
      if (pdf) {
        await widget.share.pdf(sharePdf(b));
      } else {
        await widget.share.text(shareText(b), shareTitle(b, Strings.wordsFor(Strings.language)));
      }
    } catch (e) {
      debugPrint('share: $e');
    }
  }

  void _copy() {
    final url = _url;
    if (url == null) return;
    // Android: marked sensitive, so its copy preview shows dots, never the link (which holds the key)
    unawaited(Phone.android ? NativeShareApi.copySensitive(url) : Clipboard.setData(ClipboardData(text: url)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    SemanticsService.sendAnnouncement(View.of(context), Strings.linkCopied, TextDirection.ltr);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = widget.blessing;
    final still = MediaQuery.of(context).disableAnimations;
    final steps = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 250),
      child: KeyedSubtree(
        key: ValueKey(step),
        child: b == null ? const SizedBox.shrink() : _body(p, b),
      ),
    );
    return Sheet(
      palette: p,
      on: widget.on && b != null,
      barrier: true,
      label: Strings.shareTitle,
      panelKey: const Key('share-sheet'),
      // while the link is being made, a stray tap does not throw it away
      onDismiss: step == ShareStep.making ? null : widget.onClose,
      // With Reduce Motion the sheet simply takes its new size. (An AnimatedSize with no duration
      // is not the way: it marks itself for layout during its own layout, and Flutter throws.)
      child: still
          ? steps
          : AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: easeOut,
              alignment: Alignment.bottomCenter,
              child: steps,
            ),
    );
  }

  Widget _body(Palette p, Blessing b) => switch (step) {
        ShareStep.choose || ShareStep.making => _choose(p, b),
        ShareStep.made => _made(p),
        ShareStep.offline || ShareStep.trouble => _noLink(p),
      };

  Widget _wordsRow(Palette p) {
    final text = _Chip(key: const Key('share-text'), palette: p, icon: Glyph.text, label: Strings.textChip, onTap: () => _words(pdf: false));
    final pdf = _Chip(key: const Key('share-pdf'), palette: p, icon: Glyph.pdf, label: Strings.pdfChip, onTap: () => _words(pdf: true));
    final style = sans(14, 19, p.ink3);
    final label = Text(Strings.onlyWords, style: style);
    // at the largest text and display sizes the label goes above the two chips (beside them it was
    // squeezed to a letter or two a line); measured, because Android scales text non-linearly
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
          text: TextSpan(text: Strings.onlyWords, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout();
      if (tp.width > c.maxWidth * .45) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label,
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [text, pdf]),
        ]);
      }
      return Row(children: [Expanded(child: label), const SizedBox(width: 8), text, const SizedBox(width: 8), pdf]);
    });
  }

  Widget _foot(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        Container(height: 1, color: p.ink.withValues(alpha: .10)),
        const SizedBox(height: 16),
        Text(Strings.shareFoot, key: const Key('share-note'), textAlign: TextAlign.center, style: sans(13, 18, p.ink3)),
      ]);

  Widget _choose(Palette p, Blessing b) {
    final making = step == ShareStep.making;
    final from = b.from.trim();
    return Column(key: const Key('share-choose'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.ink.withValues(alpha: .05), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Thumb(palette: p),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.shownTitle, key: const Key('share-card-title'), maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(21, 26, p.ink)),
                const SizedBox(height: 2),
                Text(from.isEmpty ? Strings.aBlessing : Strings.blessingFrom(from), style: serif(16, 22, p.light, italic: true)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          BigButton(
            key: const Key('share-send'),
            palette: p,
            icon: Glyph.blessing,
            label: making ? Strings.linkMaking : Strings.sendBlessing,
            busy: making,
            onTap: making ? null : _makeLink,
          ),
          const SizedBox(height: 12),
          Text(Strings.keepNote, textAlign: TextAlign.center, style: sans(14, 19, p.ink3)),
          const SizedBox(height: 2),
        ]),
      ),
      const SizedBox(height: 18),
      _wordsRow(p),
      _foot(p),
    ]);
  }

  Widget _made(Palette p) {
    final url = _url ?? '';
    final hash = url.indexOf('#');
    final shown = url.replaceFirst(RegExp(r'^https?://'), '');
    final cut = hash < 0 ? shown.length : shown.indexOf('#');
    final mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: const ['Courier', 'monospace'], fontSize: 15, height: 20 / 15, color: p.ink);
    return Column(key: const Key('share-made'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        SizedBox(width: 22, height: 22, child: GlyphIcon(Glyph.link, color: p.light)),
        const SizedBox(width: 12),
        Text(Strings.linkMade, key: const Key('share-made-line'), style: sans(15, 20, p.ink2)),
      ]),
      const SizedBox(height: 14),
      Semantics(
        label: Strings.copyLink,
        button: true,
        excludeSemantics: true,
        onTap: _copy,
        child: GestureDetector(
          key: const Key('share-copy'),
          behavior: HitTestBehavior.opaque,
          onTap: _copy,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(color: p.ink.withValues(alpha: .06), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: shown.substring(0, cut)),
                    TextSpan(text: shown.substring(cut), style: TextStyle(color: p.ink3)),
                  ]),
                  key: const Key('share-link'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: mono,
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _copied
                    ? Text(Strings.linkCopied, key: const Key('share-copied'), style: sans(13, 18, p.light))
                    : SizedBox(key: const Key('share-copy-icon'), width: 22, height: 22, child: GlyphIcon(Glyph.copy, color: p.ink2)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(Strings.linkLine, key: const Key('share-link-line'), style: sans(17, 23, p.ink)),
      const SizedBox(height: 8),
      Text(Strings.linkLine2, style: sans(15, 21, p.ink3)),
      const SizedBox(height: 20),
      BigButton(key: const Key('share-send-link'), palette: p, icon: Glyph.share, label: Strings.sendLink, onTap: _sendLink),
      if (widget.onYourLinks != null) ...[
        const SizedBox(height: 16),
        Container(height: 1, color: p.ink.withValues(alpha: .10)),
        Semantics(
          button: true,
          label: Strings.yourLinks,
          excludeSemantics: true,
          onTap: _yourLinks,
          child: GestureDetector(
            key: const Key('share-your-links'),
            behavior: HitTestBehavior.opaque,
            onTap: _yourLinks,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Expanded(child: Text(Strings.yourLinks, style: sans(15, 20, p.ink2))),
                SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.forward, color: p.ink3)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  void _yourLinks() {
    widget.onClose();
    widget.onYourLinks!();
  }

  Widget _noLink(Palette p) {
    final line = switch (_trouble) {
      LinkTrouble.slowDown => Strings.linkSlowDown,
      LinkTrouble.full => Strings.linkFull,
      LinkTrouble.tooBig => Strings.linkTooBig,
      LinkTrouble.unavailable => Strings.linkUnavailable,
      _ => Strings.offLine,
    };
    return Column(key: const Key('share-offline'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, height: 24, child: GlyphIcon(Glyph.offline, color: p.ink3)),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(line, key: const Key('share-offline-line'), style: sans(15, 22, p.ink2)),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      BigButton(key: const Key('share-file'), palette: p, icon: Glyph.file, label: Strings.sendFile, onTap: _sendFile),
      const SizedBox(height: 12),
      Text(Strings.fileNote, textAlign: TextAlign.center, style: sans(14, 19, p.ink3)),
      const SizedBox(height: 18),
      _wordsRow(p),
      // no foot here: "This sends a link" would be untrue when only the file can be sent
    ]);
  }
}

/// The blessing's light, small, on the night: the card's picture.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ExcludeSemantics(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: p.ground,
          borderRadius: BorderRadius.circular(16),
          gradient: RadialGradient(
            radius: .5,
            colors: [const Color(0xFFFFF0CD), p.light, p.light.withValues(alpha: .3), p.light.withValues(alpha: 0), p.ground],
            stops: const [0, .07, .22, .55, 1],
          ),
        ),
      ),
    );
  }
}

/// The gold button with an icon: "Send this blessing", "Send the link", "Send as a file", and the
/// hand-over's "Send Emma's ring" (people/hand_over_sheet.dart).
class BigButton extends StatefulWidget {
  const BigButton({super.key, required this.palette, required this.icon, required this.label, required this.onTap, this.busy = false});
  final Palette palette;
  final Glyph icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<BigButton> createState() => BigButtonState();
}

class BigButtonState extends State<BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final bg = _down ? Color.lerp(p.light, p.ink, .25)! : p.light;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: widget.busy ? p.light.withValues(alpha: .55) : bg, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 30, height: 30, child: GlyphIcon(widget.icon, color: p.ground)),
            const SizedBox(width: 12),
            Flexible(child: Text(widget.label, textAlign: TextAlign.center, style: sans(18, 23, p.ground, weight: FontWeight.w500))),
          ]),
        ),
      ),
    );
  }
}

/// "Text", "PDF": small quiet buttons for only the words.
class _Chip extends StatefulWidget {
  const _Chip({super.key, required this.palette, required this.icon, required this.label, required this.onTap});
  final Palette palette;
  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .12 : .07), borderRadius: BorderRadius.circular(22)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 20, height: 20, child: GlyphIcon(widget.icon, color: p.ink2)),
            const SizedBox(width: 8),
            Text(widget.label, style: sans(15, 20, p.ink2)),
          ]),
        ),
      ),
    );
  }
}
