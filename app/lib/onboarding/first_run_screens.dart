import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../data/blessing.dart';
import '../record/model_offer.dart';
import '../record/session.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/scrims.dart';
import 'first_run.dart';

/// The first run's screens, drawn over the sky (design/onboarding/). The sky itself (its rising,
/// the ring's sweep, the dimming between screens) is moved by the home screen.

/// The widest the words run on a wide screen (iPad): the column stays a comfortable reading width.
const double firstRunColumn = 460;

/// The words of a first-run screen, from the bottom up so they grow upward at large text sizes,
/// in one column of comfortable width; scrolls only if they no longer fit.
class FirstRunFrame extends StatelessWidget {
  const FirstRunFrame({super.key, required this.palette, required this.child, this.scrim = true});
  final Palette palette;
  final Widget child;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Stack(children: [
      if (scrim) Positioned(left: 0, right: 0, bottom: 0, height: 460, child: BottomScrim(palette: palette)),
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, mq.viewPadding.top + 24, 28, 42 + mq.viewPadding.bottom * .5),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: firstRunColumn), child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// The app can be seen: false while it is inactive or away (a system question over it, Control
/// Centre, the app switcher). The opening and the welcome wait while it is false. Set by the home
/// screen from the app's lifecycle.
final ValueNotifier<bool> firstRunVisible = ValueNotifier(true);

/// A one-shot timer that stops counting while [firstRunVisible] is false, and goes on from where
/// it was when it is true again. It counts in small steps of plain timers (no stopwatch), so a
/// test's clock drives it as it drives everything else.
class PausableTimer {
  PausableTimer(Duration duration, this._callback) : _left = duration.inMilliseconds {
    firstRunVisible.addListener(_changed);
    _changed();
  }

  static const _step = 50;
  final VoidCallback _callback;
  int _left;
  Timer? _timer;
  bool _done = false;

  bool get isActive => !_done;

  void _changed() {
    if (_done) return;
    if (!firstRunVisible.value) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= _next();
    }
  }

  Timer _next() => Timer(Duration(milliseconds: _left.clamp(0, _step)), () {
        _left -= _step;
        if (_left > 0) {
          _timer = _next();
          return;
        }
        cancel();
        _callback();
      });

  void cancel() {
    _done = true;
    _timer?.cancel();
    _timer = null;
    firstRunVisible.removeListener(_changed);
  }
}

