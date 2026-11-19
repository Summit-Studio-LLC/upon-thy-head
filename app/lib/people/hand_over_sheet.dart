import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/semantics.dart';

import '../not_yet.dart';
import '../share/link_service.dart';
import '../share/links.dart';
import '../share/share_sheet.dart' show BigButton;
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/sheet.dart';
import 'person.dart';

/// Handing a family member's ring to their own phone, the parent's side (design/entry-and-rings,
/// B1-10 and B1-11): the share sheet's card with whose ring and how many, a "Kept by" name typed
/// once, the gold "Send Emma's ring", and the plain line that this sends a link. The link goes out
/// through the system share sheet as a blessing's does. Once it has gone: keep the ring on this
/// phone, or delete it now (Keep is the main button).
class HandOverSheet extends StatefulWidget {
  const HandOverSheet({
    super.key,
    required this.palette,
    required this.on,
    required this.person,
    required this.countLine,
    required this.keptBy,
    required this.onMake,
    required this.onShare,
    required this.onSent,
    required this.onClose,
    this.onDelete,
  });

  final Palette palette;
  final bool on;
  final Person? person;

  /// "Seven blessings since August 2008".
  final String countLine;

  /// The name the "Kept by" row starts with (remembered, or the ring's most common From name).
  final String keptBy;

  /// Make the ring's link, kept by the name typed.
  final Future<MakeResult> Function(String keptBy) onMake;

  /// The system share sheet with [url]: true when it was sent somewhere.
  final Future<bool> Function(String url, String title) onShare;

  /// The link was sent: remember the name, and when.
  final void Function(String keptBy) onSent;

  /// Keep (the ring stays), a tap on the dimmed sky, or closing before sending.
  final VoidCallback onClose;

  /// Delete it now: the family member's page asks once more, as removing them does. Null when
  /// drafts remain on the ring (never offered then).
  final VoidCallback? onDelete;

  @override
  State<HandOverSheet> createState() => HandOverSheetState();
}

enum HandOverStep { choose, making, made, sent }

class HandOverSheetState extends State<HandOverSheet> {
  HandOverStep step = HandOverStep.choose;
  final _keptBy = TextEditingController();
  final _focus = FocusNode();
  String? _url, _trouble;
  bool _busy = false;
  int _gen = 0;

  /// Tests: the link made.
  String? get debugUrl => _url;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(HandOverSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // each time it opens (or switches person) it starts again
    if ((widget.on && !oldWidget.on) || widget.person?.id != oldWidget.person?.id) _reset();
    if (!widget.on && oldWidget.on) {
      _gen++;
      _busy = false;
      _focus.unfocus();
    }
  }

  void _reset() {
    _gen++;
    step = HandOverStep.choose;
    _keptBy.text = widget.keptBy;
    _url = _trouble = null;
    _busy = false;
  }

