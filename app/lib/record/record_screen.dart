import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../sky/sky_engine.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fade.dart';
import '../widgets/scrims.dart';
import '../widgets/sheet.dart';
import 'hold_ring.dart';
import 'language_menu.dart';
import 'session.dart';
import 'transcriber.dart';

/// The recording screen, drawn over the sky: Begin, then the ring that
/// discards in the first ten seconds and finishes after them.
class RecordLayer extends StatefulWidget {
  const RecordLayer({
    super.key,
    required this.palette,
    required this.session,
    required this.onBegin,
    required this.onClose,
    required this.onDiscardEarly,
    required this.onAmen,
    required this.onLanguage,
    required this.onOpenSettings,
    this.active = true,
    this.practice = false,
  });

  /// The first run's rehearsal: marked as practice, with "Not now" as the way out and Amen from
  /// the start.
  final bool practice;

  final Palette palette;
  final RecordSession session;
  final VoidCallback onBegin;

  /// The recording screen is the one showing (it stays built, faded out, behind the others).
  final bool active;

  /// The language was changed on the ready screen.
  final ValueChanged<SpeechLanguage> onLanguage;

  /// "Open Settings", when a permission was refused.
  final VoidCallback onOpenSettings;

  /// Close before Begin, or Discard from the sheet: back to the sky.
  final VoidCallback onClose;

  /// Held Discard inside the first ten seconds: back to Begin.
  final VoidCallback onDiscardEarly;

  /// Held Amen.
  final VoidCallback onAmen;

  @override
  State<RecordLayer> createState() => _RecordLayerState();
}

