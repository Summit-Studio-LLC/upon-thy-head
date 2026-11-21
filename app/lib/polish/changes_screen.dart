import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';

import '../data/blessing.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/swap_text.dart';
import 'change.dart';
import 'model.dart';

/// The changes screen (the prototype's "Review changes", design/prototype/shots/05-review-changes.png):
/// the polished words with every change marked, by size, and a sheet to step through them, restore
/// the original words or keep the polished ones. Each choice is saved at once ([onSave]).
///
/// Colour never stands alone: each size has its own underline (light dotted, moderate dashed, heavy
/// wavy), and a restored change is the original words over a thin solid line.
class ChangesLayer extends StatefulWidget {
  const ChangesLayer({
    super.key,
    required this.palette,
    required this.blessing,
    required this.on,
    required this.onSave,
    required this.onDone,
  });

  final Palette palette;
  final Blessing? blessing;
  final bool on;
  final Future<void> Function() onSave;

  /// Done, and the back chevron: back where the screen was opened from.
  final VoidCallback onDone;

  @override
  State<ChangesLayer> createState() => ChangesLayerState();
}

/// The colour of each size (the prototype's --e1, --e2, --e3); always with its own underline.
Color changeColor(ChangeSize s) => switch (s) {
      ChangeSize.light => const Color(0xFF9CC58D),
      ChangeSize.moderate => const Color(0xFFE8A552),
      ChangeSize.heavy => const Color(0xFFEC8672),
    };

String sizeWord(ChangeSize s) => switch (s) {
      ChangeSize.light => Strings.sizeLight,
      ChangeSize.moderate => Strings.sizeModerate,
      ChangeSize.heavy => Strings.sizeHeavy,
    };

String sizeChange(ChangeSize s) => switch (s) {
      ChangeSize.light => Strings.changeLight,
      ChangeSize.moderate => Strings.changeModerate,
      ChangeSize.heavy => Strings.changeHeavy,
    };

String kindWords(ChangeKind k) => switch (k) {
      ChangeKind.filler => Strings.kindFiller,
      ChangeKind.repeat => Strings.kindRepeat,
      ChangeKind.reworded => Strings.kindReworded,
      ChangeKind.grammar => Strings.kindGrammar,
      ChangeKind.punctuation => Strings.kindPunctuation,
    };

/// What a change did, in words. The phone's model makes only punctuation (with capitals and
/// paragraphs) and one word for another (stored as `grammar`, so files stay readable by every
/// version); these are named by what they did.
String changeWords(Change c) {
  if (c.source != ModelSource.name) return kindWords(c.kind);
  if (c.kind == ChangeKind.grammar) return Strings.kindWord;
  if (c.kind != ChangeKind.punctuation) return kindWords(c.kind);
  if (c.now.contains('\n') && !c.was.contains('\n')) return Strings.kindParagraph;
  if (c.now.toLowerCase() == c.was.toLowerCase()) return Strings.kindCapital;
  return Strings.kindPunctuation;
}