/// Animations under it stand still while the app cannot be seen ([firstRunVisible]).
class WhileVisible extends StatelessWidget {
  const WhileVisible({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: firstRunVisible,
        builder: (context, on, child) => TickerMode(enabled: on, child: child!),
        child: child,
      );
}

/// Arrives after [delay]: fades in and rises a little (only fades in with Reduce Motion).
class Arrive extends StatefulWidget {
  const Arrive({super.key, required this.delay, required this.child, this.rise = 10, this.duration = const Duration(milliseconds: 900)});
  final Duration delay, duration;
  final double rise;
  final Widget child;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> {
  bool _on = false;
  PausableTimer? _t;

  @override
  void initState() {
    super.initState();
    _t = PausableTimer(widget.delay, () {
      if (mounted) setState(() => _on = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedOpacity(
      opacity: _on ? 1 : 0,
      duration: widget.duration,
      curve: easeOut,
      child: AnimatedSlide(
        offset: Offset(0, _on || still ? 0 : widget.rise / 100),
        duration: widget.duration,
        curve: easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---- 1 the opening ----

/// The name, arriving once the ring has crossed the sky. A tap anywhere moves on.
class OpeningLayer extends StatelessWidget {
  const OpeningLayer({super.key, required this.palette, required this.onTap});
  final Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      key: const Key('opening'),
      button: true,
      label: Strings.appName,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: const Alignment(0, .133),
          child: Arrive(
            delay: Duration(milliseconds: still ? 600 : 2300),
            duration: Duration(milliseconds: still ? 1000 : 800),
            rise: 15,
            child: Text(Strings.appName, style: serif(40, 46, palette.ink, tracking: -.01), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

// ---- 2 the welcome ----

class WelcomeLayer extends StatelessWidget {
  const WelcomeLayer({super.key, required this.palette, required this.onContinue});
  final Palette palette;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final still = MediaQuery.of(context).disableAnimations;
    // the opening's name is gone (its fade, [openingOut]) before the first line begins
    Duration at(int ms) => Duration(milliseconds: still ? openingOut.inMilliseconds + 150 : ms);
    final line = serif(25, 31, p.ink, tracking: -.008);
    return FirstRunFrame(
      key: const Key('welcome'),
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Arrive(delay: at(openingOut.inMilliseconds + 250), child: Text(Strings.welcome1, style: line)),
          const SizedBox(height: 18),
          // for children too (people/): one line, no screen of its own
          Arrive(delay: at(1500), child: Text(Strings.welcomeFamily, key: const Key('welcome-family'), style: line)),
          const SizedBox(height: 18),
          Arrive(delay: at(2300), child: Text(Strings.welcome2, style: line)),
          const SizedBox(height: 18),
          Arrive(delay: at(3200), child: Text(Strings.welcome3, style: line)),
          const SizedBox(height: 28),
          Arrive(delay: at(3900), child: Text(Strings.welcomeFree, key: const Key('welcome-free'), style: sans(15, 21, p.ink3))),
          const SizedBox(height: 36),
          Arrive(
            delay: at(4300),
            child: PillBtn(key: const Key('welcome-continue'), label: Strings.continueLabel, palette: p, kind: PillKind.primary, onTap: onContinue),
          ),
        ],
      ),
    );
  }
}

// ---- 3 the permissions ----

/// "A few things first": four rows, each with its own Allow; Continue once the two required rows
/// are answered (the owner's ruling, 2026-11-16).
class PermissionsLayer extends StatelessWidget {
  const PermissionsLayer({super.key, required this.palette, required this.state, required this.onContinue});
  final Palette palette;
  final FirstRunPermissions state;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final asking = state.asking;
        final open = state.canContinue;
        final needed = state.stillNeeded;
        final hint = needed.isEmpty
            ? ''
            : Strings.stillNeeded(microphone: needed.contains(PermissionKind.microphone), speech: needed.contains(PermissionKind.speech));
        return FirstRunFrame(
          key: const Key('permissions'),
          palette: p,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(Strings.permsTitle, style: serif(30, 34.5, p.ink, tracking: -.012))),
              const SizedBox(height: 10),
              Text(Strings.permsLede, style: sans(17, 25, p.ink2)),
              const SizedBox(height: 22),
              for (final r in state.rows)
                AnimatedOpacity(
                  // while a question is up, its row is the lit one
                  opacity: asking == null || asking == r.kind ? 1 : .32,
                  duration: const Duration(milliseconds: 350),
                  curve: easeOut,
                  child: PermissionRowView(
                    key: Key('row-${r.kind.name}'),
                    palette: p,
                    row: r,
                    onAllow: () => state.ask(r.kind),
                    onSettings: () => state.openSettings(r.kind),
                  ),
                ),
              const SizedBox(height: 18),
              // what is still needed before Continue; its room is kept so nothing jumps
              ExcludeSemantics(
                excluding: open || !state.loaded,
                child: AnimatedOpacity(
                  opacity: open || !state.loaded ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: Text(hint.isEmpty ? ' ' : hint, key: const Key('perms-needed'), style: sans(13, 18, p.ink2)),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedOpacity(
                opacity: open ? 1 : .35,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !open,
                  child: PillBtn(
                    key: const Key('permissions-continue'),
                    label: Strings.continueLabel,
                    palette: p,
                    kind: PillKind.primary,
                    enabled: open,
                    onTap: open ? onContinue : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One row: the icon at the left, the title (with Required or Optional) and its reason in the
/// middle, and at the right its own control: Allow, or the quiet tick once allowed. At large text
/// sizes the control drops beneath the words.
///
/// The control's room is the Allow button's, whatever it shows, so when a row is answered its words
/// keep their width and the row its height: nothing re-wraps and nothing below moves. Refused, the
/// row's "Off" and Settings go beneath its words, which still keep their width.
class PermissionRowView extends StatelessWidget {
  const PermissionRowView({super.key, required this.palette, required this.row, this.onAllow, this.onSettings});
  final Palette palette;
  final PermissionRow row;
  final VoidCallback? onAllow, onSettings;

  static const iconSize = 22.0;
  static const _iconGap = 14.0, _controlGap = 12.0;

  /// The least the words keep beside the control before it goes beneath them.
  static const minWords = 170.0;

  /// Decorative: the row's label already names it, so VoiceOver never reads the icon.
  Glyph get glyph => switch (row.kind) {
        PermissionKind.microphone => Glyph.microphone,
        PermissionKind.speech => row.title == Strings.notifications ? Glyph.bell : Glyph.writing,
        PermissionKind.location => Glyph.location,
        PermissionKind.lock => row.title == 'Face ID' ? Glyph.faceId : Glyph.lock,
      };

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final scaler = MediaQuery.textScalerOf(context);
    final lit = row.status == RowStatus.asking;
    final titleStyle = sans(15, 20, lit ? p.light : p.ink, weight: FontWeight.w500);
    final markStyle = sans(13, 20, row.required ? p.ink2 : p.ink3, tracking: .005);
    final lineStyle = sans(15, 21, p.ink2);
    final title = TextSpan(children: [
      TextSpan(text: row.title, style: titleStyle),
      TextSpan(text: '  ', style: markStyle),
      TextSpan(text: row.required ? Strings.requiredMark : Strings.optionalMark, style: markStyle),
    ]);
    final control = _RowControl(palette: p, row: row, onAllow: onAllow, onSettings: onSettings);
    final slot = control.slot(scaler);
    final off = row.status == RowStatus.off;

    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(builder: (context, box) {
          final words = box.maxWidth - iconSize - _iconGap;
          final beside = slot.width == 0 || words - _controlGap - slot.width >= minWords;
          final textWidth = beside && slot.width > 0 ? words - _controlGap - slot.width : words;
          // The icon and the control are centred on the block of the title and the reason's first
          // line, however either wraps, at every text size.
          final t = TextPainter(text: title, textScaler: scaler, textDirection: TextDirection.ltr)..layout(maxWidth: textWidth);
          final l = TextPainter(text: TextSpan(text: row.line, style: lineStyle), textScaler: scaler, textDirection: TextDirection.ltr)
            ..layout(maxWidth: textWidth);
          final metrics = l.computeLineMetrics();
          final firstLine = metrics.isEmpty ? scaler.scale(21) : metrics.first.height;
          final centre = (t.height + 2 + firstLine) / 2;
          t.dispose();
          l.dispose();
          final text = Semantics(
            container: true,
            label: row.semantics,
            excludeSemantics: true,
            liveRegion: lit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(title, key: const Key('row-title')),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(row.line, key: ValueKey(row.line), style: lineStyle),
                ),
              ],
            ),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _At(
                top: centre - iconSize / 2,
                child: SizedBox.square(
                  dimension: iconSize,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: lit ? p.light : p.ink2),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, c, _) => GlyphIcon(glyph, color: c ?? p.ink2),
                  ),
                ),
              ),
              const SizedBox(width: _iconGap),
              Expanded(
                child: beside && !off
                    ? text
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        text,
                        if (slot.width > 0) ...[
                          const SizedBox(height: 10),
                          off ? control : SizedBox(height: slot.height, child: Align(alignment: Alignment.centerLeft, child: control)),
                        ],
                      ]),
              ),
              if (beside && slot.width > 0) ...[
                const SizedBox(width: _controlGap),
                _At(
                  top: centre - slot.height / 2,
                  child: SizedBox.fromSize(size: slot, child: off ? null : Align(alignment: Alignment.centerRight, child: control)),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

/// [child] moved down by [top], or up when [top] is negative (the Allow button's tap area is
/// taller than a one-line row's words, and reaches into the row's padding).
class _At extends StatelessWidget {
  const _At({required this.top, required this.child});
  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) => top >= 0
      ? Padding(padding: EdgeInsets.only(top: top), child: child)
      : Transform.translate(offset: Offset(0, top), child: child);
}

/// A row's own control, by its status.
class _RowControl extends StatelessWidget {
  const _RowControl({required this.palette, required this.row, this.onAllow, this.onSettings});
  final Palette palette;
  final PermissionRow row;
  final VoidCallback? onAllow, onSettings;

  static const _mark = Size(18, 20);

  /// Nothing to show: the row's line says it all (info).
  bool get _none => row.status == RowStatus.info;
  bool get _off => row.status == RowStatus.off;
  String get _offWord => Strings.offWord(feminine: row.kind == PermissionKind.location);

  /// The room a row keeps for its control at this text size, the same in every state: the Allow
  /// button's (the tick and the asking dot are smaller). Nothing for an info row. "Off" and Settings
  /// go beneath the words instead.
  Size slot(TextScaler scaler) {
    if (_none) return Size.zero;
    final tp = TextPainter(text: TextSpan(text: Strings.allowLabel, style: _RowPill.style(palette, true)), textScaler: scaler, textDirection: TextDirection.ltr)
      ..layout();
    final allow = tp.width + _RowPill.padX * 2;
    tp.dispose();
    return Size(math.max(allow, _mark.width), math.max(_RowPill.heightFor(scaler), _mark.height));
  }

  TextStyle get _offStyle => sans(15, 20, palette.ink);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    if (_none) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (row.status) {
        RowStatus.waiting => _RowPill(
            key: Key('allow-${row.kind.name}'),
            palette: p,
            gold: true,
            label: Strings.allowLabel,
            semanticsLabel: Strings.allowFor(row.title),
            onTap: onAllow,
          ),
        RowStatus.allowed => SizedBox.fromSize(
            key: const Key('mark-allowed'),
            size: _mark,
            child: CustomPaint(painter: _Check(p.light.withValues(alpha: .85))),
          ),
        RowStatus.asking => SizedBox.fromSize(
            key: const Key('mark-asking'),
            size: _mark,
            child: Center(child: Container(width: 7, height: 7, decoration: BoxDecoration(color: p.light, shape: BoxShape.circle))),
          ),
        // beneath the words at large sizes, the Settings button may wrap under "Off"
        _ when _off => Wrap(
            key: const Key('row-off'),
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExcludeSemantics(child: Text(_offWord, style: _offStyle)),
              _RowPill(
                key: Key('settings-${row.kind.name}'),
                palette: p,
                gold: false,
                label: Strings.settingsButton,
                // (Android's lock row with no screen lock opens the phone's screen-lock settings)
                semanticsLabel: row.kind == PermissionKind.lock && row.note != null ? Strings.settingsForScreenLock : Strings.settingsFor(row.title),
                onTap: onSettings,
              ),
            ],
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// The rows' small pill: Allow in gold on a faint gold ground; Settings plain.
class _RowPill extends StatefulWidget {
  const _RowPill({super.key, required this.palette, required this.gold, required this.label, required this.semanticsLabel, this.onTap});
  final Palette palette;
  final bool gold;
  final String label, semanticsLabel;
  final VoidCallback? onTap;

  static const padX = 14.0;

  /// Clear space above and below the pill that still takes a tap, so the target is 44 points high.
  static const hitPad = 6.0;
  static double heightFor(TextScaler scaler) => scaler.scale(15) * 20 / 15 + 12 + hitPad * 2;
  static TextStyle style(Palette p, bool gold) => sans(15, 20, gold ? p.light : p.ink, weight: FontWeight.w500);

  @override
  State<_RowPill> createState() => _RowPillState();
}

class _RowPillState extends State<_RowPill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final base = widget.gold ? p.light : p.ink;
    final h = _RowPill.heightFor(MediaQuery.textScalerOf(context)) - _RowPill.hitPad * 2;
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _RowPill.hitPad),
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: h,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: _RowPill.padX),
          decoration: BoxDecoration(
            color: base.withValues(alpha: _down ? .26 : (widget.gold ? .16 : .1)),
            borderRadius: BorderRadius.circular(h / 2),
          ),
          // never wider than the row: a label too long shrinks to fit on one line
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(widget.label, maxLines: 1, softWrap: false, style: _RowPill.style(p, widget.gold))),
          ),
        ),
      ),
    );
  }
}

/// The small quiet mark for an allowed row.
class _Check extends CustomPainter {
  _Check(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 5, c.dy)
        ..lineTo(c.dx - 1.5, c.dy + 3.5)
        ..lineTo(c.dx + 5.5, c.dy - 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Check old) => old.color != color;
}

// ---- 4a Android: the speech model ----

/// Android, before the rehearsal: the one-time download that lets the phone write the words
/// (docs/android-plan.md 3.5). Download starts it and the step stays to show it coming in; Later,
/// or Continue once it has started, moves on (the download carries on while the app is open).
class ModelAskLayer extends StatelessWidget {
  const ModelAskLayer({super.key, required this.palette, required this.onNext});
  final Palette palette;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return FirstRunFrame(
      key: const Key('model-step'),
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(Strings.modelTitle, style: serif(30, 34.5, p.ink, tracking: -.012))),
          const SizedBox(height: 10),
          ModelOffer(palette: p, onLater: onNext),
        ],
      ),
    );
  }
}

