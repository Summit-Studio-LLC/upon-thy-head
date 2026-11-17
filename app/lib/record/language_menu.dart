import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/icons.dart';
import '../widgets/pull_down.dart';
import 'transcriber.dart';

/// The language a blessing is spoken in, as a small quiet control: "English ⌃⌄". On iOS a
/// tap opens the system pull-down menu (ios/Runner/LanguageMenu.swift, a clear native button
/// laid over these words); elsewhere (Android) a tap opens the same menu drawn in Flutter
/// ([showPullDown]).
class LanguageControl extends StatefulWidget {
  const LanguageControl({super.key, required this.palette, required this.language, required this.onChanged});

  final Palette palette;
  final SpeechLanguage language;
  final ValueChanged<SpeechLanguage> onChanged;

  @override
  State<LanguageControl> createState() => LanguageControlState();
}

class LanguageControlState extends State<LanguageControl> {
  MethodChannel? _menu;

  static bool get _native => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  @override
  void didUpdateWidget(LanguageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _menu?.invokeMethod<void>('select', {'code': widget.language.code});
  }

  void _created(int id) {
    _menu = MethodChannel('upon_thy_head/language_menu/$id')
      ..setMethodCallHandler((call) async {
        if (call.method == 'picked') {
          widget.onChanged(SpeechLanguage.fromCode((call.arguments as Map)['code'] as String?));
        }
      });
  }

  /// Open the menu as a tap would (iOS 17.4 and later); for screenshots in tests.
  Future<void> debugOpen() async => _menu?.invokeMethod<void>('debugOpen');

  Future<void> debugClose() async => _menu?.invokeMethod<void>('debugClose');

  /// Choose as the menu would, through the native button's own handler path.
  void debugPick(SpeechLanguage l) => widget.onChanged(l);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final label = Strings.languageName(widget.language);
    final words = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, key: const Key('language-label'), style: sans(13, 18, p.ink2)),
        const SizedBox(width: 3),
        SizedBox(width: 13, height: 13, child: GlyphIcon(Glyph.upDown, color: p.ink3)),
      ]),
    );
    if (!_native) {
      return Semantics(
        button: true,
        label: Strings.languageLabel(widget.language),
        excludeSemantics: true,
        child: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final code = await showPullDown(
                context,
                palette: p,
                choices: [for (final l in SpeechLanguage.values) (l.code, Strings.languageName(l))],
                selected: widget.language.code,
              );
              if (code != null && code != widget.language.code && mounted) widget.onChanged(SpeechLanguage.fromCode(code));
            },
            child: words,
          ),
        ),
      );
    }
    return Stack(children: [
      words,
      Positioned.fill(
        child: UiKitView(
          viewType: 'upon_thy_head/language_menu',
          creationParams: {'code': widget.language.code, 'label': Strings.languageLabel(widget.language)},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      ),
    ]);
  }
}