/// The underline of a change (the prototype's `.e`: 2 px, 6 px under the text): drawn from [x0] to
/// [x1] under the line whose baseline is at [baseline]. [size] null: a restored change, a thin
/// solid line in [color].
void paintChangeLine(Canvas canvas, double x0, double x1, double baseline, ChangeSize? size, Color color) {
  final w = x1 - x0;
  if (w <= 0) return;
  final paint = Paint()..color = color;
  const top = 6.5; // below the baseline, as Safari and Chrome draw text-underline-offset: 6px
  switch (size) {
    case null:
      canvas.drawRect(Rect.fromLTWH(x0, baseline + top, w, 1), paint);
    case ChangeSize.light:
      // dots of 2, every 4
      for (var x = x0; x + 2 <= x1 + .5; x += 4) {
        canvas.drawRect(Rect.fromLTWH(x, baseline + top, 2, 2), paint);
      }
    case ChangeSize.moderate:
      // dashes of 6, the gaps (about 4) stretched so the line starts and ends with a dash
      const dash = 6.0, gap0 = 4.0;
      final n = math.max(1, ((w + gap0) / (dash + gap0)).round());
      final gap = n > 1 ? (w - n * dash) / (n - 1) : 0.0;
      for (var i = 0; i < n; i++) {
        final x = x0 + i * (dash + gap);
        canvas.drawRect(Rect.fromLTWH(x, baseline + top, math.min(dash, x1 - x), 2), paint);
      }
    case ChangeSize.heavy:
      // a wave 1.5 thick, 11 long, rising 1.9 either side
      const centre = 9.8, amp = 1.9, length = 11.0;
      final path = Path();
      for (var x = x0; x <= x1; x += .5) {
        final y = baseline + centre + amp * math.cos(2 * math.pi * (x - x0 - 2.5) / length);
        x == x0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
  }
}

/// The caret where words were left out (the prototype's `.cut`: 11 × 8 under the baseline).
void paintCaret(Canvas canvas, double left, double baseline, Color color) {
  final top = baseline - 2;
  final path = Path()
    ..moveTo(left + 1.5, top + 6.67)
    ..lineTo(left + 5.5, top + 1.33)
    ..lineTo(left + 9.5, top + 6.67);
  canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
}

/// A label with a change's underline under it: the legend's "light", the sheet's "Heavy change".
class MarkedLabel extends StatelessWidget {
  const MarkedLabel(this.text, {super.key, required this.style, required this.size});
  final String text;
  final TextStyle style;
  final ChangeSize size;

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: CustomPaint(size: tp.size, painter: _MarkedLabelPainter(tp, size)),
    );
  }
}

class _MarkedLabelPainter extends CustomPainter {
  _MarkedLabelPainter(this.tp, this.level);
  final TextPainter tp;
  final ChangeSize level;

  @override
  void paint(Canvas canvas, Size size) {
    tp.paint(canvas, Offset.zero);
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    paintChangeLine(canvas, 0, tp.width, base, level, changeColor(level));
  }

  @override
  bool shouldRepaint(_MarkedLabelPainter old) => old.tp.text != tp.text || old.level != level;
}

// ---- the words, laid out ----

/// Stands where words were left out: a no-break space stretched to the caret's 12 points (1 of
/// margin, 11 of caret), so the caret keeps to the word before it.
const _cutChar = ' ';

class _Piece {
  _Piece(this.text, {this.n, this.cut = false});
  final String text;
  final int? n; // the change, or null for the spoken words between changes
  final bool cut;
}

class _Span {
  _Span(this.n, this.start, this.end, this.cut);
  final int n, start, end;
  final bool cut;
}

class _Para {
  _Para(this.tp, this.top, this.spans, this.pieces);
  final TextPainter tp;
  final double top;
  final List<_Span> spans;

  /// Its pieces as (start, end, piece) within its text.
  final List<(int, int, _Piece)> pieces;

  late final List<LineMetrics> lines = tp.computeLineMetrics();

  double baselineAt(double y) {
    var top = 0.0;
    for (final l in lines) {
      if (y < top + l.height) return l.baseline;
      top += l.height;
    }
    return lines.isEmpty ? 0 : lines.last.baseline;
  }

  ({double top, double height}) lineAt(double y) {
    var top = 0.0;
    for (final l in lines) {
      if (y < top + l.height) return (top: top, height: l.height);
      top += l.height;
    }
    return (top: top, height: lines.isEmpty ? 0 : lines.last.height);
  }

  List<TextBox> boxes(int start, int end) =>
      tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end), boxHeightStyle: BoxHeightStyle.tight);
}

class _Layout {
  _Layout(this.paras, this.height);
  final List<_Para> paras;
  final double height;
}

/// A word (or the caret) where it sits, for the motion when changes are restored or kept.
class _Tok {
  _Tok(this.text, this.x, this.baseline, this.style, {this.n, this.cut = false, this.ch = false});
  final String text;
  final double x, baseline;
  final TextStyle style;
  final int? n;
  final bool cut, ch;
  TextPainter? _tp;
  TextPainter tp(TextScaler s) => _tp ??= TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: s)..layout();
}

class _Flip {
  _Flip(this.items);