// ---- 4b the rehearsal ----

class RehearsalAskLayer extends StatelessWidget {
  const RehearsalAskLayer({super.key, required this.palette, required this.onTry, required this.onNotNow});
  final Palette palette;
  final VoidCallback onTry, onNotNow;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return FirstRunFrame(
      key: const Key('rehearsal'),
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(Strings.tryTitle, style: serif(30, 34.5, p.ink, tracking: -.012))),
          const SizedBox(height: 10),
          Text(Strings.tryBody, style: sans(17, 25, p.ink2)),
          const SizedBox(height: 36),
          PillBtn(key: const Key('try-it'), label: Strings.tryIt, palette: p, kind: PillKind.primary, onTap: onTry),
          const SizedBox(height: 8),
          PillBtn(key: const Key('try-not-now'), label: Strings.notNow, palette: p, kind: PillKind.quiet, onTap: onNotNow),
        ],
      ),
    );
  }
}

/// After the practice's Amen: what the phone wrote, and that nothing was kept.
class PracticeResultLayer extends StatefulWidget {
  const PracticeResultLayer({super.key, required this.palette, required this.session, required this.onContinue});
  final Palette palette;
  final RecordSession session;
  final VoidCallback onContinue;

  @override
  State<PracticeResultLayer> createState() => _PracticeResultLayerState();
}