  @override
  void dispose() {
    _keptBy.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _name => widget.person?.name ?? '';

  Future<void> _send() async {
    if (_busy || widget.person == null) return;
    final gen = ++_gen;
    _focus.unfocus();
    setState(() {
      _busy = true;
      _trouble = null;
      step = HandOverStep.making;
    });
    final started = DateTime.now();
    MakeResult r;
    try {
      r = await widget.onMake(_keptBy.text.trim());
    } catch (e) {
      debugPrint('hand over: could not make the link (${e.runtimeType})');
      r = const NotMade(LinkTrouble.offline);
    }
    final shown = DateTime.now().difference(started);
    if (shown < const Duration(milliseconds: 500)) await Future<void>.delayed(const Duration(milliseconds: 500) - shown);
    if (!mounted || !widget.on || gen != _gen) return;
    switch (r) {
      case Made(:final url):
        _url = url;
        _busy = false;
        await _share();
      case NotMade(:final trouble):
        setState(() {
          _busy = false;
          step = HandOverStep.choose;
          _trouble = switch (trouble) {
            LinkTrouble.slowDown => Strings.linkSlowDown,
            LinkTrouble.full => Strings.linkFull,
            LinkTrouble.tooBig => Strings.ringTooBig(_name),
            LinkTrouble.unavailable => Strings.linkUnavailable,
            LinkTrouble.offline => Strings.offLine,
          };
        });
    }
  }

  /// The system share sheet with the link; sent, the keep-or-delete question; not, the link stays
  /// here to send when they are ready (it is in Your links meanwhile).
  Future<void> _share() async {
    final url = _url;
    if (url == null || _busy) return;
    final gen = ++_gen;
    _busy = true;
    var done = false;
    try {
      done = await widget.onShare(url, Strings.ringOf(_name));
    } catch (e) {
      debugPrint('hand over: $e');
    }
    if (gen != _gen) return;
    _busy = false;
    if (!mounted || !widget.on) return;
    if (done) widget.onSent(_keptBy.text.trim());
    setState(() => step = done ? HandOverStep.sent : HandOverStep.made);
    if (done) SemanticsService.sendAnnouncement(View.of(context), Strings.ringSent, TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final still = MediaQuery.of(context).disableAnimations;
    final steps = AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 250),
      child: KeyedSubtree(
        key: ValueKey(step == HandOverStep.making ? HandOverStep.choose : step),
        child: widget.person == null ? const SizedBox.shrink() : _body(p),
      ),
    );
    return Sheet(
      palette: p,
      on: widget.on && widget.person != null,
      barrier: true,
      label: Strings.handOverRow(_name),
      panelKey: const Key('hand-over-sheet'),
      // while the link is being made, or the delete question is open, a stray tap does not end it
      onDismiss: step == HandOverStep.choose || step == HandOverStep.made || (step == HandOverStep.sent && widget.onDelete == null)
          ? widget.onClose
          : null,
      child: still
          ? steps
          : AnimatedSize(duration: const Duration(milliseconds: 300), curve: easeOut, alignment: Alignment.bottomCenter, child: steps),
    );
  }

  Widget _body(Palette p) => switch (step) {
        HandOverStep.choose || HandOverStep.making => _choose(p),
        HandOverStep.made => _made(p),
        HandOverStep.sent => _sent(p),
      };