  /// (token, dx, dy, kind): kind 0 moves from (dx, dy) to its place; 1 fades out; 2 fades in.
  final List<(_Tok, double, double, int)> items;
}

class ChangesLayerState extends State<ChangesLayer> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  int _sel = 0, _shown = 0, _dir = 1;
  Timer? _swap;
  // made in initState, not lazily: a lazy one first touched in dispose would look up the tree there
  late final AnimationController _out, _in, _flipC;
  _Flip? _flip;
  _Layout? _layout;
  String? _layoutKey;
  double _width = 0;
  TextScaler _scaler = TextScaler.noScaling;
  double _nbsp = 0;
  String? _id;

  Blessing? get _b => widget.blessing;
  List<Change> get _changes => _b?.changes ?? const [];
  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The change selected, for tests.
  int get selected => _sel;

  @override
  void initState() {
    super.initState();
    _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 130));
    _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
    _flipC = AnimationController(vsync: this, duration: const Duration(milliseconds: 540))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() => _flip = null);
      });
    if (widget.on) WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(ChangesLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && (!oldWidget.on || widget.blessing?.id != _id)) _open();
  }

  @override
  void dispose() {
    _swap?.cancel();
    _out.dispose();
    _in.dispose();
    _flipC.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open() {
    _id = _b?.id;
    _sel = _shown = 0;
    _swap?.cancel();
    _out.value = 0;
    _in.value = 1;
    _flipC.stop();
    _flip = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (mounted) setState(() {});
  }

  // ---- choosing a change ----

  /// Select change [i] (wrapping round). The sheet's words slide out the way you are going and the
  /// next slide in behind them; the change is scrolled into view.
  void select(int i, {int? dir, bool instant = false}) {
    final n = _changes.length;
    if (n == 0) return;
    final prev = _sel;
    _sel = ((i % n) + n) % n;
    _swap?.cancel();
    if (instant || _still || prev == _sel) {
      _shown = _sel;
      _out.value = 0;
      _in.value = 1;
    } else {
      _dir = dir ?? (_sel > prev ? 1 : -1);
      _in.value = 1;
      _out.forward(from: 0);
      _swap = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _shown = _sel);
        _out.value = 0;
        _in.forward(from: 0);
      });
    }
    setState(() {});
    _reveal(instant: instant || _still);
  }

  /// Scroll the selected change to the middle when it is near the top or under the sheet.
  void _reveal({required bool instant}) {
    final l = _layout;
    if (l == null || !_scroll.hasClients) return;
    double? y;
    for (final p in l.paras) {
      for (final s in p.spans.where((s) => s.n == _sel)) {
        final b = p.boxes(s.start, s.end);
        if (b.isNotEmpty) y ??= p.top + b.first.top;
      }
    }
    if (y == null) return;
    final top = _wordsTop(context);
    final at = top + y - _scroll.offset;
    if (at >= 190 && at <= 500) return;
    final to = (_scroll.offset + at - 340).clamp(0.0, _scroll.position.maxScrollExtent);
    if (instant) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(to, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  // ---- restoring and keeping ----

  /// Restore ([keep] false) or keep the changes [ns], and let it be seen: the words that stay glide
  /// to where they now belong, the old words fade and the new ones arrive.
  void _set(List<int> ns, bool keep) {
    final b = _b;
    if (b == null) return;
    final changed = {for (final n in ns) if (b.changes[n].kept != keep) n};
    if (changed.isEmpty) return;
    final before = _still || _layout == null ? null : _tokens(_layout!, changed);
    for (final n in changed) {
      b.changes[n].kept = keep;
    }
    if (before != null) {
      final after = _tokens(_build(b), changed);
      final a = before.where((t) => !t.ch).toList(), z = after.where((t) => !t.ch).toList();
      if (a.length == z.length) {
        final items = <(_Tok, double, double, int)>[];
        for (var k = 0; k < z.length; k++) {
          final dx = a[k].x - z[k].x, dy = a[k].baseline - z[k].baseline;
          if (dx.abs() > 1 && dy.abs() > 2) {
            // a word that changes line dissolves, so it never flies across the others
            items
              ..add((a[k], 0, 0, 1))
              ..add((z[k], 0, 0, 2));
          } else {
            items.add((z[k], dx, dy, 0));
          }
        }
        for (final t in before.where((t) => t.ch)) {
          items.add((t, 0, 0, 1));
        }
        for (final t in after.where((t) => t.ch)) {
          items.add((t, 0, 0, 2));
        }
        _flip = _Flip(items);
        _flipC.forward(from: 0);
      } else {
        _flip = null;
      }
    }
    setState(() {});
    unawaited(widget.onSave());
  }

  void _restoreOrUse() => _set([_sel], !_changes[_sel].kept);

  void _all() {
    final anyKept = _changes.any((c) => c.kept);
    _set([for (var i = 0; i < _changes.length; i++) i], !anyKept);
  }

  // ---- layout ----

  double _wordsTop(BuildContext context) => 168 + math.max(62.0, MediaQuery.viewPaddingOf(context).top) - 62;

  TextStyle get _wordStyle => serif(19, 30, widget.palette.ink).copyWith(
        fontFeatures: const [FontFeature.oldstyleFigures()],
        leadingDistribution: TextLeadingDistribution.even,
      );

  _Layout _build(Blessing b) {
    final p = widget.palette;
    final base = _wordStyle;
    final raw = b.rawText;
    // the display: the spoken words with each change as it now stands
    final order = [for (var i = 0; i < b.changes.length; i++) i]..sort((x, y) => b.changes[x].start.compareTo(b.changes[y].start));
    final pieces = <_Piece>[];
    var at = 0;
    for (final n in order) {
      final c = b.changes[n];
      if (c.start < at || c.end > raw.length || raw.substring(c.start, c.end) != c.was) continue;
      if (c.start > at) pieces.add(_Piece(raw.substring(at, c.start)));
      if (c.kept && c.now.isEmpty) {
        pieces.add(_Piece(_cutChar, n: n, cut: true));
      } else {
        pieces.add(_Piece((c.kept ? c.now : c.was).replaceAll('\n', ' '), n: n));
      }
      at = c.end;
    }
    if (at < raw.length) pieces.add(_Piece(raw.substring(at)));
    // where each piece sits in the whole
    final whole = StringBuffer();
    final ranges = <(int, int, _Piece)>[];
    for (final pc in pieces) {
      ranges.add((whole.length, whole.length + pc.text.length, pc));
      whole.write(pc.text);
    }
    final text = whole.toString();
    // paragraphs: split at blank lines in the spoken words, as the reading page does
    final paraRanges = <(int, int)>[];
    var from = 0;
    for (final m in RegExp(r'\n[ \t\r\n]*\n').allMatches(text)) {
      if (ranges.any((r) => r.$3.n != null && r.$1 < m.end && m.start < r.$2)) continue;
      paraRanges.add((from, m.start));
      from = m.end;
    }
    paraRanges.add((from, text.length));
    bool space(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
    final paras = <_Para>[];
    var y = 0.0;
    for (var (s, e) in paraRanges) {
      while (s < e && space(text.codeUnitAt(s))) {
        s++;
      }
      while (e > s && space(text.codeUnitAt(e - 1))) {
        e--;
      }
      if (s >= e) continue;
      final children = <InlineSpan>[];
      final spans = <_Span>[];
      final local = <(int, int, _Piece)>[];
      for (final (rs, re, pc) in ranges) {
        final a = math.max(rs, s), z = math.min(re, e);
        if (a >= z) continue;
        final str = text.substring(a, z);
        final TextStyle style;
        if (pc.cut) {
          style = base.copyWith(color: const Color(0x00000000), letterSpacing: 12 - _nbsp);
        } else if (pc.n != null && !b.changes[pc.n!].kept) {
          style = base.copyWith(color: p.ink2);
        } else {
          style = base;
        }
        children.add(TextSpan(text: str, style: style));
        if (pc.n != null) spans.add(_Span(pc.n!, a - s, z - s, pc.cut));
        local.add((a - s, z - s, pc));
      }
      final tp = TextPainter(text: TextSpan(children: children, style: base), textDirection: TextDirection.ltr, textScaler: _scaler)
        ..layout(maxWidth: _width);
      if (paras.isNotEmpty) y += _scaler.scale(15);
      paras.add(_Para(tp, y, spans, local));
      y += tp.height;
    }
    return _Layout(paras, y);
  }

  _Layout _layoutFor(Blessing b) {
    final key = '${b.rawText.hashCode}|${[for (final c in b.changes) '${c.start}:${c.kept}'].join(',')}|$_width|${_scaler.scale(19)}';
    if (key != _layoutKey || _layout == null) {
      _layout = _build(b);
      _layoutKey = key;
    }
    return _layout!;
  }

  /// Every word and caret on the page, where it sits; [ch]: those in the changes being changed.
  List<_Tok> _tokens(_Layout l, Set<int> changing) {
    final out = <_Tok>[];
    final word = RegExp(r'\S+');
    for (final p in l.paras) {
      final text = p.tp.plainText;
      for (final (s, e, pc) in p.pieces) {
        final style = _styleAt(p, s);
        final ch = pc.n != null && changing.contains(pc.n);
        if (pc.cut) {
          final bx = p.boxes(s, e);
          if (bx.isEmpty) continue;
          out.add(_Tok('', bx.first.left, p.top + p.baselineAt((bx.first.top + bx.first.bottom) / 2), style, n: pc.n, cut: true, ch: ch));
          continue;
        }
        final seg = text.substring(s, e);
        for (final m in word.allMatches(seg)) {
          final a = s + m.start, z = s + m.end;
          final bx = p.boxes(a, z);
          if (bx.isEmpty) continue;
          // inside a change, a word keeps the space after it, so its line runs on to the next
          final t = m.group(0)! + (pc.n != null && seg.substring(m.end).trim().isNotEmpty ? ' ' : '');
          out.add(_Tok(t, bx.first.left, p.top + p.baselineAt((bx.first.top + bx.first.bottom) / 2), style, n: pc.n, ch: ch));
        }
      }
    }
    return out;
  }

  TextStyle _styleAt(_Para p, int offset) {
    final span = p.tp.text!.getSpanForPosition(TextPosition(offset: offset));
    return (span is TextSpan ? span.style : null) ?? _wordStyle;
  }

  // ---- building ----

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = _b;
    final mq = MediaQuery.of(context);
    final dy = math.max(62.0, mq.viewPadding.top) - 62;
    if (b == null || b.changes.isEmpty) return ColoredBox(color: p.ground);
    if (_sel >= b.changes.length) _sel = _shown = 0;
    final scaler = MediaQuery.textScalerOf(context);
    if (_nbsp == 0 || scaler != _scaler) {
      _scaler = scaler;
      _nbsp = (TextPainter(text: TextSpan(text: _cutChar, style: _wordStyle), textDirection: TextDirection.ltr, textScaler: scaler)..layout()).width;
    }
    final kept = b.changes.where((c) => c.kept).length, n = b.changes.length;
    final count = kept == n ? Strings.changes(n) : kept == 0 ? Strings.originalWords : Strings.keptOf(kept, n);
    final sizes = {for (final c in b.changes) c.size}.toList()..sort((x, y) => x.index.compareTo(y.index));
    return ColoredBox(
      color: p.ground,
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth - 56;
        final layout = _layoutFor(b);
        return Stack(children: [
          Positioned.fill(
            child: SingleChildScrollView(
              key: const Key('changes-scroll'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(28, 168 + dy, 28, 300 * math.max(1, scaler.scale(1))),
              child: _words(p, b, layout),
            ),
          ),
          // the top goes solid under the bar and the legend
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 164 + dy,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.ground, p.ground, p.ground.withValues(alpha: 0)],
                    stops: const [0, .86, 1],
                  ),
                ),
              ),
            ),
          ),
          // the bar: back, the count, Done
          Positioned(
            left: 0,
            right: 0,
            top: 54 + dy,
            height: 44,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Stack(children: [
                Positioned.fill(
                  child: Center(
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: SwapText(count, textKey: const Key('changes-count'), style: serif(20, 44, p.ink).copyWith(leadingDistribution: TextLeadingDistribution.even), textAlign: TextAlign.center),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 0,
                  child: IconBtn(key: const Key('changes-back'), icon: Glyph.older, color: p.ink, palette: p, semantics: Strings.back, onTap: widget.onDone),
                ),
                Positioned(right: 12, top: 0, child: LightTextBtn(key: const Key('changes-done'), label: Strings.done, palette: p, onTap: widget.onDone)),
              ]),
            ),
          ),
          // the legend: the sizes in this blessing, and Restore all / Use polished
          Positioned(
            left: 28,
            right: 28,
            top: 104 + dy,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Container(
                padding: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.ink.withValues(alpha: .10)))),
                child: Row(children: [
                  for (var i = 0; i < sizes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 20),
                    MarkedLabel(sizeWord(sizes[i]), key: Key('legend-${sizes[i].code}'), style: sans(13, 20, p.ink2), size: sizes[i]),
                  ],
                  const Spacer(),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
          // Restore all / Use polished: on the legend's line, with a 44-point target round it
          Positioned(
            right: 28,
            top: 92 + dy,
            height: 44,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: _AllButton(
                key: const Key('changes-all'),
                label: kept == 0 ? Strings.usePolished : Strings.restoreAll,
                palette: p,
                onTap: _all,
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _sheet(p, b)),
        ]);
      }),
    );
  }

  Widget _words(Palette p, Blessing b, _Layout l) {
    return SizedBox(
      key: const Key('changes-words'),
      width: _width,
      height: l.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final n = _hit(l, d.localPosition);
          if (n != null) select(n);
        },
        child: CustomPaint(
          painter: _WordsPainter(
            layout: l,
            changes: b.changes,
            sel: _sel,
            palette: p,
            flip: _flip,
            flipT: _flipC,
            scaler: _scaler,
            labelFor: _label,
            onTap: select,
          ),
        ),
      ),
    );
  }

  String _label(int n) {
    final c = _changes[n];
    return Strings.changeLabel(sizeChange(c.size), changeWords(c), c.shownWas, c.shownNow, c.kept);
  }

  int? _hit(_Layout l, Offset at) {
    for (final p in l.paras) {
      for (final s in p.spans) {
        for (final bx in p.boxes(s.start, s.end)) {
          final line = p.lineAt((bx.top + bx.bottom) / 2);
          final r = Rect.fromLTRB(bx.left - (s.cut ? 10 : 2), p.top + line.top, bx.right + (s.cut ? 10 : 2), p.top + line.top + line.height);
          if (r.contains(at)) return s.n;
        }
      }
    }
    return null;
  }

  Widget _sheet(Palette p, Blessing b) {
    final cur = b.changes[_sel];
    return Container(
      key: const Key('changes-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 38),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: p.ink.withValues(alpha: .07), offset: const Offset(0, -1))],
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_out, _in]),
        builder: (context, _) {
          final shown = b.changes[_shown.clamp(0, b.changes.length - 1)];
          double op, dx;
          if (_out.value > 0) {
            final t = Curves.easeIn.transform(_out.value);
            op = 1 - t;
            dx = -16 * _dir * t;
          } else {
            final u = _in.value;
            op = easeOut.transform((u * 320 / 260).clamp(0.0, 1.0));
            dx = 16 * _dir * (1 - easeOut.transform(u));
          }
          final label = sans(13, 20, p.ink2);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // the row is 28 high; the 36-point step buttons stand out of it, as in the prototype
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 120),
                    child: Opacity(
                      opacity: op,
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
                            MarkedLabel(sizeChange(shown.size), key: const Key('sheet-size'), style: sans(13, 20, p.ink), size: shown.size),
                            Text(' ${changeWords(shown)}', key: const Key('sheet-kind'), style: label),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -10,
                    top: -4,
                    bottom: -4,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconBtn(
                        key: const Key('sheet-prev'),
                        icon: Glyph.older,
                        color: p.ink2,
                        palette: p,
                        size: 36,
                        iconSize: 20,
                        semantics: Strings.previousChange,
                        onTap: () => select(_sel - 1, dir: -1),
                      ),
                      const SizedBox(width: 2),
                      Opacity(
                        opacity: op,
                        child: Text(Strings.stepOf(_shown + 1, b.changes.length),
                            key: const Key('sheet-step'), style: label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                      const SizedBox(width: 2),
                      IconBtn(
                        key: const Key('sheet-next'),
                        icon: Glyph.newer,
                        color: p.ink2,
                        palette: p,
                        size: 36,
                        iconSize: 20,
                        semantics: Strings.nextChange,
                        onTap: () => select(_sel + 1, dir: 1),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: op,
                child: Transform.translate(
                  offset: Offset(dx, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 90),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _pairRow(p, Strings.original, Text(shown.shownWas, key: const Key('sheet-was'), style: serif(18, 26, p.ink2, italic: true).copyWith(leadingDistribution: TextLeadingDistribution.even))),
                      const SizedBox(height: 10),
                      _pairRow(
                        p,
                        Strings.polished,
                        shown.now.isEmpty
                            ? Text(Strings.leftOut, key: const Key('sheet-now'), style: serif(18, 26, p.ink3, italic: true).copyWith(leadingDistribution: TextLeadingDistribution.even))
                            : Text(shown.shownNow, key: const Key('sheet-now'), style: serif(18, 26, p.ink).copyWith(leadingDistribution: TextLeadingDistribution.even)),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: PillBtn(
                    key: const Key('sheet-restore'),
                    label: cur.kept ? Strings.restoreOriginal : Strings.usePolished,
                    palette: p,
                    kind: PillKind.tonal,
                    height: 48,
                    fontSize: 16,
                    fadeLabel: true,
                    onTap: _restoreOrUse,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillBtn(
                    key: const Key('sheet-keep'),
                    label: cur.kept ? Strings.keep : Strings.next,
                    palette: p,
                    kind: PillKind.primary,
                    height: 48,
                    fontSize: 16,
                    fadeLabel: true,
                    onTap: () => select(_sel + 1, dir: 1),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _pairRow(Palette p, String label, Widget value) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // at least 76 wide; wider when the text size makes the label longer, never split mid-word
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 76),
          child: Text(label, softWrap: false, style: sans(13, 26, p.ink3).copyWith(leadingDistribution: TextLeadingDistribution.even)),
        ),
        const SizedBox(width: 12),
        Expanded(child: value),
      ]);
}

/// "Restore all" / "Use polished": a word in the light colour over a faint line.
class _AllButton extends StatefulWidget {
  const _AllButton({super.key, required this.label, required this.palette, required this.onTap});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_AllButton> createState() => _AllButtonState();
}

class _AllButtonState extends State<_AllButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final style = sans(13, 20, p.light).copyWith(
      decoration: TextDecoration.underline,
      decorationColor: p.light.withValues(alpha: _down ? 1 : .45),
    );
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
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12),
          alignment: Alignment.centerRight,
          child: SwapText(widget.label, textKey: const Key('changes-all-text'), style: style),
        ),
      ),
    );
  }
}