class _PracticeResultLayerState extends State<PracticeResultLayer> {
  WordsState? _told;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final s = widget.session;
        final state = s.wordsState;
        final words = s.words.trim();
        final String? plain = switch (state) {
          WordsState.none || WordsState.writing => Strings.practiceWriting,
          WordsState.unavailable || WordsState.later => Strings.practiceUnavailable,
          WordsState.failed => Strings.practiceFailed,
          WordsState.done => words.isEmpty ? Strings.practiceSilent : null,
        };
        final settled = state != WordsState.writing && state != WordsState.none;
        if (settled && _told != state) {
          _told = state;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final said = plain ?? '${Strings.phoneWrote}: $words';
            SemanticsService.sendAnnouncement(View.of(context), '$said ${Strings.practiceKept}', TextDirection.ltr);
          });
        }
        return FirstRunFrame(
          key: const Key('practice-result'),
          palette: p,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(Strings.phoneWrote, style: sans(13, 18, p.ink3)),
              const SizedBox(height: 10),
              if (plain == null)
                Container(
                  key: const Key('practice-words'),
                  padding: const EdgeInsets.only(left: 16),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: p.light.withValues(alpha: .5), width: 2))),
                  child: Text(words, style: serif(22, 32, p.ink)),
                )
              else
                Text(plain, key: const Key('practice-plain'), style: serif(22, 30, state == WordsState.writing ? p.ink2 : p.ink)),
              const SizedBox(height: 18),
              Text(Strings.practiceKept, style: sans(15, 21, p.ink2)),
              const SizedBox(height: 36),
              AnimatedOpacity(
                opacity: settled ? 1 : .35,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !settled,
                  child: PillBtn(key: const Key('practice-continue'), label: Strings.continueLabel, palette: p, kind: PillKind.primary, onTap: widget.onContinue),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- opened from a blessing file ----

/// "A blessing has been shared with you." and Continue.
class SharedLineLayer extends StatelessWidget {
  const SharedLineLayer({super.key, required this.palette, required this.onContinue});
  final Palette palette;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return FirstRunFrame(
      key: const Key('shared-line'),
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Arrive(delay: Duration.zero, child: Text(Strings.sharedWithYou, style: serif(30, 34.5, p.ink, tracking: -.012))),
          const SizedBox(height: 36),
          Arrive(
            delay: const Duration(milliseconds: 500),
            child: PillBtn(key: const Key('shared-continue'), label: Strings.continueLabel, palette: p, kind: PillKind.primary, onTap: onContinue),
          ),
        ],
      ),
    );
  }
}

