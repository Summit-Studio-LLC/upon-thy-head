import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/lock/lock.dart';

/// How the integration tests start: as if the person had just unlocked. The lock itself stays as a
/// real user has it (on, with the phone's own Face ID or passcode, and it locks again after a
/// minute away); only the launch's question is skipped, so a test never waits on Face ID.
///
/// The first run (onboarding/) is never shown to them either: they begin on the sky as before.
/// Its own replay is tool/first_run_acceptance.sh.
AppLock unlockedLock() {
  HomeScreen.debugSkipFirstRun = true;
  return AppLock(api: NativeLockApi(), startUnlocked: true);
}

/// The app's own store, emptied and filled with the five samples, as a
/// launch with `--dart-define=SEED_SAMPLES=true` on a fresh install.
/// With [dense], the 120 test blessings instead; with [empty], nothing.
Future<BlessingStore> freshSeededStore({bool dense = false, bool empty = false}) async {
  HomeScreen.debugSkipFirstRun = true;
  final store = SqliteBlessingStore.open(await SqliteBlessingStore.defaultPath(), audioDir: await defaultAudioDir());
  for (final b in await store.list()) {
    await store.delete(b.id);
  }
  if (!empty) await seedSamplesIfEmpty(store, dense: dense);
  return store;
}
