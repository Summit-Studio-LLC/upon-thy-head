import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../check/checks.dart';
import '../lock/lock.dart';
import '../place/where.dart';
import '../record/transcriber.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/over_sky_page.dart';

/// Settings, over the dimmed sky, in the reading page's family: the back chevron, a large serif
/// title, and four quiet rows with hairlines, each explained in a line of small sans.
class SettingsLayer extends StatelessWidget {
  const SettingsLayer({
    super.key,
    required this.palette,
    required this.lock,
    required this.where,
    required this.language,
    required this.version,
    required this.onBack,
    required this.onLock,
    required this.onLanguage,
    required this.onUseLocation,
    this.onSetScreenLock,
    this.onPhoneCheck,
    this.passingCount = 0,
    this.onPassAlong,
    this.onYourLinks,
  });

  final Palette palette;
  final AppLock lock;
  final BlessingPlace where;

  /// "en", "es", or null for the phone's own.
  final String? language;
  final String version;
  final VoidCallback onBack;
  final ValueChanged<bool> onLock;
  final ValueChanged<String?> onLanguage;
  final VoidCallback onUseLocation;

  /// Android, a phone with no screen lock: opens the phone's own screen-lock settings. Null, no button.
  final VoidCallback? onSetScreenLock;

  /// Opens the phone check page; only in builds made with `--dart-define=PHONE_CHECK=true`.
  final VoidCallback? onPhoneCheck;

