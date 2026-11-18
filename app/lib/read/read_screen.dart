import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../data/blessing.dart';
import '../share/links.dart';
import '../share/share.dart';
import '../share/share_sheet.dart';
import '../widgets/icons.dart';
import '../sky/placement.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/balanced_text.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';

/// Reading a blessing: the page scrolls up over the sky, where its light sits
/// alone near the top (SkyView.read). Edit and Delete live here too.
class ReadLayer extends StatefulWidget {
  const ReadLayer({
    super.key,
    required this.palette,
    required this.blessing,
    required this.placement,
    required this.on,
    required this.onBack,
    required this.onReview,
    required this.onDelete,
    this.onChanges,
    this.share,
    this.links,
    this.onSent,
    this.onYourLinks,
    this.liveLinks,
  });

  final Palette palette;
  final Blessing? blessing;
  final Placement placement;
  final bool on;
  final VoidCallback onBack;
  /// Edit, or Review on a draft: the review page.
  final VoidCallback onReview;

  /// Delete it (after the question): false when it was not deleted because its links could not be
  /// stopped (no internet), which the question then says.
  final Future<bool> Function() onDelete;

  /// "Review changes": the changes polish made, on their own screen.
  final VoidCallback? onChanges;

  /// The system share sheet (share/share.dart); none, no share control.
  final ShareApi? share;

  /// Links are made with this; null, the file only.
  final Links? links;

  /// It left the phone and the system sheet says it was sent (not cancelled).
  final Future<void> Function(Blessing b)? onSent;

  /// "Your links", from the link-made sheet.
  final VoidCallback? onYourLinks;

  /// How many of its links still work, for the delete question.
  final Future<int> Function(Blessing b)? liveLinks;

  /// Past this many points of scroll, the top goes solid behind the back button.
  static const double scrolledAt = 132;

  @override
  State<ReadLayer> createState() => ReadLayerState();
}

class ReadLayerState extends State<ReadLayer> {
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false, _deleting = false, _sharing = false, _sentSheet = false;

