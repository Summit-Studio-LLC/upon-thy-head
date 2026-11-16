import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/audio.dart';
import 'data/samples.dart';
import 'data/store.dart';
import 'home/home_screen.dart';
import 'lock/lock.dart';
import 'strings.dart';
import 'theme.dart';

/// `--dart-define=SKY_STATS=true` shows frame timings over the sky.
const bool skyStats = bool.fromEnvironment('SKY_STATS');

/// `--dart-define=SKY_DEMO=true` steps to the next blessing every 3 seconds.
const bool skyDemo = bool.fromEnvironment('SKY_DEMO');

/// `--dart-define=SKY_START=listening` opens a recording and presses Begin once the sky loads.
const String skyStart = String.fromEnvironment('SKY_START');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // the app's words follow the phone's first language (iOS restarts the app when it changes)
  Strings.use(UiLanguage.forLocales(WidgetsBinding.instance.platformDispatcher.locales));
  // iPhone stays upright and iPad turns freely: Info.plist says which, per device (ruled 2026-11-16).
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(UponThyHeadApp(store: await openAppStore(seed: seedSamplesFlag, dense: seedSamples == 'dense')));
}

/// The store in the documents folder; with [seed], the five samples (or with
/// [dense], the 120) go into it if it is empty.
Future<BlessingStore> openAppStore({bool seed = false, bool dense = false}) async {
  final store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: await defaultAudioDir());
  if (seed) await seedSamplesIfEmpty(store, dense: dense);
  return store;
}

class UponThyHeadApp extends StatelessWidget {
  const UponThyHeadApp({super.key, required this.store, this.stats = skyStats, this.demo = skyDemo, this.start = skyStart, this.lock});

  final BlessingStore store;

  /// The app lock; null for the real one (on by default). Tests pass one that starts unlocked.
  final AppLock? lock;
  final bool stats, demo;
  final String start;

  @override
  Widget build(BuildContext context) {
    const palette = Palette.lamplight;
    return CupertinoApp(
      title: 'Upon Thy Head',
      debugShowCheckedModeBanner: false,
      // the words in strings.dart are chosen in main(); this makes iOS's own pieces (the text
      // selection menu, VoiceOver's language) agree with them
      locale: Strings.locale,
      supportedLocales: [for (final l in UiLanguage.values) l.locale],
      localizationsDelegates: const [GlobalCupertinoLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
      theme: CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: palette.light,
        scaffoldBackgroundColor: palette.ground,
      ),
      home: HomeScreen(palette: palette, store: store, showStats: stats, demo: demo, start: start, lock: lock),
    );
  }
}