/// "Read first": the blessing that was sent, to read before anything is kept, with Keep and Not
/// now at the foot. Nothing here is dismissed by a stray tap: only the two buttons answer.
class SharedPreviewLayer extends StatelessWidget {
  const SharedPreviewLayer({super.key, required this.palette, required this.blessing, required this.onKeep, required this.onNotNow, this.busy = false});
  final Palette palette;
  final Blessing? blessing;
  final VoidCallback onKeep, onNotNow;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final b = blessing;
    if (b == null) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final title = Strings.isUntitled(b.title) ? Strings.untitled : b.title;
    final paragraphs = b.words.split(RegExp(r'\n\s*\n')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final foot = Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + mq.viewPadding.bottom * .6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: firstRunColumn),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(Strings.receiveAsk, style: sans(15, 21, p.ink)),
            const SizedBox(height: 14),
            IgnorePointer(
              ignoring: busy,
              child: Row(children: [
                Expanded(
                  child: PillBtn(key: const Key('preview-not-now'), label: Strings.notNow, palette: p, kind: PillKind.tonal, height: 48, fontSize: 16, onTap: onNotNow),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillBtn(key: const Key('preview-keep'), label: Strings.receiveKeep, palette: p, kind: PillKind.primary, height: 48, fontSize: 16, onTap: onKeep),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
    return Stack(key: const Key('shared-preview'), children: [
      Positioned.fill(child: ColoredBox(color: p.ground.withValues(alpha: .55))),
      Positioned.fill(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, mq.viewPadding.top + 40, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.longDate, style: sans(13, 18, p.ink2, tracking: .005)),
                    const SizedBox(height: 6),
                    Semantics(header: true, child: Text(title, key: const Key('preview-title'), style: serif(30, 34.5, p.ink, tracking: -.012))),
                    if (b.from.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(Strings.from(b.from), style: serif(18, 26, p.light, italic: true)),
                    ],
                    const SizedBox(height: 24),
                    for (final para in paragraphs) ...[
                      Text(para, style: serif(19, 29, p.ink)),
                      const SizedBox(height: 14),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          foot,
        ]),
      ),
    ]);
  }
}

/// How long the opening's name takes to fade out as the welcome comes.
const openingOut = Duration(milliseconds: 550);

/// How a forward step moves (welcome to permissions, permissions to the rehearsal's question):
/// the old screen fades out moving a short way left while the new one fades in arriving from a
/// short way right, overlapping, over the still sky; [back] mirrors it. Reduce Motion: a plain
/// crossfade.
const slideTime = Duration(milliseconds: 400);
const double slideDistance = 28;

/// A first-run screen fading in when it is first built and out when [on] goes false (the home
/// screen keeps it built for the fade out, then drops it); with [slide], moving as a step does.
/// Nothing on it takes a touch once it is leaving.
class FirstRunFade extends StatefulWidget {
  const FirstRunFade({
    super.key,
    required this.on,
    required this.child,
    this.inDuration = const Duration(milliseconds: 700),
    this.outDuration = const Duration(milliseconds: 450),
    this.slide = false,
    this.back = false,
  });
  final bool on;
  final Widget child;
  final Duration inDuration, outDuration;
  final bool slide, back;

