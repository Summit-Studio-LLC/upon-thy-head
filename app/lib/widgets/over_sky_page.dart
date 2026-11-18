import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import 'icons.dart';

/// A page over the dimmed sky in the Settings family: the back chevron, a large serif title, a line
/// under it, and its rows ("To pass along", "Your links").
class OverSkyPage extends StatelessWidget {
  const OverSkyPage({
    super.key,
    required this.palette,
    required this.title,
    required this.lede,
    required this.children,
    required this.onBack,
    required this.backKey,
    this.scrollKey,
    this.titleKey,
  });

  final Palette palette;
  final String title, lede;
  final List<Widget> children;
  final VoidCallback onBack;
  final Key backKey;
  final Key? scrollKey, titleKey;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dy = math.max(62.0, MediaQuery.of(context).viewPadding.top) - 62;
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: ColoredBox(color: p.ground.withValues(alpha: .55)))),
      Positioned.fill(
        child: SingleChildScrollView(
          key: scrollKey,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(28, 112 + dy, 28, 64),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Title(title, key: titleKey, style: serif(34, 38, p.ink, tracking: -.012)),
            const SizedBox(height: 8),
            Text(lede, style: sans(15, 22, p.ink2)),
            const SizedBox(height: 24),
            Container(height: 1, color: p.ink.withValues(alpha: .10)),
            ...children,
          ]),
        ),
      ),
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
      Positioned(
        left: 4,
        top: 54 + dy,
        child: IconBtn(key: backKey, icon: Glyph.older, color: p.ink, palette: p, semantics: Strings.back, onTap: onBack),
      ),
    ]);
  }
}

/// The page's title at the phone's text size, except that no word of it is ever broken across
/// lines: at the largest sizes the size steps down just enough for its longest word to fit.
class _Title extends StatelessWidget {
  const _Title(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      var widest = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        final tp = TextPainter(text: TextSpan(text: word, style: style), textScaler: scaler, textDirection: Directionality.of(context), maxLines: 1)..layout();
        widest = math.max(widest, tp.width);
        tp.dispose();
      }
      final fit = widest > box.maxWidth && widest > 0 ? box.maxWidth / widest * .98 : 1.0;
      return Text(text, style: style, textScaler: fit < 1 ? TextScaler.linear(scaler.scale(style.fontSize!) / style.fontSize! * fit) : scaler);
    });
  }
}

/// A row that opens something: its words, and a chevron.
class OpenRow extends StatefulWidget {
  const OpenRow({super.key, required this.palette, required this.semantics, required this.child, required this.onTap});
  final Palette palette;
  final String semantics;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<OpenRow> createState() => _OpenRowState();
}

class _OpenRowState extends State<OpenRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.semantics,
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
          color: p.ink.withValues(alpha: _down ? .05 : 0),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            Expanded(child: widget.child),
            const SizedBox(width: 12),
            SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.forward, color: p.ink3)),
          ]),
        ),
      ),
    );
  }
}