  /// "To pass along" (with how many) and "Your links": the blessings recorded for someone else, and
  /// the links sent. Null, no row.
  final int passingCount;
  final VoidCallback? onPassAlong, onYourLinks;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dy = math.max(62.0, MediaQuery.of(context).viewPadding.top) - 62;
    final hint = sans(13, 18, p.ink3);
    final label = sans(17, 22, p.ink);
    Widget hairline() => Container(height: 1, color: p.ink.withValues(alpha: .10));
    Widget row(List<Widget> children, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    return ListenableBuilder(
      listenable: Listenable.merge([lock, where]),
      builder: (context, _) {
        final canLock = lock.method != LockMethod.none;
        final place = where.fallback ? Strings.nearTemple : Strings.near(where.place.lat, where.place.lon);
        return Stack(children: [
          // the sky dims behind the page
          Positioned.fill(child: IgnorePointer(child: ColoredBox(color: p.ground.withValues(alpha: .55)))),
          Positioned.fill(
            child: SingleChildScrollView(
              key: const Key('settings-scroll'),
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(28, 112 + dy, 28, 64),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Strings.settings, key: const Key('settings-title'), style: serif(34, 38, p.ink, tracking: -.012)),
                const SizedBox(height: 28),
                hairline(),
                // ---- the blessings for someone else, and the links sent ----
                if (onPassAlong != null) ...[
                  OpenRow(
                    key: const Key('settings-pass-along'),
                    palette: p,
                    semantics: '${Strings.toPassAlong}, $passingCount',
                    onTap: onPassAlong!,
                    child: Row(children: [
                      Expanded(child: Text(Strings.toPassAlong, style: label)),
                      Text('$passingCount', key: const Key('settings-pass-count'), style: sans(17, 22, p.ink2)),
                    ]),
                  ),
                  hairline(),
                ],
                if (onYourLinks != null) ...[
                  OpenRow(
                    key: const Key('settings-links'),
                    palette: p,
                    semantics: Strings.yourLinks,
                    onTap: onYourLinks!,
                    child: Text(Strings.yourLinks, style: label),
                  ),
                  hairline(),
                ],
                // ---- app lock ----
                row(key: const Key('settings-lock'), [
                  Row(children: [
                    Expanded(child: Text(Strings.appLock, style: label)),
                    GoldSwitch(
                      key: const Key('settings-lock-switch'),
                      palette: p,
                      value: canLock && lock.chosen,
                      label: Strings.appLock,
                      onChanged: canLock && !lock.asking ? onLock : null,
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    canLock ? Strings.lockHint(lock.method) : Strings.noPasscode,
                    key: const Key('settings-lock-hint'),
                    style: hint,
                  ),
                  // Android with no screen lock: the way to set one (back here, the lock is read again)
                  if (!canLock && onSetScreenLock != null) ...[
                    const SizedBox(height: 4),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: _GoldWord(key: const Key('settings-set-screen-lock'), label: Strings.setScreenLock, palette: p, onTap: onSetScreenLock!),
                    ),
                  ],
                ]),
                hairline(),
                // ---- language ----
                row(key: const Key('settings-language'), [
                  // side by side; at the largest text sizes, when the two no longer fit on one line, the
                  // menu goes under the words (its own words then line up with them)
                  LayoutBuilder(builder: (context, box) {
                    final scaler = MediaQuery.textScalerOf(context);
                    double width(String text, TextStyle style) {
                      final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
                      final w = tp.width;
                      tp.dispose();
                      return w;
                    }

                    final control = SettingsLanguageControl(palette: p, code: language, onChanged: onLanguage);
                    final controlWidth = width(SettingsLanguageControl.nameOf(language), sans(15, 20, p.ink2)) + 3 + 13 + 24 - 12;
                    // the words beside the menu in at most two lines, no word broken
                    final beside = TextPainter(text: TextSpan(text: Strings.recordingLanguage, style: label), textDirection: TextDirection.ltr, textScaler: scaler);
                    final room = box.maxWidth - controlWidth;
                    beside.layout(maxWidth: math.max(1.0, room));
                    final fits = beside.minIntrinsicWidth <= room && beside.computeLineMetrics().length <= 2;
                    beside.dispose();
                    if (fits) {
                      return Row(children: [
                        Expanded(child: Text(Strings.recordingLanguage, style: label)),
                        Transform.translate(offset: const Offset(12, 0), child: control),
                      ]);
                    }
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Strings.recordingLanguage, style: label),
                      Transform.translate(offset: const Offset(-12, 0), child: control),
                    ]);
                  }),
                  const SizedBox(height: 2),
                  Text(Strings.recordingLanguageHint, style: hint),
                ]),
                hairline(),
                // ---- where ----
                row(key: const Key('settings-where'), [
                  Text(Strings.whereGiven, style: label),
                  const SizedBox(height: 6),
                  Text(place, key: const Key('settings-place'), style: sans(15, 20, p.ink2)),
                  const SizedBox(height: 6),
                  Text(Strings.whereHint, style: hint),
                  const SizedBox(height: 4),
                  Transform.translate(
                    offset: const Offset(-12, 0),
                    child: _GoldWord(key: const Key('settings-use-location'), label: Strings.useMyLocation, palette: p, onTap: onUseLocation),
                  ),
                ]),
                hairline(),
                // ---- about ----
                row(key: const Key('settings-about'), [
                  Text(Strings.about, style: label),
                  const SizedBox(height: 6),
                  Text(Strings.aboutBody, style: sans(15, 22, p.ink2)),
                  const SizedBox(height: 6),
                  Text(version.isEmpty ? '' : Strings.version(version), key: const Key('settings-version'), style: hint),
                ]),
                hairline(),
                // ---- phone check: test builds only, never in English or Spanish strings for people ----
                if (phoneCheck && onPhoneCheck != null) ...[
                  row(key: const Key('settings-phone-check'), [
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: _GoldWord(key: const Key('settings-phone-check-open'), label: 'Phone check', palette: p, onTap: onPhoneCheck!),
                    ),
                    const SizedBox(height: 2),
                    Text('Checks this iPhone for the first test session. Only in test builds.', style: hint),
                  ]),
                  hairline(),
                ],
              ]),
            ),
          ),
          // the sky darkens a little under the status bar and the back button, as on the reading page
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
            child: IconBtn(key: const Key('settings-back'), icon: Glyph.older, color: p.ink, palette: p, semantics: Strings.backFromSettings, onTap: onBack),
          ),
        ]);
      },
    );
  }
}