  @override
  State<FirstRunFade> createState() => _FirstRunFadeState();
}

class _FirstRunFadeState extends State<FirstRunFade> {
  bool _shown = false;

  /// Still shown though [FirstRunFade.on] went false: the step it leaves for is built in that same
  /// frame (the permissions screen measures every row), and a fade started in it would lose that
  /// frame's time and jump (seen in the film, 2026-11-16). So leaving begins a frame later, with
  /// the arriving step's own fade, which also waits a frame. Touches are refused at once.
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void didUpdateWidget(FirstRunFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.on && !widget.on && _shown) {
      _holding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _holding = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = (widget.on || _holding) && _shown;
    final still = MediaQuery.of(context).disableAnimations;
    final Duration time = widget.slide ? slideTime : (on ? widget.inDuration : widget.outDuration);
    final curve = widget.slide ? Curves.easeInOutCubic : easeOut;
    final faded = AnimatedOpacity(opacity: on ? 1 : 0, duration: time, curve: curve, child: widget.child);
    // arriving: from the right; leaving: to the left (mirrored going back). The same tree with or
    // without the move, so turning [slide] on as a step begins never restarts the fade.
    final sign = widget.back ? -1.0 : 1.0;
    final dx = !widget.slide || still || on ? 0.0 : (_shown ? -slideDistance : slideDistance) * sign;
    final child = LayoutBuilder(
      builder: (context, box) => AnimatedSlide(
        offset: Offset(dx / (box.maxWidth == 0 ? 1 : box.maxWidth), 0),
        duration: time,
        curve: curve,
        child: faded,
      ),
    );
    return IgnorePointer(
      ignoring: !widget.on,
      child: ExcludeSemantics(excluding: !widget.on, child: child),
    );
  }
}