class _WordsPainter extends CustomPainter {
  _WordsPainter({
    required this.layout,
    required this.changes,
    required this.sel,
    required this.palette,
    required this.flip,
    required this.flipT,
    required this.scaler,
    required this.labelFor,
    required this.onTap,
  }) : super(repaint: flipT);

  final _Layout layout;
  final List<Change> changes;
  final int sel;
  final Palette palette;
  final _Flip? flip;
  final AnimationController flipT;
  final TextScaler scaler;
  final String Function(int) labelFor;
  final void Function(int) onTap;

  static const _ease = Cubic(.25, .1, .25, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final f = flip;
    if (f != null && flipT.isAnimating) {
      _paintFlip(canvas, f, flipT.value * 540);
      return;
    }
    for (final p in layout.paras) {
      canvas.save();
      canvas.translate(0, p.top);
      // the selected change, faintly lit behind
      for (final s in p.spans.where((s) => s.n == sel)) {
        final c = changes[s.n];
        final bg = Paint()..color = changeColor(c.size).withValues(alpha: .20);
        for (final bx in p.boxes(s.start, s.end)) {
          final base = p.baselineAt((bx.top + bx.bottom) / 2);
          final r = s.cut ? Rect.fromLTWH(bx.left + 1, base - 19, 11, 19) : Rect.fromLTRB(bx.left - 1, bx.top - 2, bx.right + 1, bx.bottom + 2);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), bg);
        }
      }
      p.tp.paint(canvas, Offset.zero);
      for (final s in p.spans) {
        final c = changes[s.n];
        for (final bx in p.boxes(s.start, s.end)) {
          final base = p.baselineAt((bx.top + bx.bottom) / 2);
          if (s.cut) {
            paintCaret(canvas, bx.left + 1, base, changeColor(c.size));
          } else if (c.kept) {
            paintChangeLine(canvas, bx.left, bx.right, base, c.size, changeColor(c.size));
          } else {
            paintChangeLine(canvas, bx.left, bx.right, base, null, palette.ink3);
          }
        }
      }
      canvas.restore();
    }
  }

  void _paintFlip(Canvas canvas, _Flip f, double ms) {
    double clamp(double v) => v.clamp(0.0, 1.0);
    for (final (t, dx, dy, kind) in f.items) {
      final double op;
      var x = t.x, y = t.baseline;
      switch (kind) {
        case 0:
          final k = 1 - easeOut.transform(clamp(ms / 500));
          x += dx * k;
          y += dy * k;
          op = 1;
        case 1:
          op = 1 - _ease.transform(clamp(ms / 200));
        default:
          op = _ease.transform(clamp((ms - 160) / 340));
      }
      if (op <= 0) continue;
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, op));
      final c = t.n == null ? null : changes[t.n!];
      if (t.cut) {
        if (t.n == sel) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y - 19, 11, 19), const Radius.circular(4)),
              Paint()..color = changeColor(c!.size).withValues(alpha: .20));
        }
        paintCaret(canvas, x + 1, y, changeColor(c!.size));
      } else {
        final tp = t.tp(scaler);
        final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        if (c != null && t.n == sel) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - base, tp.width, tp.height), const Radius.circular(4)),
              Paint()..color = changeColor(c.size).withValues(alpha: .20));
        }
        tp.paint(canvas, Offset(x, y - base));
        if (c != null) {
          // as it is drawn in the words: a restored change in ink2, over a thin line
          final restored = t.style.color == palette.ink2;
          paintChangeLine(canvas, x, x + tp.width, y, restored ? null : c.size, restored ? palette.ink3 : changeColor(c.size));
        }
      }
      canvas.restore();
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final out = <CustomPainterSemantics>[];
        for (final p in layout.paras) {
          out.add(CustomPainterSemantics(
            rect: Rect.fromLTWH(0, p.top, size.width, p.tp.height),
            properties: SemanticsProperties(label: p.tp.plainText.replaceAll(_cutChar, ''), textDirection: TextDirection.ltr),
          ));
          for (final s in p.spans) {
            final bx = p.boxes(s.start, s.end);
            if (bx.isEmpty) continue;
            var r = Rect.fromLTRB(bx.first.left, bx.first.top, bx.first.right, bx.first.bottom);
            for (final b in bx.skip(1)) {
              r = r.expandToInclude(Rect.fromLTRB(b.left, b.top, b.right, b.bottom));
            }
            final n = s.n;
            out.add(CustomPainterSemantics(
              key: ValueKey('change-$n'),
              rect: r.shift(Offset(0, p.top)).inflate(s.cut ? 10 : 2),
              properties: SemanticsProperties(
                button: true,
                selected: n == sel,
                label: labelFor(n),
                textDirection: TextDirection.ltr,
                onTap: () => onTap(n),
              ),
            ));
          }
        }
        return out;
      };

  @override
  bool shouldRebuildSemantics(_WordsPainter old) => true;

  @override
  bool shouldRepaint(_WordsPainter old) => true;
}