  /// The delete question's words: its links, and what went wrong.
  int _live = 0;
  String? _deleteNote;
  bool _deleteBusy = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > ReadLayer.scrolledAt;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void didUpdateWidget(ReadLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && (!oldWidget.on || oldWidget.blessing?.id != widget.blessing?.id)) {
      // every visit starts at the top of the page
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _scrolled = false;
      _deleting = _sharing = _sentSheet = false;
    }
    if (!widget.on && oldWidget.on) {
      _deleting = _sharing = _sentSheet = false;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Android's back: the share or delete sheet goes, if one is up. True when one went.
  bool closeSheet() {
    if (!_sharing && !_deleting && !_sentSheet) return false;
    // the Sent question's way out is Keep
    setState(() => _sharing = _deleting = _sentSheet = false);
    return true;
  }

  /// Tests: open the share sheet as its button does.
  void debugShare() => setState(() => _sharing = true);

  bool get _passing => widget.blessing?.ownership == Ownership.passingOn;

  Future<void> _askDelete() async {
    final b = widget.blessing;
    if (b == null) return;
    var live = 0;
    // a blessing passed along was handed over: its links are not stopped with it
    if (!_passing) {
      try {
        live = await widget.liveLinks?.call(b) ?? 0;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _live = live;
      _deleteNote = null;
      _deleting = true;
    });
  }

  Future<void> _confirmDelete() async {
    if (_deleteBusy) return;
    _deleteBusy = true;
    final ok = await widget.onDelete();
    _deleteBusy = false;
    if (!mounted) return;
    setState(() {
      if (ok) {
        _deleting = _sentSheet = false;
      } else {
        _deleteNote = Strings.deleteStopOffline;
      }
    });
  }

  Future<void> _sent(Blessing b, bool completed) async {
    if (!completed) return;
    await widget.onSent?.call(b);
    // one passed along: keep a copy, or let it go now
    if (mounted && b.ownership == Ownership.passingOn && identical(b, widget.blessing)) setState(() => _sentSheet = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = widget.blessing;
    final mq = MediaQuery.of(context);
    // the prototype's phone has its content start 62 points down; follow the real safe area
    final dy = math.max(62.0, mq.viewPadding.top) - 62;
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final spacer = 252 + dy;
      return Stack(children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const Key('read-scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: spacer),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: h - spacer + 16),
                child: _page(p, b),
              ),
            ]),
          ),
        ),
        // the sky darkens a little under the status bar and the back button
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 104 + dy,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.ground.withValues(alpha: .7), p.ground.withValues(alpha: .35), p.ground.withValues(alpha: 0)],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ),
        ),
        // once the words reach the top, it goes solid so they pass under cleanly
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 124 + dy,
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const Key('read-topsolid'),
              opacity: _scrolled ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.ground, p.ground, p.ground.withValues(alpha: 0)],
                    stops: const [0, .8, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 84,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [p.ground, p.ground, p.ground.withValues(alpha: 0)],
                  stops: const [0, .3, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 4,
          right: 12,
          top: 54 + dy,
          height: 44,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconBtn(key: const Key('read-back'), icon: Glyph.older, color: p.ink, palette: p, semantics: Strings.back, onTap: widget.onBack),
            Row(mainAxisSize: MainAxisSize.min, children: [
              // a draft has not been reviewed, so it cannot leave the phone yet
              if (b != null && !b.draft && widget.share != null)
                IconBtn(key: const Key('read-share'), icon: Glyph.share, color: p.ink, palette: p, semantics: Strings.share, onTap: () => setState(() => _sharing = true)),
              LightTextBtn(
                key: const Key('read-edit'),
                label: b?.draft ?? false ? Strings.review : Strings.edit,
                palette: p,
                onTap: widget.onReview,
              ),
            ]),
          ]),
        ),
        if (widget.share != null)
          Positioned.fill(
            child: ShareSheet(
              palette: p,
              on: _sharing && b != null && !b.draft,
              blessing: b,
              share: widget.share!,
              links: widget.links,
              onClose: () => setState(() => _sharing = false),
              onSent: (b, done) => unawaited(_sent(b, done)),
              onYourLinks: widget.onYourLinks,
            ),
          ),
        // sent, and passed along: keep a copy here, or delete it (its link keeps working)
        Positioned.fill(
          child: ConfirmSheet(
            palette: p,
            on: _sentSheet && !_deleting,
            barrier: true,
            title: Strings.sentTitle,
            body: Strings.sentBody,
            note: Strings.sentDeleteNote,
            noteKey: const Key('sent-note'),
            dangerLabel: Strings.delete,
            safeLabel: Strings.keep,
            onDanger: () => unawaited(_confirmDelete()),
            onSafe: () => setState(() => _sentSheet = false),
            panelKey: const Key('sent-sheet'),
            dangerKey: const Key('sent-delete'),
            safeKey: const Key('sent-keep'),
          ),
        ),
        Positioned.fill(
          child: ConfirmSheet(
            palette: p,
            on: _deleting,
            barrier: true,
            title: Strings.deleteTitle,
            body: _passing ? Strings.passingDeleteBody : (_live > 0 ? Strings.deleteLiveBody : Strings.deleteBody),
            note: _deleteNote,
            noteKey: const Key('delete-note'),
            dangerLabel: Strings.delete,
            safeLabel: Strings.keep,
            onDanger: () => unawaited(_confirmDelete()),
            onSafe: () => setState(() => _deleting = false),
            panelKey: const Key('delete-sheet'),
            dangerKey: const Key('delete-confirm'),
            safeKey: const Key('delete-keep'),
          ),
        ),
      ]);
    });
  }

  Widget _page(Palette p, Blessing? b) {
    if (b == null) return ColoredBox(color: p.ground);
    final words = b.words.split(RegExp(r'\n\s*\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final wordStyle = serif(19, 30, p.ink).copyWith(fontFeatures: const [FontFeature.oldstyleFigures()]);
    final note = sans(13, 20, p.ink3);
    // passthrough: the page fills the minimum height it is given, so the sky
    // never shows below a short page
    return Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      // past the end, the bounce shows more page rather than sky
      Positioned(left: 0, right: 0, bottom: -1000, height: 1000, child: ColoredBox(color: p.ground)),
      // the sky fades into the page above its first line
      Positioned(
        left: 0,
        right: 0,
        top: -76,
        height: 76,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.ground.withValues(alpha: 0), p.ground.withValues(alpha: .55), p.ground],
                stops: const [0, .5, 1],
              ),
            ),
          ),
        ),
      ),
      Container(
        color: p.ground,
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.longDate, key: const Key('read-date'), style: sans(13, 18, p.ink2, tracking: .005)),
          const SizedBox(height: 6),
          BalancedText(b.shownTitle, textKey: const Key('read-title'), style: serif(34, 38, p.ink, tracking: -.012)),
          if (b.from.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(Strings.blessingFrom(b.from), key: const Key('read-from'), style: serif(18, 26, p.light, italic: true)),
          ],
          if (b.draft) ...[
            const SizedBox(height: 22),
            Text(Strings.notReviewed, key: const Key('read-draft-note'), style: sans(15, 22, p.ink2)),
            const SizedBox(height: 14),
            PillBtn(key: const Key('read-review'), label: Strings.reviewThis, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: widget.onReview),
          ],
          // passed along: sending it is what this page is for
          if (!b.draft && b.ownership == Ownership.passingOn && widget.share != null) ...[
            const SizedBox(height: 22),
            if (b.sent != null) ...[
              Text(Strings.sentOn(b.sent!.toLocal()), key: const Key('read-sent'), style: sans(14, 20, p.ink2)),
              const SizedBox(height: 10),
            ],
            PillBtn(key: const Key('read-send'), label: Strings.sendBlessing, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: () => setState(() => _sharing = true)),
          ],
          const SizedBox(height: 28),
          if (words.isEmpty)
            Text(Strings.noWords, key: const Key('read-no-words'), style: serif(19, 30, p.ink3, italic: true))
          else
            for (var i = 0; i < words.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 15),
                child: Text(words[i], style: wordStyle),
              ),
          const SizedBox(height: 40),
          Container(height: 1, color: p.ink.withValues(alpha: .10)),
          const SizedBox(height: 20),
          if (words.isNotEmpty) ...[
            // polished words say so, and how much; the spoken words are always kept beside them
            Text(b.keptChanges > 0 ? Strings.polishedFrom(b.keptChanges) : Strings.asSpoken, key: const Key('read-as-spoken'), style: note),
            if (b.changes.isNotEmpty) ...[
              const SizedBox(height: 16),
              PillBtn(
                key: const Key('read-review-changes'),
                label: Strings.reviewChanges,
                palette: p,
                kind: PillKind.tonal,
                height: 44,
                fontSize: 15,
                onTap: () => widget.onChanges?.call(),
              ),
            ],
            const SizedBox(height: 24),
          ],
          // who it was for and its tags, quietly, above the closing line
          if (b.recipient.trim().isNotEmpty) ...[
            Text(Strings.forName(b.recipient.trim()), key: const Key('read-for'), style: note.copyWith(color: p.ink2)),
            const SizedBox(height: 4),
          ],
          if (b.tags.isNotEmpty) ...[
            Text(b.tags.join('  ·  '), key: const Key('read-tags'), style: note),
          ],
          if (b.recipient.trim().isNotEmpty || b.tags.isNotEmpty) const SizedBox(height: 24),
          Text(widget.placement.note(b), key: const Key('read-sky'), style: note),
          const SizedBox(height: 28),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: _QuietBtn(
              key: const Key('read-delete'),
              label: Strings.deleteBlessing,
              color: p.danger,
              palette: p,
              onTap: () => unawaited(_askDelete()),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// A quiet word as a button, in [color].
class _QuietBtn extends StatefulWidget {
  const _QuietBtn({super.key, required this.label, required this.color, required this.palette, required this.onTap});
  final String label;
  final Color color;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_QuietBtn> createState() => _QuietBtnState();
}

class _QuietBtnState extends State<_QuietBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: widget.palette.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: Text(widget.label, style: sans(15, 20, widget.color)),
        ),
      ),
    );
  }
}