  Widget _card(Palette p, List<Widget> below) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.ink.withValues(alpha: .05), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MergeSemantics(
            child: Row(children: [
              RingThumb(palette: p),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Strings.ringOf(_name), key: const Key('hand-over-title'), maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(21, 26, p.ink)),
                  const SizedBox(height: 2),
                  Text(widget.countLine, key: const Key('hand-over-count'), style: sans(14, 19, p.ink2)),
                ]),
              ),
            ]),
          ),
          ...below,
        ]),
      );

  Widget _keptByRow(Palette p) {
    final scaler = MediaQuery.textScalerOf(context);
    final stacked = scaler.scale(15) > 28;
    final label = ExcludeSemantics(child: Text(Strings.keptByLabel, style: sans(15, 20, p.ink2)));
    final field = CupertinoTextField(
      key: const Key('hand-over-kept-by'),
      controller: _keptBy,
      focusNode: _focus,
      enabled: step == HandOverStep.choose,
      style: sans(17, 22, p.ink),
      placeholder: Strings.keptByHint,
      placeholderStyle: sans(17, 22, p.ink3),
      cursorColor: p.light,
      keyboardAppearance: Brightness.dark,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      maxLength: nameLimit,
      onSubmitted: (_) => _focus.unfocus(),
      padding: EdgeInsets.zero,
      decoration: null,
      selectionControls: Phone.android ? m.materialTextSelectionHandleControls : null,
      contextMenuBuilder: Phone.android
          ? (context, s) => m.AdaptiveTextSelectionToolbar.editableText(editableTextState: s)
          : (context, s) => CupertinoAdaptiveTextSelectionToolbar.editableText(editableTextState: s),
    );
    final value = MergeSemantics(
      child: Semantics(
        label: Strings.keptByLabel,
        child: Phone.android
            ? m.Theme(
                data: m.ThemeData(
                  brightness: Brightness.dark,
                  textSelectionTheme: m.TextSelectionThemeData(selectionHandleColor: p.light, cursorColor: p.light),
                ),
                child: field,
              )
            : field,
      ),
    );
    final pencil = ExcludeSemantics(child: SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.writing, color: p.ink3)));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(top: 12), child: label),
                Padding(padding: const EdgeInsets.only(top: 4, bottom: 14), child: value),
              ])
            : Row(children: [
                SizedBox(width: 82 * math.max(1.0, scaler.scale(15) / 15), child: label),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 15), child: value)),
                const SizedBox(width: 8),
                pencil,
              ]),
      ),
    );
  }

  Widget _foot(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        Container(height: 1, color: p.ink.withValues(alpha: .10)),
        const SizedBox(height: 16),
        Text(Strings.ringFoot, key: const Key('hand-over-note'), textAlign: TextAlign.center, style: sans(13, 18, p.ink3)),
      ]);

  Widget _choose(Palette p) {
    final making = step == HandOverStep.making;
    final trouble = _trouble;
    return Column(key: const Key('hand-over-choose'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _card(p, [
        const SizedBox(height: 6),
        Container(height: 1, color: p.ink.withValues(alpha: .10)),
        _keptByRow(p),
        const SizedBox(height: 4),
        BigButton(
          key: const Key('hand-over-send'),
          palette: p,
          icon: Glyph.blessing,
          label: making ? Strings.linkMaking : Strings.sendRing(_name),
          busy: making,
          onTap: making ? null : () => unawaited(_send()),
        ),
        const SizedBox(height: 12),
        if (trouble != null) ...[
          Semantics(liveRegion: true, child: Text(trouble, key: const Key('hand-over-trouble'), textAlign: TextAlign.center, style: sans(14, 19, p.ink2))),
          const SizedBox(height: 8),
        ],
        Text(Strings.ringKeepNote(_name), textAlign: TextAlign.center, style: sans(14, 19, p.ink3)),
        const SizedBox(height: 2),
      ]),
      _foot(p),
    ]);
  }

  /// Made, but the share sheet was closed without sending: the link waits here.
  Widget _made(Palette p) => Column(key: const Key('hand-over-made'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _card(p, [
          const SizedBox(height: 14),
          Text(Strings.ringNotSentYet(_name), key: const Key('hand-over-made-line'), style: sans(15, 21, p.ink2)),
          const SizedBox(height: 16),
          BigButton(key: const Key('hand-over-send-link'), palette: p, icon: Glyph.share, label: Strings.sendLink, onTap: () => unawaited(_share())),
        ]),
        _foot(p),
      ]);

  /// Sent: keep the ring here, or delete it now (when no drafts remain on it).
  Widget _sent(Palette p) => Column(key: const Key('hand-over-sent'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          SizedBox(width: 22, height: 22, child: GlyphIcon(Glyph.link, color: p.light)),
          const SizedBox(width: 12),
          Text(Strings.ringSent, key: const Key('hand-over-sent-line'), style: sans(15, 20, p.ink2)),
        ]),
        if (widget.onDelete != null) ...[
          const SizedBox(height: 14),
          Text(Strings.keepOrDelete(_name), key: const Key('hand-over-question'), style: serif(22, 28, p.ink)),
          const SizedBox(height: 8),
          Text(Strings.keepOrDeleteBody(_name), style: sans(15, 21, p.ink2)),
          const SizedBox(height: 20),
          SheetButtons(
            palette: p,
            left: PillBtn(key: const Key('hand-over-delete'), label: Strings.delete, palette: p, kind: PillKind.quiet, height: 48, fontSize: 16, onTap: widget.onDelete),
            right: PillBtn(key: const Key('hand-over-keep'), label: Strings.keep, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: widget.onClose),
          ),
        ] else ...[
          const SizedBox(height: 20),
          PillBtn(key: const Key('hand-over-keep'), label: Strings.done, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: widget.onClose),
        ],
      ]);
}

/// A ring of small lights on the night: the hand-over card's picture (B1-10).
class RingThumb extends StatelessWidget {
  const RingThumb({super.key, required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: palette.ground, borderRadius: BorderRadius.circular(16)),
          child: CustomPaint(painter: _RingPainter(palette)),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p);
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // a shallow arc, as the ring crosses the sky, with lights along it brightening to the newest
    final path = Path()
      ..moveTo(0, h * .58)
      ..quadraticBezierTo(w * .5, h * .70, w, h * .52);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = p.light.withValues(alpha: .45));
    final metric = path.computeMetrics().first;
    for (var i = 0; i < 5; i++) {
      final t = .1 + i * .2;
      final at = metric.getTangentForOffset(metric.length * t)!.position;
      final r = 1.6 + i * .5;
      canvas.drawCircle(at, r * 3, Paint()..color = p.light.withValues(alpha: .12 + i * .03));
      canvas.drawCircle(at, r, Paint()..color = Color.lerp(p.light, const Color(0xFFFFF0CD), i / 4)!);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p;
}