class _RecordLayerState extends State<RecordLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _countdown = ValueNotifier(0);
  bool _amen = false, _nudge = false;
  Timer? _nudgeTimer;

  RecordSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _onSession();
  }

  @override
  void didUpdateWidget(RecordLayer old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
      _onSession();
    }
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _ticker.dispose();
    _countdown.dispose();
    _nudgeTimer?.cancel();
    super.dispose();
  }

  void _onSession() {
    if (s.live && !_ticker.isActive) _ticker.start();
    if (!s.live && _ticker.isActive) _ticker.stop();
    _tick(Duration.zero);
    if (mounted) setState(() {});
  }

  void _tick(Duration _) {
    _countdown.value = s.live ? (s.practice ? 1.0 : (s.elapsed / RecordSession.window).clamp(0.0, 1.0)) : 0;
    final amen = s.amen;
    if (amen != _amen) setState(() => _amen = amen);
  }

  void _nudgeHint() {
    _nudgeTimer?.cancel();
    setState(() => _nudge = true);
    _nudgeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _nudge = false);
    });
  }

  /// Under Begin: what Begin does, and the language the blessing will be spoken in.
  Widget _hintAndLanguage(Palette p) => widget.practice
      ? Text(Strings.practiceHint, key: const Key('practice-hint'), style: sans(13, 18, p.ink3), textAlign: TextAlign.center)
      : Column(mainAxisSize: MainAxisSize.min, children: [
        Text(Strings.nothingRecorded, style: sans(13, 18, p.ink3), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        // the native menu button exists only while this screen is up and ready
        if (widget.active && !s.live)
          LanguageControl(key: const Key('language'), palette: p, language: s.language, onChanged: widget.onLanguage)
        else
          const SizedBox(height: 40),
      ]);

  /// Under a dimmed Begin: what was refused, and the way to Settings.
  Widget _refused(Palette p, Permissions perms) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          Strings.refused(microphone: perms.microphone == Permission.denied, speech: perms.speech == Permission.denied),
          key: const Key('refused'),
          style: sans(13, 18, p.ink2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        PillBtn(
          key: const Key('open-settings'),
          label: Strings.openSettings,
          palette: p,
          kind: PillKind.quiet,
          height: 40,
          fontSize: 15,
          onTap: widget.onOpenSettings,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final mq = MediaQuery.of(context);
    final live = s.live;
    final perms = s.permissions;
    final refused = perms?.anyDenied ?? false;
    final top = math.max(62.0, mq.viewPadding.top);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      // Begin sits on the look point, where the glow breathes
      final lookY = (1 - (SkyView.ready.cy * .5 + .5)) * h;
      return Stack(children: [
        Positioned(left: 0, right: 0, top: 0, height: 190, child: TopScrim(palette: p)),
        Positioned(left: 0, right: 0, bottom: 0, height: 230, child: BottomScrim(palette: p)),
        // ---- top: what this is, and the way out ----
        // The title and the way out share one line, so at the largest text sizes they stop growing (as
        // iOS's own navigation bars do) and the title shrinks before it reaches the button.
        Positioned(
          left: 104,
          right: 104,
          top: top + 6,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: IgnorePointer(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Stack(alignment: Alignment.topCenter, children: [
                  AnimatedOpacity(
                    opacity: live ? 0 : 1,
                    duration: const Duration(milliseconds: 500),
                    curve: easeOut,
                    child: Text(widget.practice ? Strings.practice : Strings.newBlessing, style: serif(17, 24, p.ink3, italic: true), textAlign: TextAlign.center),
                  ),
                  Fade(
                    on: live,
                    inDuration: const Duration(milliseconds: 500),
                    outDuration: const Duration(milliseconds: 500),
                    delay: const Duration(milliseconds: 500),
                    child: Text(s.paused ? Strings.paused : (widget.practice ? Strings.practiceListening : Strings.listening),
                        key: const Key('listening'), style: serif(17, 24, p.ink3, italic: true), textAlign: TextAlign.center),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: top - 4,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Fade(
              on: !live || _amen,
              inDuration: const Duration(milliseconds: 800),
              outDuration: const Duration(milliseconds: 300),
              child: TextBtn(
                key: const Key('rec-x'),
                label: widget.practice ? Strings.notNow : (live ? Strings.discard : Strings.close),
                palette: p,
                // a practice keeps nothing, so leaving it needs no question
                onTap: () => live && !widget.practice ? s.showSheet(true) : widget.onClose(),
              ),
            ),
          ),
        ),
        // ---- before Begin ----
        Positioned(
          left: 0,
          right: 0,
          top: lookY - 66,
          child: Center(
            child: IgnorePointer(
              ignoring: live,
              child: AnimatedScale(
                scale: live ? 1.55 : 1,
                duration: const Duration(milliseconds: 900),
                curve: easeOut,
                child: AnimatedOpacity(
                  opacity: live ? 0 : 1,
                  duration: const Duration(milliseconds: 600),
                  curve: easeOut,
                  child: AnimatedOpacity(
                    opacity: refused ? .35 : 1,
                    duration: const Duration(milliseconds: 400),
                    child: BeginButton(key: const Key('begin'), palette: p, onTap: refused ? null : widget.onBegin),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 32,
          right: 32,
          top: lookY + 89,
          child: IgnorePointer(
            ignoring: live,
            child: AnimatedOpacity(
              opacity: live ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: refused ? _refused(p, perms!) : _hintAndLanguage(p),
            ),
          ),
        ),
        // ---- while it listens ----
        Positioned(
          left: 0,
          right: 0,
          bottom: 92 - HoldRing.reach,
          child: Center(
            child: Fade(
              on: live,
              inDuration: const Duration(milliseconds: 900),
              outDuration: const Duration(milliseconds: 500),
              delay: const Duration(milliseconds: 600),
              child: HoldRing(
                key: const Key('hold'),
                palette: p,
                amen: _amen,
                countdown: _countdown,
                onHeld: () => _amen ? widget.onAmen() : widget.onDiscardEarly(),
                onShortPress: _nudgeHint,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 58,
          child: IgnorePointer(
            child: Fade(
              on: live,
              inDuration: const Duration(milliseconds: 900),
              outDuration: const Duration(milliseconds: 500),
              delay: const Duration(milliseconds: 600),
              child: Stack(alignment: Alignment.center, children: [
                for (final (text, show) in [(Strings.holdToDiscard, !_amen), (Strings.holdToFinish, _amen)])
                  AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    curve: easeOut,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: sans(13, 18, _nudge ? p.ink : p.ink3),
                      child: Text(text, textAlign: TextAlign.center),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        // ---- are you sure ----
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DiscardSheet(
            palette: p,
            on: s.sheet,
            onDiscard: widget.onClose,
            onKeep: () => s.showSheet(false),
          ),
        ),
      ]);
    });
  }
}

/// "Begin": a ring of light round the look point.
class BeginButton extends StatefulWidget {
  const BeginButton({super.key, required this.palette, required this.onTap});
  final Palette palette;

  /// Null while Begin is unavailable (a permission was refused).
  final VoidCallback? onTap;

  @override
  State<BeginButton> createState() => _BeginButtonState();
}

class _BeginButtonState extends State<BeginButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: Strings.beginLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => widget.onTap == null ? null : setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .96 : 1,
          duration: const Duration(milliseconds: 200),
          curve: easeOut,
          child: Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.light.withValues(alpha: .6), width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
              gradient: RadialGradient(
                colors: [p.light.withValues(alpha: .16), p.light.withValues(alpha: .04), p.light.withValues(alpha: 0)],
                stops: const [0, .72, 1],
              ),
            ),
            // one word, kept whole inside the circle at any text size
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(Strings.begin, style: serif(24, 24, p.ink))),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Discard this recording?", rising from the bottom edge.
class DiscardSheet extends StatelessWidget {
  const DiscardSheet({super.key, required this.palette, required this.on, required this.onDiscard, required this.onKeep});
  final Palette palette;
  final bool on;
  final VoidCallback onDiscard, onKeep;

  @override
  Widget build(BuildContext context) => ConfirmSheet(
        palette: palette,
        on: on,
        title: Strings.discardTitle,
        body: Strings.discardBody,
        dangerLabel: Strings.discard,
        safeLabel: Strings.keepListening,
        onDanger: onDiscard,
        onSafe: onKeep,
        panelKey: const Key('sheet'),
        dangerKey: const Key('sheet-discard'),
        safeKey: const Key('sheet-keep'),
      );
}