/// A switch in the app's own style: a quiet track, gold when on, with a cream thumb.
class GoldSwitch extends StatelessWidget {
  const GoldSwitch({super.key, required this.palette, required this.value, required this.label, required this.onChanged});
  final Palette palette;
  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedOpacity(
            opacity: enabled || value ? 1 : .4,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: easeOut,
              width: 51,
              height: 31,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? p.light : p.ink.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? p.ground : p.ink,
                    boxShadow: [BoxShadow(color: const Color(0x40000000), blurRadius: 4, offset: const Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A word in the light colour, as an action ("Use my location").
class _GoldWord extends StatefulWidget {
  const _GoldWord({super.key, required this.label, required this.palette, required this.onTap});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_GoldWord> createState() => _GoldWordState();
}

class _GoldWordState extends State<_GoldWord> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
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
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: Text(widget.label, style: sans(15, 20, p.light, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

/// "Same as this iPhone ⌃⌄": on iOS the system pull-down menu (ios/Runner/LanguageMenu.swift, given
/// three choices); elsewhere a tap moves to the next choice.
class SettingsLanguageControl extends StatefulWidget {
  const SettingsLanguageControl({super.key, required this.palette, required this.code, required this.onChanged});
  final Palette palette;

  /// "en", "es", or null for the phone's own language.
  final String? code;
  final ValueChanged<String?> onChanged;

  static const phone = 'phone';
  static List<(String, String)> get choices => [
        (phone, Strings.sameAsPhone),
        ('en', Strings.languageName(SpeechLanguage.english)),
        ('es', Strings.languageName(SpeechLanguage.spanish)),
      ];

  static String nameOf(String? code) => choices.firstWhere((c) => c.$1 == (code ?? phone), orElse: () => choices.first).$2;

  @override
  State<SettingsLanguageControl> createState() => SettingsLanguageControlState();
}

class SettingsLanguageControlState extends State<SettingsLanguageControl> {
  MethodChannel? _menu;
  static bool get _native => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  @override
  void didUpdateWidget(SettingsLanguageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _menu?.invokeMethod<void>('select', {'code': widget.code ?? SettingsLanguageControl.phone});
  }

  void _created(int id) {
    _menu = MethodChannel('upon_thy_head/language_menu/$id')
      ..setMethodCallHandler((call) async {
        if (call.method == 'picked') debugPick((call.arguments as Map)['code'] as String?);
      });
  }

  /// Choose as the menu would.
  void debugPick(String? code) => widget.onChanged(code == null || code == SettingsLanguageControl.phone ? null : code);

  Future<void> debugOpen() async => _menu?.invokeMethod<void>('debugOpen');
  Future<void> debugClose() async => _menu?.invokeMethod<void>('debugClose');

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final name = SettingsLanguageControl.nameOf(widget.code);
    final words = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(name, key: const Key('settings-language-label'), style: sans(15, 20, p.ink2))),
        const SizedBox(width: 3),
        SizedBox(width: 13, height: 13, child: GlyphIcon(Glyph.upDown, color: p.ink3)),
      ]),
    );
    final label = '${Strings.recordingLanguage}: $name';
    if (!_native) {
      final codes = SettingsLanguageControl.choices.map((c) => c.$1).toList();
      final next = codes[(codes.indexOf(widget.code ?? SettingsLanguageControl.phone) + 1) % codes.length];
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => debugPick(next), child: words),
      );
    }
    return Stack(children: [
      words,
      Positioned.fill(
        child: UiKitView(
          viewType: 'upon_thy_head/language_menu',
          creationParams: {
            'code': widget.code ?? SettingsLanguageControl.phone,
            'label': label,
            'choices': [for (final c in SettingsLanguageControl.choices) [c.$1, c.$2]],
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      ),
    ]);
  }
}
