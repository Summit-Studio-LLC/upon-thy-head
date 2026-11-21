import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import '../data/samples.dart' show seedWithFirstRun;
import '../data/audio.dart';
import '../data/blessing.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../lock/lock.dart';
import 'head_buttons.dart';
import 'locked.dart';
import '../not_yet.dart';
import '../onboarding/first_run.dart';
import '../onboarding/first_run_screens.dart';
import '../people/family.dart';
// the count line moved to people/family.dart; still found here by those who read it from home
export '../people/family.dart' show countLine;
import '../people/family_pages.dart';
import '../people/person.dart';
import '../people/sky_switch.dart';
import '../place/where.dart';
import '../polish/changes_screen.dart';
import '../read/read_screen.dart';
import '../record/after_screen.dart';
import '../record/record_screen.dart';
import '../record/recovered_sheet.dart';
import '../record/recovery.dart';
import '../record/session.dart';
import '../record/android_words.dart';
import '../record/speech.dart';
import '../record/words_model.dart';
import '../record/transcriber.dart';
import '../review/player.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import '../share/link_crypto.dart';
import '../share/link_format.dart';
import '../share/link_service.dart';
import '../share/links.dart';
import '../share/hand_over.dart';
import '../share/receive.dart';
import '../share/ring_arrival.dart';
import '../share/share.dart';
import '../share/your_links.dart';
import '../check/check_page.dart';
import '../check/checks.dart';
import '../sky/astro.dart';
import '../sky/figures.dart';
import '../sky/placement.dart';
import '../sky/sky_engine.dart';
import '../sky/sky_painter.dart';
import '../sky/sky_view.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/balanced_text.dart';
import '../widgets/edge_swipe.dart';
import '../widgets/fade.dart';
import '../widgets/icons.dart';
import '../widgets/scrims.dart';
import '../widgets/measure.dart';
import 'pass_along.dart';
import 'ruler.dart';
import 'sky_stats.dart';
import 'timeline.dart';

/// Which screen is over the sky.
enum Stage { home, record, after, read, review, changes, settings, passing, links, family, person }

/// Where the first run is (onboarding/first_run.dart); [none] once it is over or never shown.
/// [waiting]: it will be shown, once the launch knows whether a blessing file opened the app.
enum Onboard { none, waiting, opening, welcome, permissions, model, rehearsal, practice, practiceResult, sharedLine, sharedPreview }

/// `--dart-define=FIRST_RUN_FEED=<name>`: the rehearsal's recording is replaced at Amen by the file
/// of this name in the app's tmp folder (the acceptance runs, with the prepared speech file).
const String firstRunFeed = String.fromEnvironment('FIRST_RUN_FEED');

/// "For me": the night sky with a light for each blessing, the one in focus
/// named below, and a ruler of months to move between them; or the same
/// blessings as a list. The recording and reading screens are drawn over the
/// same sky, so the camera moves between them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.palette,
    required this.store,
    this.showStats = false,
    this.demo = false,
    this.start = '',
    this.recorder,
    this.transcriber,
    this.player,
    this.joiner,
    this.lock,
    this.locator,
    this.share,
    this.links,
    this.firstRunAsker,
  });

  /// Sending by link (share/links.dart); on a phone the native one against [linkService] when not
  /// given, and none on the host (the share sheet then offers the file).
  final Links? links;

  /// The first run's questions; the native ones on iOS when not given.
  final FirstRunAsker? firstRunAsker;

  /// Tests only: never show the first run (the integration tests begin on the sky as before).
  static bool debugSkipFirstRun = false;

  /// The app lock; the native one on iOS when not given (on unless turned off).
  final AppLock? lock;

  /// The phone's location; the native one on iOS when not given.
  final Locator? locator;

  /// The system share sheet; null for the real one.
  final ShareApi? share;

  final Palette palette;
  final BlessingStore store;

  /// The microphone and the words; on iOS the native ones (record/speech.dart) when not given,
  /// elsewhere silent stand-ins.
  final Recorder? recorder;
  final Transcriber? transcriber;

  /// Plays recordings on the review page; the native one on iOS when not given.
  final Player? player;

  /// Joins the parts of a recording the app was closed during; the native one on iOS when not given.
  final AudioJoiner? joiner;
  final bool showStats, demo;

  /// `listening`: open a recording and press Begin as soon as the sky loads (for timings).
  final String start;

  /// Tests only: draw nothing over the sky (integration_test/cover_shot_test.dart renders the app
  /// switcher's cover, assets/sky/cover.jpg, this way).
  static bool debugBare = false;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Placement placement = RingPlacement();

  /// Where the empty sky looks: the Milky Way through Aquila and Scutum.
  static const double emptyRa = 285 * deg, emptyDec = 2 * deg;

  /// The blessings on the ring showing ([_ring]), oldest first. Only these are in the sky.
  List<Blessing> _blessings = [];

  /// The family members and every ring's blessings, as last read from the store (people/).
  Family _family = Family(const [], const []);

  /// Whose sky is showing: '' for the person's own, else a family member's id. Remembered, so the
  /// app reopens on it. While locked it is kept but nothing of it is shown.
  String _ring = '';

  /// The family member being changed on the person page (null: adding one), and where that page
  /// was opened from (the sky's menu, or Manage family).
  Person? _editing;
  Stage _personFrom = Stage.home;
  final GlobalKey<PersonLayerState> _personKey = GlobalKey();

  /// The sky's menu is being opened or is open (it goes at once if the app locks: the capsule and
  /// the glass menu it morphs into leave the tree with the head).
  bool _skyMenuOpen = false;

  /// When the ring showing begins: a family member's birth, if given.
  DateTime? get _begins => _family.person(_ring)?.born?.local;
  List<Vec3> _line = const [];

  Stage _stage = Stage.home;
  bool _list = false;
  RecordSession _session = RecordSession();

  /// The blessing in focus before the recording screen opened, to go back to.
  int _homeFocus = 0;
  final SkyEngine _engine = SkyEngine(const []);
  late final Future<SkyAssets> _assets;
  final StarFillStats _fill = StarFillStats();

  /// The blessing the caption shows; trails the engine's focus by the cross-fade.
  int _shown = 0;
  bool _swapping = false;
  Timer? _swapTimer, _demoTimer;

  /// Away from the foreground, until the lock has had its say on the return (_onActive). iOS hands
  /// over a link or file that brought the app back before it says the app is active, so without
  /// this an arrival could open a page in the moment before the lock comes down.
  bool _away = false;
  Timer? _awayTimer;

  BlessingStore get _store => widget.store;

  static bool get _ios => Phone.ios;

  // iPhone and Android answer the same channels; on Android most answers are still stand-ins that
  // say "not on this phone yet" (not_yet.dart). Elsewhere (tests on the host) the silent ones.
  static bool get _native => Phone.native;

  late final Recorder _recorder = widget.recorder ?? (_native ? NativeSpeech.instance : SilentRecorder());
  late final Transcriber _transcriber = widget.transcriber ?? (_native ? NativeSpeech.instance : const SilentTranscriber());
  late final Player _player = widget.player ?? (_native ? NativePlayer() : SilentPlayer());
  late final AudioJoiner _joiner = widget.joiner ?? (_native ? NativeSpeech.instance : const FileJoiner());
  late final AppLock _lock = widget.lock ?? AppLock(api: _native ? NativeLockApi() : NoLockApi());
  late final Locator _locator = widget.locator ?? (_native ? NativeLocator() : const NoLocator());
  late final ShareApi _share = widget.share ?? (_native ? NativeShareApi() : NoShareApi());
  late final Links? _links = widget.links ??
      (_native ? Links(store: _store, crypto: const NativeLinkCrypto(), secrets: const NativeLinkCrypto(), service: HttpLinkService()) : null);

  /// Blessings passed along ("To pass along"), oldest first: never in the sky or the count.
  List<Blessing> _passing = [];

  /// The blessing passed along that is being read or reviewed now (it has no light to focus), and
  /// where its reading page was opened from.
  Blessing? _aside;
  Stage _readFrom = Stage.home;

  /// Where "Your links" was opened from (Settings, or the link-made sheet on a reading page).
  Stage _linksFrom = Stage.settings;
  final GlobalKey<YourLinksLayerState> _linksKey = GlobalKey();
  /// "The place blessings are given" (place/where.dart), once the settings are read.
  BlessingPlace? _where;
  Settings? _settings;
  String _version = '';

  /// Locked: the sky with no lights, ring, dates, caption, count or list (lock/lock.dart). Until the
  /// lock has been read at launch, nothing is drawn over the sky at all.
  bool get _locked => _lock.locked;
  bool _wasLocked = false;

  /// The blessing in focus when the sky was locked, to come back to.
  int _lockedFocus = 0;

  /// Blessings rebuilt at this launch from recordings the app was closed during, and whether the
  /// sheet that says so is up.
  List<Blessing> _recovered = const [];
  bool _recoveredSheet = false;

  /// Blessing files that arrived and wait to be shown (one at a time, only when unlocked and never
  /// during a recording), the one shown now, and whether its sheet is up.
  final List<IncomingFile> _inbox = [];
  IncomingFile? _arrivalFile;
  Arrival? _arrival;
  bool _receiving = false, _arrivalsOpen = false, _arrivalBusy = false, _arrivalScheduled = false;

  /// A ring handed over being kept; and the words of the quiet notice over the sky.
  bool _ringBusy = false;
  String _noticeText = Strings.alreadyHave;

  /// Where an App Shortcut, the Spotlight entry or a launcher shortcut asked the app to open (the
  /// newest only), waiting until the app is unlocked and free to go there.
  ShortcutPlace? _shortcut;
  bool _shortcutScheduled = false;

  /// "You already have this blessing.", for a few seconds.
  bool _noticeOn = false;
  Timer? _noticeTimer;

  /// Words being written at this launch for blessings saved before their words were.
  final Map<String, WordsState> _writing = {};

  /// The blessing on the review page, where the page was opened from, and the tags in use.
  Blessing? _reviewing;
  Stage _reviewFrom = Stage.read;

  /// Where the changes screen was opened from (the review page or the reading page), and for which.
  Stage _changesFrom = Stage.review;
  Blessing? _changing;
  final GlobalKey<ChangesLayerState> _changesKey = GlobalKey();
  List<String> _knownTags = const [];
  final GlobalKey<ReviewLayerState> _reviewKey = GlobalKey();
  final GlobalKey<ReadLayerState> _readKey = GlobalKey();

  /// Home's head, measured after layout so a wide screen's ring can keep below it.
  final GlobalKey _headKey = GlobalKey();

  /// On a screen wider than tall (an iPad in landscape) the sky is told where the head ends, so the
  /// ring is sized to pass below it (SkyEngine.fitBelow); a phone held upright is left as it is.
  void _measureHead() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final box = _headKey.currentContext?.findRenderObject();
    final bottom = size.width > size.height && box is RenderBox && box.hasSize ? box.localToGlobal(Offset(0, box.size.height)).dy : 0.0;
    _engine.clearTop = bottom;
  }

  /// The remembered language, and where recordings go; read once at start.
  late final Future<(Settings, String)> _speechSetup = Future.wait<Object>([
    Settings.open(),
    defaultAudioDir(),
  ]).then((r) {
    // Android keeps the place of words being written beside the audio folder (android_words.dart)
    AndroidWords.useAudioFolder(r[1] as String);
    return (r[0] as Settings, r[1] as String);
  });

  // ---- the first run ----
  Onboard _onboard = Onboard.none;

  /// Steps fading out, kept built until they have.
  final Set<Onboard> _leaving = {};
  FirstRunPermissions? _perms;
  PausableTimer? _openingTimer;

  /// First-run steps that move as a step (in from the right, out to the left) rather than fade.
  final Set<Onboard> _sliding = {};
  bool _openingShared = false;

  /// Locked at launch with the rest of the first run still to come: shown once unlocked.
  FirstRunStart? _afterUnlock;

  /// The blessing a file opened the app with on a fresh install ("Read first"), not yet kept.
  Blessing? _shared;
  bool _sharedBusy = false;

  /// The blessing written to the store at Amen, before its words are.
  Future<void>? _saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.addListener(_onEngine);
    _lock.addListener(_onLock);
    _lock.api.onActive = _onActive;
    // a file made for a share sheet the app was killed under
    unawaited(_share.clean());
    if (phoneCheck) {
      // tool/phone.sh --check launches straight onto the phone check page
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await phoneCheckAsked() && mounted) _openPhoneCheck();
      });
    }
    final kept = _recover();
    _assets = Future.wait<Object?>([kept, loadSkyAssets(), _setUpPrivacy()]).then((r) {
      final list = r[0] as List<Blessing>, a = r[1] as SkyAssets;
      _wasLocked = _locked;
      // open on the newest, or on the newest recording just recovered
      final rescued = _recovered.isEmpty ? -1 : list.indexWhere((b) => b.id == _recovered.last.id);
      _setBlessings(list, focus: rescued >= 0 ? rescued : list.length - 1);
      _recoveredSheet = _recovered.isNotEmpty;
      if (_onboard == Onboard.waiting) _engine.setView(SkyView.black);
      _engine.snap();
      if (list.isEmpty || _locked) _engine.lookToward(emptyRa, emptyDec, instant: true);
      _shown = _engine.focus;
      _engine.show = FigureShow(a.figures);
      if (widget.start == 'listening') {
        Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          _openRecord();
          Timer(const Duration(milliseconds: 1500), () => mounted ? _begin() : null);
        });
      }
      unawaited(_writeMissingWords());
      if (Phone.android) {
        // the model arriving (downloaded now, or carried on from an earlier launch) writes the words
        // of every recording that waited for it
        WordsModel.instance.whenReady(_modelArrived);
        unawaited(WordsModel.instance.refresh(resume: true));
      }
      unawaited(_startReceiving().then((_) => _beginFirstRun()));
      unawaited(_clearPractice());
      // locked at launch: the phone asks once, as the locked sky appears
      if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _askToUnlock());
      return a;
    });
    if (widget.demo) {
      _demoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_blessings.isNotEmpty) _engine.setFocus((_engine.focus + 1) % _blessings.length);
      });
    }
  }

  /// Before the sky: the lock (locked at launch when on) and the place blessings are given.
  Future<void> _setUpPrivacy() async {
    final (settings, _) = await _speechSetup;
    _settings = settings;
    _where = BlessingPlace(settings: settings, locator: _locator);
    var anything = false;
    try {
      anything = (await _store.list()).isNotEmpty;
    } catch (_) {}
    // a test build seeded for the first run: met as on a fresh install
    if (seedWithFirstRun && settings.firstRun == null) anything = false;
    if (!HomeScreen.debugSkipFirstRun) {
      if (settings.firstRun == null && anything) {
        // blessings from before the first run existed (or the seeded build): never shown
        await settings.setFirstRun(FirstRun.existing);
      } else if (firstRunStart(settings.firstRun, hasBlessings: anything, fileWaiting: false) != FirstRunStart.none) {
        _onboard = Onboard.waiting;
      }
    }
    // nothing kept yet, so nothing to lock while the first run is shown
    await _lock.init(settings, unlocked: _onboard == Onboard.waiting && !anything);
    try {
      _version = await _lock.api.version();
    } catch (_) {}
  }

  // ---- the lock ----

  void _onLock() {
    if (!mounted) return;
    final now = _locked;
    if (now == _wasLocked) return setState(() {});
    _wasLocked = now;
    now ? _hideBlessings() : _showBlessings();
    final pending = _afterUnlock;
    if (!now && pending != null) {
      _afterUnlock = null;
      unawaited(_resumeFirstRun(pending));
    }
  }

  /// Locked: nothing of any blessing stays on screen or in the sky. A recording under way, or its
  /// after-Amen screen, stays; only its own new light is in the sky.
  void _hideBlessings() {
    // the sky's menu, with its names and counts, goes at once: the locked head has no capsule, and
    // the menu goes with it
    _skyMenuOpen = false;
    _personKey.currentState?.closeSheet();
    // the system share sheet goes too, with anything made for it
    unawaited(_share.dismiss());
    // a blessing file being asked about waits, unseen, until the next unlock
    if (_arrivalFile != null) {
      _inbox.insert(0, _arrivalFile!);
      _arrivalFile = null;
    }
    _receiving = false;
    _arrival = null;
    _noticeOn = false;
    _lockedFocus = _blessings.isEmpty ? 0 : _engine.focus.clamp(0, _blessings.length - 1);
    _swapTimer?.cancel();
    _swapping = false;
    _line = const [];
    final draft = _session.draft;
    if ((_stage == Stage.record || _stage == Stage.after) && draft != null) {
      _engine.setBlessings([draft], focus: 0);
    } else {
      if (_stage == Stage.changes) unawaited(_saveChanges());
      _stage = Stage.home;
      _engine.setBlessings(const [], focus: 0);
      _engine.setView(SkyView.home);
      _engine.lookToward(emptyRa, emptyDec, instant: true);
    }
    _reviewing = null;
    _changing = null;
    _aside = null;
    _list = false;
    setState(() {});
  }

  /// Unlocked: the blessings come back, the one in focus as before.
  void _showBlessings() {
    final draft = _session.draft;
    if ((_stage == Stage.record || _stage == Stage.after) && draft != null) {
      _line = placement.line(_blessings);
      _placeDraft(draft);
    } else {
      _setBlessings(_blessings, focus: _lockedFocus);
      _engine.setView(SkyView.home);
      if (_blessings.isEmpty) {
        _engine.lookToward(emptyRa, emptyDec, instant: true);
      } else {
        _engine.lookAt(_engine.focus, instant: true);
      }
      _showNow();
    }
    setState(() {});
  }

  /// Ask the phone to unlock: automatically once as the locked sky appears, and from "Unlock".
  Future<bool> _askToUnlock() async {
    if (!_locked || !mounted) return !_locked;
    return _lock.unlock();
  }

  /// The app is in front again. Away more than a minute, and not recording or playing: locked, and
  /// drawn so before the cover over the app is lifted; then the phone asks once.
  Future<void> _onActive(Duration away, bool background) async {
    if (!mounted) return;
    await _lock.recheck();
    if (background && _lock.active && !_locked && shouldLockOnReturn(away: away, recording: _session.live, playing: _player.playing)) {
      debugPrint('lock: locked after ${away.inSeconds} s away');
      _lock.lock();
    }
    _cameBack();
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 800));
    } catch (_) {}
    if (background && _locked && _stage == Stage.home) unawaited(_askToUnlock());
  }

  /// Before the sky: recordings the app was closed during become drafts, and audio that belongs to
  /// nothing is removed (record/recovery.dart). Then the blessings for the sky.
  Future<List<Blessing>> _recover() async {
    try {
      final (_, dir) = await _speechSetup;
      final r = await Recovery(store: _store, audioDir: dir, joiner: _joiner).run();
      _recovered = r.recovered;
    } catch (e) {
      // whatever it found, the app starts
      debugPrint('recovery: $e');
    }
    try {
      _passing = await _store.list(ownership: Ownership.passingOn);
    } catch (_) {}
    final (settings, _) = await _speechSetup;
    final onRings = await _store.list(ownership: Ownership.forMe);
    var people = const <Person>[];
    try {
      people = await _store.people();
    } catch (e) {
      debugPrint('family: $e');
    }
    _family = Family(people, onRings);
    // an entry opened and left with nothing in it (the app closed on it) is not kept
    for (final b in _family.unplaced.where(isEmptyEntry).toList()) {
      try {
        await _store.delete(b.id);
        _family.unplaced.remove(b);
      } catch (_) {}
    }
    // the sky that was showing last
    _ring = _family.known(settings.sky);
    return _family.on(_ring);
  }

  Future<void> _reloadPassing() async {
    final list = await _store.list(ownership: Ownership.passingOn);
    if (!mounted) return;
    // the one being read or reviewed stays the same object, so the pages see its edits
    final a = _aside;
    _passing = [for (final b in list) a != null && b.id == a.id ? a : b];
    setState(() {});
  }

  void _modelArrived() => unawaited(_writeMissingWords());

  /// [_writeMissingWords] is running; asked again meanwhile: run once more when it ends.
  bool _missingRunning = false, _missingAgain = false;

  /// Blessings saved before their words were written (closed just after Amen, or recovered), and
  /// recordings kept for their words (Android, waiting for the model): the words are written now
  /// from the audio, one at a time, oldest first. Recording is never held up by it: on Android
  /// each piece waits while the microphone is live, and a new blessing's words go first.
  Future<void> _writeMissingWords() async {
    if (_missingRunning) {
      _missingAgain = true;
      return;
    }
    _missingRunning = true;
    try {
      do {
        _missingAgain = false;
        await _writeMissingOnce();
      } while (_missingAgain && mounted);
    } finally {
      _missingRunning = false;
    }
  }

  Future<void> _writeMissingOnce() async {
    final List<Blessing> all;
    try {
      all = waitingOrder(await _store.list());
    } catch (e) {
      return debugPrint('words: $e');
    }
    if (Phone.android) {
      // the places kept for recordings no longer on the phone
      final names = {for (final b in all) ?_audioOf(b)}.map(path.basename).toSet();
      unawaited(AndroidWords.instance.tidy(names));
    }
    for (final stored in all) {
      final path = _audioOf(stored);
      if (path == null) continue;
      // the blessing just recorded: its session is writing its words
      if (stored.id == _session.draft?.id && (_session.wordsState == WordsState.writing || _session.wordsState == WordsState.none)) continue;
      if (wordsDueFromRecording(stored, audioOnPhone: true)) {
        await _writeLaterWords(stored);
        continue;
      }
      if (couldTryWordsAgain(stored, audioOnPhone: true)) {
        await _tryWordsAgain(stored);
        continue;
      }
      if (!needsWords(stored, audioOnPhone: true)) continue;
      if (!mounted) return;
      // the one in the sky, so the review page and the caption see the words arrive
      final b = _blessings.firstWhere((x) => x.id == stored.id, orElse: () => stored);
      setState(() => _writing[b.id] = WordsState.writing);
      var state = WordsState.failed;
      try {
        await RecordSession.debugHoldWords();
        final t = await _transcriber.transcribe(path, SpeechLanguage.fromCode(b.language));
        state = t.later ? WordsState.later : t.unavailable ? WordsState.unavailable : WordsState.done;
        if (state == WordsState.done && b.rawText.trim().isEmpty) {
          b
            ..rawText = t.text
            ..firstText = t.text;
        }
      } catch (e) {
        debugPrint('words: ${b.id}: $e');
      }
      b.wordsStatus = _statusOf(state);
      try {
        await _store.update(b);
        debugPrint('words: wrote ${b.id} (${b.wordsStatus.code}, ${b.rawText.length} characters)');
      } on StateError {
        // deleted while the words were being written
      }
      if (!mounted) return;
      setState(() => _writing[b.id] = state);
    }
  }

  /// Ids being tried again now, so the launch and the review page do not try the same one twice.
  final Set<String> _retrying = {};

  /// A draft whose words could not be written on this phone ("The recording stays here until they
  /// can be"): tried again, quietly, now that the phone may be able to write its language. Nothing
  /// is shown unless the words come; then they drop into the box as any late words do.
  Future<void> _tryWordsAgain(Blessing stored) async {
    final path = _audioOf(stored);
    if (path == null || !couldTryWordsAgain(stored, audioOnPhone: true) || !_retrying.add(stored.id)) return;
    try {
      final b = _blessings.firstWhere((x) => x.id == stored.id, orElse: () => stored);
      final Transcript t;
      try {
        t = await _transcriber.transcribe(path, SpeechLanguage.fromCode(b.language));
      } catch (e) {
        return debugPrint('words: again ${b.id}: $e');
      }
      if (t.unavailable || t.later) return debugPrint('words: ${b.id} still cannot be written here');
      // typed in meanwhile: the person's words stand
      if (b.rawText.trim().isNotEmpty) return;
      b
        ..rawText = t.text
        ..firstText = t.text
        ..wordsStatus = WordsStatus.written;
      try {
        await _store.update(b);
        debugPrint('words: wrote ${b.id} on trying again (${b.rawText.length} characters)');
      } on StateError {
        return; // deleted meanwhile
      }
      if (!mounted) return;
      final reviewing = identical(_reviewing, b) && _stage == Stage.review;
      setState(() => _writing[b.id] = WordsState.done);
      if (reviewing) _reviewKey.currentState?.wordsArrived();
    } finally {
      _retrying.remove(stored.id);
    }
  }

  /// THE SEAM, Dart side: a recording kept for its words (`WordsStatus.later`, see [keepsRecording])
  /// is given to the phone again, at every launch and whenever its review page opens. Until the
  /// next task fills `transcribe` in android/.../SpeechChannel.kt, Android answers "later" and
  /// nothing changes. When words come:
  ///  - nothing typed: they are the blessing's words, as after any Amen;
  ///  - words typed meanwhile: the person's words stand, and the phone's are kept beneath them as
  ///    the first transcript (`firstText`), as the iPhone keeps its own;
  ///  - the blessing is `written`, and if its review was already finished, its recording is erased
  ///    now, as it would have been at Done.
  /// A failure, or a phone that cannot write the language, leaves it `later`: tried again next time.
  Future<void> _writeLaterWords(Blessing stored) async {
    final path = _audioOf(stored);
    if (path == null || !wordsDueFromRecording(stored, audioOnPhone: true) || !_retrying.add(stored.id)) return;
    try {
      final b = [..._blessings, ..._passing].firstWhere((x) => x.id == stored.id, orElse: () => stored);
      final Transcript t;
      // Android with the model here: the page shows the words being written, piece by piece
      final able = Phone.android && WordsModel.instance.status.ready;
      if (able && mounted) setState(() => _writing[b.id] = WordsState.writing);
      try {
        t = await _transcriber.transcribe(path, SpeechLanguage.fromCode(b.language));
      } catch (e) {
        if (able && mounted) setState(() => _writing.remove(b.id));
        return debugPrint('words: later ${b.id}: $e');
      }
      if (t.later || t.unavailable) {
        if (able && mounted) setState(() => _writing.remove(b.id));
        return;
      }
      final typed = b.rawText.trim().isNotEmpty;
      final erase = takeLaterWords(b, t.text);
      // the blessing just recorded is held by its session as a copy of its own: the page after Amen
      // and its review read that one, so it takes the words too
      final draft = _session.draft;
      if (draft != null && draft.id == b.id && !identical(draft, b)) takeLaterWords(draft, t.text);
      try {
        await _store.update(b);
        if (erase) await _store.eraseAudio(b);
        debugPrint('words: wrote ${b.id} from its kept recording (${t.text.length} characters, typed: $typed)');
      } on StateError {
        return; // deleted meanwhile
      }
      if (!mounted) return;
      final reviewing = identical(_reviewing, b) && _stage == Stage.review;
      setState(() => _writing[b.id] = WordsState.done);
      if (reviewing && !typed) _reviewKey.currentState?.wordsArrived();
    } finally {
      _retrying.remove(stored.id);
    }
  }

  static WordsStatus _statusOf(WordsState s) => switch (s) {
        WordsState.done => WordsStatus.written,
        WordsState.unavailable => WordsStatus.unavailable,
        WordsState.failed => WordsStatus.failed,
        WordsState.later => WordsStatus.later,
        WordsState.none || WordsState.writing => WordsStatus.pending,
      };

  /// "Review now" on the sheet: the oldest recovered blessing's review page.
  Future<void> _reviewRecovered() async {
    if (!_recoveredSheet) return;
    setState(() => _recoveredSheet = false);
    final i = _recovered.isEmpty ? -1 : _blessings.indexWhere((b) => b.id == _recovered.first.id);
    if (i < 0 || _stage != Stage.home) return;
    _engine.setFocus(i);
    _showNow();
    await _openReview(_blessings[i], from: Stage.home);
  }

  void _laterRecovered() => setState(() => _recoveredSheet = false);

  /// Put [list] in the sky with [focus] in focus, without moving the camera.
  void _setBlessings(List<Blessing> list, {required int focus}) {
    _blessings = list;
    placement.apply(_blessings, begins: _begins);
    if (_locked) {
      // kept for when it is unlocked; nothing in the sky meanwhile
      _lockedFocus = math.max(0, focus);
      _line = const [];
      _engine.setBlessings(const [], focus: 0);
      return;
    }
    _line = placement.line(_blessings);
    _engine.setBlessings(_blessings, focus: math.max(0, focus));
  }

  /// Turn the home sky to blessing [i], or to the empty sky when there is none to show.
  void _lookHome(int i) {
    if (_blessings.isEmpty || _locked) {
      _engine.lookToward(emptyRa, emptyDec);
    } else {
      _engine.lookAt(i);
    }
  }

  void _onEngine() {
    // while recording, the engine's focus is the draft, which the caption never shows
    if (_engine.focus >= _blessings.length) return setState(() {});
    if (_engine.focus != _shown && !_swapping && _stage == Stage.home) {
      // fade the words out, change them, fade them back in
      setState(() => _swapping = true);
      _swapTimer?.cancel();
      _swapTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        setState(() {
          _shown = _engine.focus;
          _swapping = false;
        });
      });
    } else {
      setState(() {});
    }
  }

  /// Show the caption for the blessing in focus now, without the cross-fade.
  void _showNow() {
    _swapTimer?.cancel();
    _shown = _engine.focus;
    _swapping = false;
  }

  void _cameBack() {
    _awayTimer?.cancel();
    if (!_away || !mounted) return;
    setState(() => _away = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _awayTimer?.cancel();
      _away = true;
    } else if (state == AppLifecycleState.resumed && _away) {
      // the lock says so in _onActive; where there is no lock to ask, or it never says, not for long
      if (!_lock.active) {
        _cameBack();
      } else {
        _awayTimer?.cancel();
        _awayTimer = Timer(const Duration(seconds: 3), _cameBack);
      }
    }
    // the opening and the welcome wait while the app cannot be seen (a question over it, Control
    // Centre, the app switcher), and go on from where they were when it can
    _setVisible(state == AppLifecycleState.resumed);
    // back from Settings: look again at what is allowed
    if (state == AppLifecycleState.resumed && _stage == Stage.record && !_session.live) {
      _session.checkPermissions(ask: false);
    }
    // back from the Settings app from a refused row of the first run: look again
    if (state == AppLifecycleState.resumed && _onboard == Onboard.permissions) unawaited(_perms?.recheck());
    // back from the Settings app after "Use my location": if now allowed, look
    if (state == AppLifecycleState.resumed && _stage == Stage.settings) {
      final w = _where;
      if (w != null) {
        w.recheck().then((_) {
          if (w.status == LocationStatus.granted) w.refresh();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WordsModel.instance.notWhenReady(_modelArrived);
    _lock.removeListener(_onLock);
    _lock.api.onActive = null;
    _swapTimer?.cancel();
    _demoTimer?.cancel();
    _awayTimer?.cancel();
    _noticeTimer?.cancel();
    _openingTimer?.cancel();
    _perms?.dispose();
    _session.dispose();
    if (widget.player == null) _player.dispose();
    _engine
      ..removeListener(_onEngine)
      ..dispose();
    super.dispose();
  }

  void _pick(int i, {required bool fresh}) {
    if (i != _engine.focus) {
      _engine.setFocus(i);
    } else if (_engine.free && fresh) {
      _engine.lookAt(i);
    }
  }

  // ---- recording ----

  /// "New blessing": a draft given now, its light placed by the rule, and the camera turned to it.
  void _openRecord() {
    if (_stage != Stage.home || (_recoveredSheet && !_locked) || !_lock.ready) return;
    _homeFocus = _locked ? _lockedFocus : _engine.focus;
    _session.dispose();
    _session = RecordSession(recorder: _recorder, transcriber: _transcriber);
    _setUpSession(_session);
    // for whoever's sky is showing; locked, for the person's own until unlocked and said otherwise
    final draft = draftBlessing(DateTime.now(), place: _where?.place ?? saltLakeTemple, personId: recordingPerson(locked: _locked, ring: _ring));
    _session.draft = draft;
    _placeDraft(draft);
    _engine.setView(SkyView.ready);
    _engine.lookAt(_engine.focus);
    setState(() {
      _stage = Stage.record;
      _list = false;
    });
  }

  /// The session's language (remembered, else the phone's) and audio folder, and the permissions:
  /// asked here, on the ready screen, the first time it opens; never during a blessing.
  Future<void> _setUpSession(RecordSession s) async {
    final (settings, dir) = await _speechSetup;
    if (!identical(s, _session)) return;
    final phone = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    // the language set in Settings, else the phone's
    s
      ..audioDir = dir
      ..setLanguage(SpeechLanguage.fromCode(settings.language ?? SpeechLanguage.forPhone(phone).code));
    // let the ready screen settle before the system asks
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // after the first run, the recording screen never puts a system question: its refused line
    // and Open Settings are the way back
    final ask = recordScreenMayAsk(settings.firstRun);
    // Android asks when Begin is pressed instead (_begin), so its question answers a press
    if (identical(s, _session) && !s.live) await s.checkPermissions(ask: ask && !NotYet.android);
    // then, the first time ever, where blessings are given (after the microphone and speech
    // questions, never once Begin is pressed; Begin never waits for it)
    bool ready() => identical(s, _session) && !s.live && _stage == Stage.record;
    if (ready()) await _where?.onRecordScreen(stillReady: () => ask && ready());
  }

  /// The pull-down on the Begin screen. The choice is remembered: it is the same setting the
  /// Settings page shows, so someone who records in Spanish on an English phone chooses once.
  void _setLanguage(SpeechLanguage l) {
    _session.setLanguage(l);
    unawaited(_settings?.setLanguage(l.code));
  }

  void _begin() {
    if (!_session.canBegin) {
      // Android: the microphone not asked yet (the first run's row was never reached): Android's
      // question now, and the recording begins as soon as it is allowed
      if (NotYet.android && _session.permissions?.microphone == Permission.undetermined) {
        unawaited(_askThenBegin(_session));
        return;
      }
      _session.checkPermissions(ask: recordScreenMayAsk(_settings?.firstRun));
      return;
    }
    if (_session.practice) {
      // the practice puts no light in the sky and keeps nothing
      _engine.setView(SkyView.record);
      _session.begin();
      return;
    }
    final draft = _session.draft!;
    // the blessing is given from the moment Begin is pressed
    final now = DateTime.now();
    draft
      ..utc = now.toUtc()
      ..utcOffset = now.timeZoneOffset
      ..place = _where?.place ?? draft.place;
    _placeDraft(draft);
    _engine.lookAt(_engine.focus);
    _engine.breathT0 = _engine.clock;
    _engine.setView(SkyView.record);
    _engine.show?.start(_engine, draft.ra, draft.dec, SkyView.record, _engine.size);
    draft.language = _session.language.code;
    _session.begin();
  }

  Future<void> _askThenBegin(RecordSession s) async {
    await s.checkPermissions(ask: true);
    if (identical(s, _session) && s.canBegin && !s.live && _stage == Stage.record) _begin();
  }

  /// The draft goes at the end of the line, the place for "now", and is the light in focus.
  void _placeDraft(Blessing draft) {
    // locked: only its own light; nothing of any earlier blessing
    final all = recordingLights(locked: _locked, blessings: _blessings, draft: draft);
    placement.apply(all, now: draft.utc, begins: _locked ? null : _begins);
    _engine.setBlessings(all, focus: all.length - 1);
  }

  /// Held Discard in the first ten seconds: nothing kept, back to Begin.
  void _discardEarly() {
    _session.discard();
    _engine.show?.stop();
    _engine.setView(SkyView.ready);
  }

  /// Close before Begin, or Discard from the sheet: nothing kept, back to the sky.
  void _closeRecord() {
    if (_session.practice) return unawaited(_closePractice());
    _session.discard();
    _engine.show?.stop();
    _setBlessings(_blessings, focus: _homeFocus);
    _engine.setView(SkyView.home);
    _lookHome(_homeFocus);
    setState(() => _stage = Stage.home);
  }

  void _amen() {
    if (_session.practice) return unawaited(_practiceAmen());
    final session = _session;
    _saved = _keep(session);
    _engine.show?.stop();
    _engine.setView(SkyView.after);
    setState(() => _stage = Stage.after);
  }

  /// After Amen: the blessing is written to the store at once with its audio, so nothing is lost
  /// if the app is closed now; then its words are written from the audio, on the phone, and saved.
  Future<void> _keep(RecordSession session) async {
    final file = await session.finish();
    final draft = session.draft!;
    // the place found by now, if any; else the Salt Lake Temple
    draft
      ..place = _where?.place ?? draft.place
      ..ownership = Ownership.forMe
      ..draft = true
      ..audio = file == null ? '' : path.basename(file)
      ..wordsStatus = file == null ? WordsStatus.failed : WordsStatus.pending
      ..created = DateTime.now().toUtc()
      ..updated = draft.created;
    await _store.create(draft);
    // in the store now: if the app closes before the words are written, the next launch writes them
    await session.forget();
    // the words come later; Save for later need not wait for them
    unawaited(_writeWords(session, draft));
  }

  Future<void> _writeWords(RecordSession session, Blessing draft) async {
    await session.transcribe();
    draft.wordsStatus = _statusOf(session.wordsState);
    if (session.wordsState == WordsState.done) {
      draft
        ..rawText = session.words
        ..firstText = session.words;
    }
    try {
      await _store.update(draft);
    } on StateError {
      return; // deleted while the words were being written
    }
    if (mounted) setState(() {});
  }

  /// The new blessing (already in the store) joins the sky, in focus; its place in the list.
  Future<int?> _joinSky() async {
    final draft = _session.draft!;
    await _saved;
    if (!mounted) return null;
    if (draft.personId != _ring) {
      // recorded for another ring (one recorded while locked is the person's own): that sky shows
      await _reloadFamily();
      if (!mounted) return null;
      _setRing(draft.personId);
    }
    final list = [..._blessings.where((b) => b.id != draft.id), draft]..sort((a, b) => a.utc.compareTo(b.utc));
    final i = list.indexOf(draft);
    _setBlessings(list, focus: i);
    return i;
  }

  /// "Save for later": the new blessing joins the sky and the sky comes back (Reduce Motion: it
  /// fades in, and the sky neither turns nor zooms).
  Future<void> _saveForLater() async {
    final i = await _joinSky();
    if (i == null) return;
    _engine.setView(SkyView.home);
    _lookHome(i);
    if (_engine.reduceMotion) _engine.crossFade();
    setState(() {
      _showNow();
      _stage = Stage.home;
    });
  }

  /// "Review now": the new blessing joins the sky, and its review page opens over it.
  Future<void> _reviewNow() async {
    if (_stage != Stage.after) return;
    // locked: unlock first; if not, stay here
    if (_locked && !await _askToUnlock()) return;
    if (_stage != Stage.after) return;
    final i = await _joinSky();
    if (i == null) return;
    _showNow();
    await _openReview(_blessings[i], from: Stage.home);
  }

  // ---- review ----

  /// The review page for [b] (in the sky, in focus) over the dimmed sky.
  Future<void> _openReview(Blessing b, {required Stage from}) async {
    unawaited(_tryWordsAgain(b));
    unawaited(_writeLaterWords(b));
    _knownTags = await _store.allTags();
    if (!mounted) return;
    _reviewing = b;
    _reviewFrom = from;
    _skyFor(SkyView.review);
    setState(() => _stage = Stage.review);
  }

  /// The recording of [b], when its file is on the phone.
  String? _audioOf(Blessing? b) {
    final path = b == null ? null : _store.audioPath(b);
    return path != null && File(path).existsSync() ? path : null;
  }

  /// Where the words of [b] are: the session's for the one just recorded; otherwise as stored, or
  /// as being written at this launch.
  WordsState? _wordsOf(Blessing? b) {
    if (b == null) return null;
    // written at this launch (a kept recording, once the model arrived) before the session's state
    final w = _writing[b.id];
    if (w != null) return w;
    if (identical(b, _session.draft)) return _session.wordsState;
    return switch (b.wordsStatus) {
      WordsStatus.written => WordsState.done,
      WordsStatus.unavailable => WordsState.unavailable,
      WordsStatus.failed => WordsState.failed,
      WordsStatus.later => WordsState.later,
      // still to be written this launch when its audio is here
      WordsStatus.pending => _audioOf(b) != null && b.rawText.trim().isEmpty ? WordsState.writing : WordsState.failed,
    };
  }

  Future<void> _saveReview() async {
    final b = _reviewing;
    if (b == null) return;
    try {
      await _store.update(b);
    } on StateError {
      return; // deleted meanwhile
    }
    if (mounted) setState(() {});
  }

  /// The back chevron: a draft stays a draft; back where the page was opened from. An entry left
  /// with nothing in it at all is not kept.
  void _closeReview() {
    final b = _reviewing;
    if (b != null && isEmptyEntry(b)) unawaited(_dropEntry(b));
    if (_reviewFrom == Stage.read) {
      _skyFor(SkyView.read);
      setState(() => _stage = Stage.read);
    } else {
      _aside = null;
      _engine.setView(SkyView.home);
      _engine.lookAt(_engine.focus);
      setState(() {
        _showNow();
        _stage = Stage.home;
      });
    }
  }

  /// Done (and Finish, when there was a recording): no longer a draft, the recording erased from
  /// the phone, and the blessing's reading page.
  ///
  /// Except a recording whose words the phone has not written yet (`WordsStatus.later`: Android,
  /// for now): it is kept, typed words or not, until the phone writes the words from it
  /// ([_writeLaterWords]), and erased then (keepsRecording, recovery.dart).
  Future<void> _finishReview() async {
    final b = _reviewing;
    if (b == null) return;
    final arriving = b.entered && b.draft && b.placed && _reviewFrom == Stage.home;
    b.draft = false;
    await _saveReview();
    if (!keepsRecording(b)) await _store.eraseAudio(b);
    if (!mounted) return;
    if (arriving) return _entryArrives(b);
    if (identical(b, _aside) && _reviewFrom == Stage.home) _readFrom = Stage.home;
    _skyFor(SkyView.read);
    setState(() => _stage = Stage.read);
  }

  // ---- entering a past blessing ----

  /// "Enter a past blessing" on the recording start: the recording is put away, and an entry (a
  /// draft with no date and no words, kept in the store from the start, so nothing typed is lost)
  /// opens on the review page, for whoever's sky is showing. Never while locked.
  Future<void> _openEntry() async {
    if (_stage != Stage.record || _locked || _session.live || _session.practice) return;
    final person = _session.draft?.personId ?? _ring;
    _session.discard();
    _engine.show?.stop();
    final b = enteredBlessing(DateTime.now(), place: _where?.place ?? saltLakeTemple, personId: person);
    await _store.create(b);
    await _reloadFamily();
    if (!mounted || _locked) return;
    // the sky as it was, without the recording's new light; the entry has none until it has a date
    _setBlessings(_blessings, focus: _homeFocus);
    _aside = b;
    _readFrom = Stage.home;
    await _openReview(b, from: Stage.home);
  }

  /// An entered blessing's date was set or changed: its light takes its place on its ring (the
  /// ring's start moves back when it is the earliest; the others slide closer), in focus behind the page.
  Future<void> _entryGiven() async {
    final b = _reviewing;
    if (b == null || !b.placed || !mounted) return;
    await _reloadFamily();
    if (!mounted || !identical(b, _reviewing)) return;
    if (b.ownership == Ownership.passingOn) return setState(() {});
    final ring = _family.known(b.personId);
    if (ring != _ring) _setRing(ring);
    final list = [..._blessings.where((x) => x.id != b.id), b]..sort((x, y) => x.utc.compareTo(y.utc));
    _aside = null;
    _setBlessings(list, focus: list.indexOf(b));
    _engine.setView(_stage == Stage.read ? SkyView.read : SkyView.review);
    _engine.lookAt(_engine.focus);
    setState(() {});
  }

  /// Done on a new entry: the sky turns to its light, which brightens in place (Reduce Motion: it
  /// fades in, and the sky does not turn).
  void _entryArrives(Blessing b) {
    _aside = null;
    final i = _blessings.indexWhere((x) => x.id == b.id);
    _engine.setView(SkyView.home);
    if (i >= 0) _engine.setFocus(i, instant: _engine.reduceMotion);
    if (_engine.reduceMotion) _engine.crossFade();
    setState(() {
      _showNow();
      _stage = Stage.home;
    });
  }

  Future<void> _dropEntry(Blessing b) async {
    try {
      await _store.delete(b.id);
    } catch (_) {}
    await _reloadFamily();
    if (mounted) setState(() {});
  }

  // ---- the changes polish made ----

  /// The changes screen for [b], over the page it was opened from.
  void openChanges(Blessing b, {required Stage from}) {
    if (b.changes.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_player.playing) _player.pause();
    _changing = b;
    _changesFrom = from;
    setState(() => _stage = Stage.changes);
  }

  Future<void> _saveChanges() async {
    final b = _changing;
    if (b == null) return;
    try {
      await _store.update(b);
    } on StateError {
      return;
    }
  }

  void _closeChanges() {
    unawaited(_saveChanges());
    setState(() => _stage = _changesFrom);
  }

  /// For tests: the changes screen, when open.
  ChangesLayerState? get changesScreen => _changesKey.currentState;

  // ---- drafts waiting ----

  /// How many blessings are still drafts: those in the sky and those to pass along.
  int get _drafts => _blessings.where((b) => b.draft).length + _passing.where((b) => b.draft).length + _unplaced.length;

  /// Entries on the ring showing still being written, with no date yet: no light, but waiting, so
  /// counted in the badge.
  List<Blessing> get _unplaced => [for (final b in _family.unplaced) if (_family.known(b.personId) == _ring) b];

  /// The badge: the review page of the oldest draft, of either kind.
  Future<void> _reviewOldestDraft() async {
    if (_stage != Stage.home || _recoveredSheet) return;
    final drafts = [..._blessings, ..._passing, ..._unplaced].where((b) => b.draft).toList()..sort((a, b) => a.utc.compareTo(b.utc));
    if (drafts.isEmpty) return;
    final d = drafts.first;
    // passed along, or an entry with no date yet: no light to frame
    if (d.ownership == Ownership.passingOn || !d.placed) {
      _aside = d;
      _readFrom = Stage.home;
      return _openReview(d, from: Stage.home);
    }
    final i = _blessings.indexOf(d);
    _engine.setFocus(i, instant: true);
    _showNow();
    await _openReview(_blessings[i], from: Stage.home);
  }

  /// The sky behind a page about [b]: its own light framed, or, for one passed along (no light),
  /// the sky dimmed as behind Settings.
  void _skyFor(SkyView view) {
    if (_aside != null) {
      _engine.setView(SkyView.settings);
    } else {
      _engine.setView(view);
      _engine.lookAt(_engine.focus);
    }
  }

  // ---- passing it along ----

  /// "Whose blessing" changed on the review page: the blessing joins or leaves the sky; put on
  /// another ring, that ring's sky shows, with it in focus.
  Future<void> _ownershipChanged(Whose w) async {
    final b = _reviewing;
    if (b == null || !mounted) return;
    final ring = w.ring;
    // an entry with no date yet has no light on any ring: only whose it is changes
    if (!b.placed) {
      await _reloadFamily();
      if (mounted) setState(() {});
      return;
    }
    if (ring != null && ring != _ring) {
      await _reloadFamily();
      if (!mounted || !identical(b, _reviewing)) return;
      _passing = _passing.where((x) => x.id != b.id).toList();
      _aside = null;
      _setRing(ring);
      final list = [..._blessings.where((x) => x.id != b.id), b]..sort((a, b) => a.utc.compareTo(b.utc));
      _setBlessings(list, focus: list.indexOf(b));
      _engine.setView(_stage == Stage.read ? SkyView.read : SkyView.review);
      _engine.lookAt(_engine.focus);
      if (_readFrom == Stage.passing) _readFrom = Stage.home;
      return setState(() {});
    }
    if (ring == null) {
      final i = _blessings.indexWhere((x) => x.id == b.id);
      if (i >= 0) {
        final list = [..._blessings]..removeAt(i);
        _setBlessings(list, focus: math.min(i, list.length - 1));
      }
      _passing = [..._passing.where((x) => x.id != b.id), b]..sort((a, b) => a.utc.compareTo(b.utc));
      _aside = b;
      _engine.setView(SkyView.settings);
    } else {
      _passing = _passing.where((x) => x.id != b.id).toList();
      final list = [..._blessings.where((x) => x.id != b.id), b]..sort((a, b) => a.utc.compareTo(b.utc));
      _aside = null;
      _setBlessings(list, focus: list.indexOf(b));
      _engine.setView(_stage == Stage.read ? SkyView.read : SkyView.review);
      _engine.lookAt(_engine.focus);
      // its reading page, when it was opened from the list of those to pass along, now goes home
      if (_readFrom == Stage.passing) _readFrom = Stage.home;
    }
    setState(() {});
  }

  void _openPassing() {
    if (_stage != Stage.settings) return;
    unawaited(_reloadPassing());
    setState(() => _stage = Stage.passing);
  }

  void _closePassing() => setState(() => _stage = Stage.settings);

  /// A row of "To pass along": its reading page, over the dimmed sky.
  void _openAside(Blessing b) {
    if (_stage != Stage.passing) return;
    _aside = b;
    _readFrom = Stage.passing;
    _engine.setView(SkyView.settings);
    setState(() => _stage = Stage.read);
  }

  /// It left the phone: when it was sent is kept ("To pass along" shows it).
  Future<void> _sent(Blessing b) async {
    b.sent = DateTime.now().toUtc();
    try {
      await _store.update(b);
    } on StateError {
      return;
    }
    if (mounted) setState(() {});
  }

  // ---- your links ----

  void _openLinks({required Stage from}) {
    if (_locked || _links == null) return;
    _linksFrom = from;
    if (from != Stage.read) _aside = null;
    _engine.setView(SkyView.settings);
    setState(() => _stage = Stage.links);
  }

  void _closeLinks() {
    if (_linksFrom == Stage.read) {
      _skyFor(SkyView.read);
    } else {
      _engine.setView(SkyView.settings);
    }
    setState(() => _stage = _linksFrom);
  }

  Future<int> _liveLinks(Blessing b) async => (await _links?.liveOf(b.id))?.length ?? 0;

  // ---- settings ----

  void _openSettings() {
    if (_stage != Stage.home || _locked) return;
    unawaited(_lock.recheck());
    unawaited(_where?.recheck());
    _engine.setView(SkyView.settings);
    setState(() {
      _stage = Stage.settings;
      _list = false;
    });
  }

  void _closeSettings() {
    _engine.setView(SkyView.home);
    setState(() {
      _showNow();
      _stage = Stage.home;
    });
  }

  /// The phone check page, over everything (PHONE_CHECK builds only).
  void _openPhoneCheck() {
    if (!phoneCheck) return;
    PhoneCheckPage.open(context, widget.palette);
  }

  Future<void> _setRecordingLanguage(String? code) async {
    await _settings?.setLanguage(code);
    if (mounted) setState(() {});
  }

  // ---- blessing files that arrive (share/receive.dart) ----

  Future<void> _startReceiving() async {
    try {
      final waiting = await _share.receiving((f) {
        final place = f.shortcut;
        place != null ? _shortcut = place : _inbox.add(f);
        if (mounted) setState(() {});
      });
      for (final f in waiting) {
        final place = f.shortcut;
        place != null ? _shortcut = place : _inbox.add(f);
      }
    } catch (e) {
      debugPrint('receive: $e');
    }
    _arrivalsOpen = true;
    if (mounted) setState(() {});
  }

  /// What arrived: a blessing file, or a link, fetched and opened (share/links.dart). The link is
  /// never logged (its fragment is the key).
  Future<Arrival> _arrivalOf(IncomingFile f) async {
    final link = f.link;
    if (link == null) return arrivalOf(f, _store.get);
    final parts = linkPartsOf(link, debug: kDebugMode);
    if (parts == null) return const ArrivalUnreadable('link: not a blessing link');
    final l = _links;
    // a phone that cannot fetch at all (the host): as with no internet
    if (l == null) return const ArrivalOnItsWay();
    final a = await l.open(parts);
    debugPrint('receive: link ${a.runtimeType}');
    return a;
  }

  /// A file may be shown now: unlocked, nothing else asking, not recording or just past Amen, and on
  /// the sky, a reading page or Settings (never over a page being edited).
  bool get _arrivalMayShow =>
      _arrivalsOpen &&
      !_away &&
      _lock.ready &&
      !_locked &&
      !_lock.asking &&
      !_receiving &&
      !_arrivalBusy &&
      !_recoveredSheet &&
      !_session.live &&
      _onboard == Onboard.none &&
      (_stage == Stage.home || (_stage == Stage.read && _aside == null) || _stage == Stage.settings || _stage == Stage.passing || _stage == Stage.links);

  /// Called after each frame while files wait: the next one, when it may be shown.
  void _scheduleArrival() {
    if (_arrivalScheduled || _inbox.isEmpty || !_arrivalMayShow) return;
    _arrivalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _arrivalScheduled = false;
      unawaited(_nextArrival());
    });
  }

  Future<void> _nextArrival() async {
    if (!mounted || _inbox.isEmpty || !_arrivalMayShow) return;
    _arrivalBusy = true;
    final f = _inbox.removeAt(0);
    Arrival a;
    try {
      a = await _arrivalOf(f);
    } catch (e) {
      a = ArrivalUnreadable('$e');
    }
    _arrivalBusy = false;
    if (!mounted) return;
    if (a is ArrivalUnreadable) debugPrint('receive: ${a.why}');
    // locked meanwhile: it waits for the next unlock
    if (_locked) {
      _inbox.insert(0, f);
      return setState(() {});
    }
    if (a is ArrivalSame) {
      // no question: it opens, saying so
      await _openReceived(a.mine.id);
      _notice();
      return setState(() {});
    }
    if (a is ArrivalRing && a.fresh.isEmpty) {
      // a ring handed over whose every blessing is here already: the person's own sky, saying so
      await _switchSky('');
      if (mounted) _notice(Strings.ringAlreadyHave);
      return setState(() {});
    }
    setState(() {
      _arrivalFile = f;
      _arrival = a;
      _receiving = true;
    });
  }

  // ---- shortcuts (share/share.dart, ShortcutPlace) ----

  /// A shortcut may be followed now: back in front, with no first run, sheet or file in the way, and
  /// as far as the lock goes (locked.dart): Open my blessings once unlocked, as a blessing file is
  /// shown; Record a blessing also while locked, as the locked New blessing button (the sheets of
  /// recovered drafts and arriving files are not shown while locked, so they are not in its way).
  bool get _shortcutMayGo {
    final place = _shortcut;
    if (place == null || !shortcutPassesLock(place, locked: _locked, asking: _lock.asking)) return false;
    return _arrivalsOpen &&
        !_away &&
        _lock.ready &&
        (_locked || (!_receiving && !_recoveredSheet)) &&
        !_arrivalBusy &&
        _onboard == Onboard.none &&
        _afterUnlock == null;
  }

  /// Called after each frame while a shortcut waits.
  void _scheduleShortcut() {
    if (_shortcutScheduled || _shortcut == null || !_shortcutMayGo) return;
    _shortcutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortcutScheduled = false;
      if (mounted && _shortcutMayGo) _goShortcut();
    });
  }

  /// Go where the shortcut leads: the recording start (as New blessing; the microphone waits for
  /// Begin), or the sky. A recording under way, the screen after Amen, and a page being edited are
  /// never left: the app comes to the front where it was.
  void _goShortcut() {
    final place = _shortcut;
    _shortcut = null;
    if (place == null) return;
    debugPrint('shortcut: ${place.name} from ${_stage.name}');
    if (_session.live || _stage == Stage.after || _stage == Stage.review || _stage == Stage.changes) return;
    if (_stage == Stage.record) {
      if (place == ShortcutPlace.home) _closeRecord();
      return;
    }
    if (_stage != Stage.home || _list) _toHome();
    if (place == ShortcutPlace.record) _openRecord();
  }

  /// From a reading page, Settings, To pass along, Your links or the list: back to the sky.
  void _toHome() {
    _aside = null;
    _engine.setView(SkyView.home);
    _lookHome(_engine.focus);
    setState(() {
      _showNow();
      _stage = Stage.home;
      _list = false;
    });
  }

  /// Keep, or Replace mine: saved as a finished blessing of the person's own, and its reading page.
  Future<void> _keepArrival() async {
    final a = _arrival;
    setState(() {
      _receiving = false;
      _arrivalFile = null;
    });
    String? id;
    try {
      if (a is ArrivalNew) {
        final b = a.record.toBlessing(place: _where?.place ?? saltLakeTemple);
        await _store.create(b);
        id = b.id;
      } else if (a is ArrivalRing) {
        // a ring handed over: each new one joins the person's own ring by its date
        setState(() => _ringBusy = true);
        final kept = await keepRing(_store, a, place: _where?.place ?? saltLakeTemple);
        debugPrint('receive: kept ${kept.length} of a ring');
        _ringBusy = false;
        // the person's own sky, turned to the newest of those just kept
        await _switchSky('', focusId: kept.isEmpty ? null : kept.last);
        return;
      } else if (a is ArrivalDifferent) {
        final mine = a.mine;
        a.record.writeOver(mine);
        // A recording kept with the person's own copy stays (Noah, 2026-11-16): it is still the
        // blessing as it was given. A draft with its recording stays a draft, so its review page
        // (with the recording to listen to) is still the way to finish it; Done erases the
        // recording then, as for any draft. Without a recording it is finished now.
        if (_audioOf(mine) == null) mine.draft = false;
        await _store.update(mine);
        id = mine.id;
      }
    } catch (e) {
      debugPrint('receive: $e');
    }
    if (id != null && mounted) await _openReceived(id);
  }

  /// Not now, Keep mine, or OK: nothing is saved.
  void _dismissArrival() => setState(() {
        _receiving = false;
        _arrivalFile = null;
      });

  /// The sky turns to blessing [id], with its reading page.
  Future<void> _openReceived(String id) async {
    await _reloadFamily();
    if (!mounted || _locked) return;
    // on whichever ring it is (a new one is the person's own)
    final b = (await _store.get(id));
    if (!mounted || _locked || b == null || b.ownership != Ownership.forMe) return;
    _setRing(b.personId);
    final list = _family.on(_ring);
    final i = list.indexWhere((b) => b.id == id);
    if (i < 0) return;
    _aside = null;
    _readFrom = Stage.home;
    _setBlessings(list, focus: i);
    _engine.setView(SkyView.read);
    _engine.lookAt(i);
    setState(() {
      _showNow();
      _stage = Stage.read;
      _list = false;
    });
  }

  void _notice([String? text]) {
    _noticeTimer?.cancel();
    _noticeOn = true;
    _noticeText = text ?? Strings.alreadyHave;
    SemanticsService.sendAnnouncement(View.of(context), _noticeText, TextDirection.ltr);
    _noticeTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _noticeOn = false);
    });
  }

  // ---- the first run (onboarding/) ----

  late final FirstRunAsker _asker = widget.firstRunAsker ?? NativeFirstRunAsker(_locator);

  void _setVisible(bool on) {
    firstRunVisible.value = on;
    _engine.frozen = !on && const {Onboard.opening, Onboard.welcome, Onboard.sharedLine}.contains(_onboard);
  }

  /// Move the first run to [next]; the step it leaves stays built while it fades out. [slide]: the
  /// two move as a step across the still sky, [FirstRunFade.slide].
  void _go(Onboard next, {bool slide = false}) {
    final was = _onboard;
    if (was == next) return;
    if (slide) {
      _sliding.addAll([was, next]);
    } else {
      _sliding
        ..remove(was)
        ..remove(next);
    }
    if (was != Onboard.none && was != Onboard.waiting) {
      _leaving.add(was);
      Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _leaving.remove(was));
      });
    }
    _leaving.remove(next);
    setState(() => _onboard = next);
  }

  /// Once the launch knows whether a blessing file opened the app: where the first run begins.
  Future<void> _beginFirstRun() async {
    if (_onboard != Onboard.waiting || !mounted) return;
    final settings = _settings!;
    // a file the app was opened with can land just after the first look
    if (settings.firstRun == null && _inbox.isEmpty) await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || _onboard != Onboard.waiting) return;
    final start = firstRunStart(settings.firstRun, hasBlessings: _blessings.isNotEmpty && !seedWithFirstRun, fileWaiting: _inbox.isNotEmpty);
    // the first run is where a fresh install opens, whatever shortcut opened it
    if (start != FirstRunStart.none) _shortcut = null;
    debugPrint('first run: ${settings.firstRun ?? 'fresh'} -> ${start.name}');
    if (_locked && start != FirstRunStart.none) {
      // a blessing was kept at a shared first launch: the lock first, then the rest
      _afterUnlock = start;
      _engine.setView(SkyView.home);
      return _go(Onboard.none);
    }
    await _resumeFirstRun(start);
  }

  Future<void> _resumeFirstRun(FirstRunStart start) async {
    switch (start) {
      case FirstRunStart.none:
        _engine.setView(SkyView.home);
        _go(Onboard.none);
      case FirstRunStart.opening:
        _startOpening(shared: false);
      case FirstRunStart.shared:
        await _startShared();
      case FirstRunStart.permissions:
        _showRing(instant: true);
        _showPermissions();
      case FirstRunStart.rehearsal:
        _showRing(instant: true);
        await _showRehearsal();
    }
  }

  /// The overhead circle at the place blessings are given, the camera on the zenith now.
  ({double ra, double dec}) _showRing({bool instant = false}) {
    final place = _where?.place ?? saltLakeTemple;
    final z = zenith(DateTime.now().toUtc(), place);
    _line = [for (var i = 0; i <= 720; i++) Vec3.radec(i / 720 * tau, place.lat * deg)];
    _engine.setBlessings(const [], focus: 0);
    if (instant) _engine.lookToward(z.ra, z.dec, instant: true);
    return z;
  }

  /// Black; the sky rises as if looking up; the ring sweeps across it left to right; the name.
  /// It moves on by itself after about four seconds, or at a tap. Only the ring: the first light
  /// anyone sees is their first blessing's (ruled 2026-11-16).
  void _startOpening({required bool shared}) {
    _openingShared = shared;
    final z = _showRing();
    _engine.setView(SkyView.black);
    _engine.snap();
    _engine.lookToward(z.ra, z.dec - 22 * deg, instant: true);
    _engine.setView(SkyView.opening);
    _engine.lookToward(z.ra, z.dec);
    _engine.lineFrom = _engine.clock + .8;
    _engine.lineFor = 1.5;
    _openingTimer?.cancel();
    _openingTimer = PausableTimer(const Duration(milliseconds: 4000), _afterOpening);
    _go(Onboard.opening);
    _setVisible(firstRunVisible.value);
  }

  void _afterOpening() {
    _openingTimer?.cancel();
    if (_onboard != Onboard.opening) return;
    _engine.lineFor = 0;
    _engine.setView(SkyView.welcome);
    _go(_openingShared ? Onboard.sharedLine : Onboard.welcome);
    _setVisible(firstRunVisible.value);
  }

  Future<void> _welcomeDone() async {
    if (_onboard != Onboard.welcome) return;
    await _settings?.setFirstRun(FirstRun.permissions);
    _showPermissions(slide: true);
  }

  void _showPermissions({bool slide = false}) {
    _perms?.dispose();
    final perms = _perms = FirstRunPermissions(
      asker: _asker,
      settings: _settings!,
      announce: (t) {
        if (mounted) SemanticsService.sendAnnouncement(View.of(context), t, TextDirection.ltr);
      },
    );
    unawaited(perms.load());
    _engine.setView(SkyView.dim);
    _engine.frozen = false;
    _go(Onboard.permissions, slide: slide);
  }

  /// Continue, open once the microphone and speech recognition are answered: on to the rehearsal
  /// (or the sky, when the microphone was refused). Location and Face ID may be left: the Salt Lake
  /// Temple's sky, and the lock asks for Face ID the first time it locks.
  Future<void> _permissionsContinue() async {
    final perms = _perms;
    if (perms == null || !perms.canContinue || _onboard != Onboard.permissions) return;
    // allowed: find the place now, so the first blessing is given under its own sky
    if (perms.row(PermissionKind.location)?.status == RowStatus.allowed) unawaited(_where?.refresh());
    unawaited(_lock.recheck());
    await _settings?.setFirstRun(FirstRun.rehearsal);
    if (mounted && _onboard == Onboard.permissions) await _showRehearsal(slide: true);
  }

  /// "Try a few words first?", only when the microphone is allowed. On Android, first the one-time
  /// download that lets the phone write the words ([ModelAskLayer]); the practice shows only the
  /// words, so it is offered only once the model is here.
  Future<void> _showRehearsal({bool slide = false, bool askedModel = false}) async {
    var mic = Permission.undetermined;
    try {
      mic = await _asker.microphone();
    } catch (_) {}
    if (!mounted) return;
    if (mic != Permission.granted) return _finishFirstRun();
    if (Phone.android && !WordsModel.instance.status.ready) {
      await WordsModel.instance.refresh();
      if (!mounted) return;
      if (!WordsModel.instance.status.ready) {
        if (askedModel) return _finishFirstRun();
        _engine.setView(SkyView.dim);
        return _go(Onboard.model, slide: slide);
      }
    }
    _engine.setView(SkyView.dim);
    _go(Onboard.rehearsal, slide: slide);
  }

  /// Later or Continue on the download step: the practice if the model is here, else the sky (the
  /// download, if started, carries on).
  Future<void> _modelNext() async {
    if (_onboard != Onboard.model) return;
    await _showRehearsal(slide: true, askedModel: true);
  }

  /// The practice's own folder, in tmp: never the audio folder, so nothing in it is ever kept,
  /// recovered or backed up; emptied at every launch and after every practice.
  Future<String> _practiceDir() async => path.join(Directory.systemTemp.path, 'practice');

  Future<void> _clearPractice() async {
    try {
      final d = Directory(await _practiceDir());
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('first run: $e');
    }
  }

  /// "Try it": the real recording screen and the real engine, marked as practice.
  Future<void> _openPractice() async {
    if (_onboard != Onboard.rehearsal) return;
    await _clearPractice();
    final dir = await _practiceDir();
    await Directory(dir).create(recursive: true);
    final (settings, _) = await _speechSetup;
    if (!mounted) return;
    final phone = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _session.dispose();
    final s = _session = RecordSession(recorder: _recorder, transcriber: _transcriber, practice: true)
      ..audioDir = dir
      ..setLanguage(SpeechLanguage.fromCode(settings.language ?? SpeechLanguage.forPhone(phone).code))
      ..draft = draftBlessing(DateTime.now(), place: _where?.place ?? saltLakeTemple);
    if (firstRunFeed.isNotEmpty && _ios) {
      final feed = path.join(Directory.systemTemp.path, firstRunFeed);
      if (File(feed).existsSync()) unawaited(NativeSpeech.instance.debugFeed(feed));
    }
    unawaited(s.checkPermissions(ask: false));
    _engine.setView(SkyView.ready);
    setState(() => _stage = Stage.record);
    _go(Onboard.practice);
  }

  /// Amen in the practice: the words are written by the real engine, shown, and the audio deleted.
  Future<void> _practiceAmen() async {
    final s = _session;
    _engine.setView(SkyView.welcome);
    setState(() => _stage = Stage.home);
    _go(Onboard.practiceResult);
    await s.finish();
    await s.transcribe();
    await _clearPractice();
    if (firstRunFeed.isNotEmpty && _ios) unawaited(NativeSpeech.instance.debugFeed(null));
    debugPrint('first run: practice ${s.wordsState.name}, ${s.words.length} characters');
  }

  /// "Not now" on the practice: nothing kept, on to the sky.
  Future<void> _closePractice() async {
    _session.discard();
    await _clearPractice();
    await _finishFirstRun();
  }

  /// The end of the first run (or of the shared first launch, with [state] "rest"): the person's
  /// own sky, with "When a blessing is recorded, its light appears here." and New blessing.
  Future<void> _finishFirstRun({String state = FirstRun.done}) async {
    await _settings?.setFirstRun(state);
    if (!mounted) return;
    if (_session.practice) {
      _session.dispose();
      _session = RecordSession();
    }
    _perms?.dispose();
    _perms = null;
    _engine.lineFor = 0;
    _setBlessings(_blessings, focus: _blessings.length - 1);
    _engine.setView(SkyView.home);
    _lookHome(_engine.focus);
    setState(() => _stage = Stage.home);
    _go(Onboard.none);
  }

  // ---- the first launch from a blessing file: "Read first" ----

  Future<void> _startShared() async {
    final f = _inbox.first;
    Arrival a;
    try {
      a = await _arrivalOf(f);
    } catch (e) {
      a = ArrivalUnreadable('$e');
    }
    if (!mounted) return;
    if (a is! ArrivalNew) {
      // nothing to read here: the usual first run, and the file's own sheet after it
      return _startOpening(shared: false);
    }
    _inbox.remove(f);
    _shared = a.record.toBlessing(place: _where?.place ?? saltLakeTemple);
    _startOpening(shared: true);
  }

  void _sharedContinue() {
    if (_onboard != Onboard.sharedLine) return;
    _engine.setView(SkyView.dim);
    _go(Onboard.sharedPreview);
  }

  /// Keep: Face ID is asked now, and only now; then it is saved and opens in the person's sky.
  Future<void> _keepShared() async {
    final b = _shared;
    if (b == null || _sharedBusy) return;
    setState(() => _sharedBusy = true);
    try {
      final bio = await _asker.biometry();
      if (bio.asks && bio.state == 'ok' && !(_settings?.faceIdAsked ?? true)) {
        await _settings?.setFaceIdAsked();
        await _asker.askBiometrics(Strings.faceIdKeepReason);
      }
    } catch (e) {
      debugPrint('first run: $e');
    }
    try {
      await _store.create(b);
    } catch (e) {
      debugPrint('first run: could not keep the shared blessing: $e');
    }
    await _lock.recheck();
    await _settings?.setFirstRun(FirstRun.rest);
    if (!mounted) return;
    _shared = null;
    _sharedBusy = false;
    _line = const [];
    _engine.lineFor = 0;
    _go(Onboard.none);
    await _openReceived(b.id);
  }

  /// Not now: nothing kept; the person's empty sky. The rest of the first run comes next launch.
  Future<void> _notNowShared() async {
    if (_sharedBusy) return;
    _shared = null;
    await _finishFirstRun(state: FirstRun.rest);
  }

  List<Widget> _firstRunLayers(Palette p) {
    bool built(Onboard o) => _onboard == o || _leaving.contains(o);
    Widget layer(Onboard o, Widget Function() child, {Duration out = const Duration(milliseconds: 450)}) => Positioned.fill(
          key: ValueKey('fr-${o.name}'),
          child: FirstRunFade(on: _onboard == o, slide: _sliding.contains(o), outDuration: out, child: child()),
        );
    return [
      // the name is gone before the welcome's first line begins ([openingOut])
      if (built(Onboard.opening))
        layer(Onboard.opening, () => WhileVisible(child: OpeningLayer(palette: p, onTap: _afterOpening)), out: openingOut),
      if (built(Onboard.welcome)) layer(Onboard.welcome, () => WhileVisible(child: WelcomeLayer(palette: p, onContinue: _welcomeDone))),
      if (built(Onboard.permissions) && _perms != null)
        layer(Onboard.permissions, () => PermissionsLayer(palette: p, state: _perms!, onContinue: _permissionsContinue)),
      if (built(Onboard.model)) layer(Onboard.model, () => ModelAskLayer(palette: p, onNext: _modelNext)),
      if (built(Onboard.rehearsal))
        layer(Onboard.rehearsal, () => RehearsalAskLayer(palette: p, onTry: _openPractice, onNotNow: _finishFirstRun)),
      if (built(Onboard.practiceResult))
        layer(Onboard.practiceResult, () => PracticeResultLayer(palette: p, session: _session, onContinue: _finishFirstRun)),
      if (built(Onboard.sharedLine))
        layer(Onboard.sharedLine, () => WhileVisible(child: SharedLineLayer(palette: p, onContinue: _sharedContinue))),
      if (built(Onboard.sharedPreview))
        layer(
          Onboard.sharedPreview,
          () => SharedPreviewLayer(palette: p, blessing: _shared, busy: _sharedBusy, onKeep: _keepShared, onNotNow: _notNowShared),
        ),
    ];
  }

  // ---- family members: a sky for each (people/) ----

  /// The family members and every ring, read again from the store.
  Future<void> _reloadFamily() async {
    try {
      _family = Family(await _store.people(), await _store.list(ownership: Ownership.forMe));
    } catch (e) {
      debugPrint('family: $e');
    }
  }

  /// Show [ring]'s blessings in the sky (the newest in focus), without moving the camera, and
  /// remember it for the next launch.
  void _setRing(String ring) {
    _ring = _family.known(ring);
    unawaited(_settings?.setSky(_ring));
    final list = _family.on(_ring);
    _setBlessings(list, focus: list.length - 1);
  }

  /// Turn to [ring]'s sky: its ring, count line, ruler and list; on blessing [focusId] if given,
  /// else its newest.
  Future<void> _switchSky(String ring, {String? focusId}) async {
    await _reloadFamily();
    if (!mounted || _locked) return;
    _aside = null;
    _setRing(ring);
    final i = focusId == null ? -1 : _blessings.indexWhere((b) => b.id == focusId);
    if (i >= 0) _setBlessings(_blessings, focus: i);
    _engine.setView(SkyView.home);
    _lookHome(_engine.focus);
    setState(() {
      _showNow();
      _stage = Stage.home;
    });
  }

  /// The capsule: the menu of skies, with Add a family member and Manage family. Never while
  /// locked: nothing of any family member is shown or reachable then.
  /// Before the capsule's menu opens: the family read afresh, and false to keep it shut.
  Future<bool> _openingSkyMenu() async {
    if (_locked || _stage != Stage.home || _skyMenuOpen || _recoveredSheet || _receiving) return false;
    _skyMenuOpen = true;
    await _reloadFamily();
    if (!mounted || _locked) {
      _skyMenuOpen = false;
      return false;
    }
    return true;
  }

  /// A row of the capsule's menu chosen.
  Future<void> _skyMenuChosen(String code) async {
    final open = _skyMenuOpen;
    _skyMenuOpen = false;
    // closed by the lock: nothing chosen
    if (!open || !mounted || _locked || _stage != Stage.home) return;
    final ring = SkyMenu.ringOf(code);
    if (ring != null) {
      if (ring != _ring) await _switchSky(ring);
    } else if (code == SkyMenu.add) {
      _openPerson(null, from: Stage.home);
    } else if (code == SkyMenu.manage) {
      _openFamily();
    }
  }

  /// "Manage family", over the dimmed sky.
  void _openFamily() {
    if (_locked) return;
    _engine.setView(SkyView.settings);
    setState(() {
      _stage = Stage.family;
      _list = false;
    });
  }

  void _closeFamily() {
    _engine.setView(SkyView.home);
    _lookHome(_engine.focus);
    setState(() {
      _showNow();
      _stage = Stage.home;
    });
  }

  /// Adding a family member ([p] null), or changing one.
  void _openPerson(Person? p, {required Stage from}) {
    if (_locked) return;
    _editing = p;
    _personFrom = from;
    _engine.setView(SkyView.settings);
    setState(() {
      _stage = Stage.person;
      _list = false;
    });
  }

  void _closePerson() {
    if (_personFrom == Stage.family) return setState(() => _stage = Stage.family);
    _closeFamily();
  }

  /// Add or Save: a new one's empty ring shows at once; a change goes back to Manage family.
  Future<void> _savePerson(String name, Day? born) async {
    final editing = _editing;
    if (editing == null) {
      final p = newPerson(name, born: born);
      try {
        await _store.addPerson(p);
      } catch (e) {
        return debugPrint('family: $e');
      }
      debugPrint('family: added ${p.id}');
      return _switchSky(p.id);
    }
    try {
      final p = editing.copy()
        ..name = name
        ..born = born;
      await _store.updatePerson(p);
    } catch (e) {
      debugPrint('family: $e');
    }
    await _reloadFamily();
    if (!mounted) return;
    // their ring showing: placed again from the new birth date
    if (_ring == editing.id) _setBlessings(_family.on(_ring), focus: _engine.focus);
    setState(() => _stage = Stage.family);
  }

  /// Remove, confirmed: the family member and every blessing on their ring leave the phone; links
  /// made from those blessings are stopped first, and if one cannot be (no internet), nothing is
  /// removed and false is answered. Nothing of anyone else's is touched.
  Future<bool> _removePerson() async {
    final p = _editing;
    if (p == null) return true;
    final theirs = (await _store.list(ownership: Ownership.forMe)).where((b) => b.personId == p.id).toList();
    final links = _links;
    if (links != null) {
      for (final b in theirs) {
        if ((await links.liveOf(b.id)).isNotEmpty && await links.stopAllOf(b.id) != StopResult.stopped) return false;
      }
    }
    await _store.removePerson(p.id);
    debugPrint('family: removed ${p.id} with ${theirs.length} blessings');
    await _reloadFamily();
    if (!mounted) return true;
    if (_ring == p.id) {
      _setRing('');
      _lookHome(_engine.focus);
    }
    _editing = null;
    setState(() => _stage = Stage.family);
    return true;
  }

  /// The family member's whole ring as one link (share/ring_file.dart), kept by [keptBy].
  Future<MakeResult> _makeRing(String keptBy) async {
    final p = _editing, links = _links;
    if (p == null || links == null) return const NotMade(LinkTrouble.unavailable);
    await _reloadFamily();
    return links.makeRing(p.id, _family.on(p.id), keptBy: keptBy, title: Strings.ringOf(p.name));
  }

  /// Their ring's link was sent: the name remembered for next time, and the day on their page.
  Future<void> _ringSent(String keptBy) async {
    final p = _editing;
    if (p == null) return;
    await _settings?.setKeptBy(keptBy);
    final handed = p.copy()..handed = DateTime.now().toUtc();
    try {
      await _store.updatePerson(handed);
    } catch (e) {
      debugPrint('family: $e');
    }
    await _reloadFamily();
    if (!mounted) return;
    setState(() => _editing = _family.person(p.id) ?? handed);
  }

  // ---- reading ----

  /// Read the blessing in focus: the page rises and the sky frames its light alone.
  void _openRead() {
    if (_blessings.isEmpty || (_stage != Stage.home)) return;
    _aside = null;
    _readFrom = Stage.home;
    _engine.setView(SkyView.read);
    _engine.lookAt(_engine.focus);
    setState(() {
      _showNow();
      _stage = Stage.read;
    });
  }

  /// From a row of the list: turn to it at once and read it.
  void _openFromList(int i) {
    _engine.setFocus(i, instant: true);
    _openRead();
  }

  // ---- Android's back: the gesture and the button ----

  /// Back leaves the app (with Android's own animation home) only from the sky itself with nothing
  /// over it, and from the first run (which resumes where it was). Everywhere else [_systemBack]
  /// does what that page's own way back does.
  bool get _backLeavesApp {
    if (_locked) return true;
    if (_onboard == Onboard.practice) return false;
    if (_onboard != Onboard.none) return true;
    return _stage == Stage.home && !_list && !_recoveredSheet && !_receiving;
  }

  /// Back on Android: closes a sheet; otherwise goes back as the page's chevron does. It never ends
  /// or throws away a recording: while one listens it does nothing (Discard and its sheet are the
  /// only way to throw one away), and on the page after Amen its two buttons are the way on.
  void _systemBack() {
    if (_locked) return;
    if (_onboard == Onboard.practice) {
      // "Not now", before Begin; nothing once the practice listens
      if (!_session.live) unawaited(_closePractice());
      return;
    }
    if (_onboard != Onboard.none) return;
    switch (_stage) {
      case Stage.home:
        // a shared blessing is declined only by its own button (question 49)
        if (_receiving) return;
        if (_recoveredSheet) return _laterRecovered();
        if (_list) setState(() => _list = false);
      case Stage.record:
        if (_session.sheet) return _session.showSheet(false);
        if (!_session.live) _closeRecord();
      case Stage.after:
        return;
      case Stage.read:
        if (_readKey.currentState?.closeSheet() ?? false) return;
        _closeRead();
      case Stage.review:
        if (_reviewKey.currentState?.closeSheet() ?? false) return;
        unawaited(_reviewKey.currentState?.back());
      case Stage.changes:
        _closeChanges();
      case Stage.settings:
        _closeSettings();
      case Stage.passing:
        _closePassing();
      case Stage.links:
        if (_linksKey.currentState?.closeSheet() ?? false) return;
        _closeLinks();
      case Stage.family:
        _closeFamily();
      case Stage.person:
        if (_personKey.currentState?.closeSheet() ?? false) return;
        _closePerson();
    }
  }

  /// Tests: what Android's back would do now, without the system.
  @visibleForTesting
  bool debugSystemBack() {
    if (_backLeavesApp) return false;
    _systemBack();
    return true;
  }

  void _closeRead() {
    if (_aside != null && _readFrom == Stage.passing) {
      _aside = null;
      unawaited(_reloadPassing());
      return setState(() => _stage = Stage.passing);
    }
    _aside = null;
    _engine.setView(SkyView.home);
    _lookHome(_engine.focus);
    setState(() {
      _showNow();
      _stage = Stage.home;
      _list = false;
    });
  }


  /// Delete the blessing being read, go home, and turn to the nearest one left. One of the person's
  /// own has its links stopped first; if they cannot be (no internet), nothing is deleted and false
  /// is answered. One passed along was handed over: its links keep working.
  Future<bool> _delete() async {
    final aside = _aside;
    if (aside != null) {
      await _store.delete(aside.id);
      if (!mounted) return true;
      _aside = null;
      _passing = _passing.where((b) => b.id != aside.id).toList();
      if (_readFrom == Stage.passing) {
        setState(() => _stage = Stage.passing);
      } else {
        _engine.setView(SkyView.home);
        _lookHome(_engine.focus);
        setState(() {
          _showNow();
          _stage = Stage.home;
        });
      }
      return true;
    }
    if (_blessings.isEmpty) return true;
    final i = _engine.focus.clamp(0, _blessings.length - 1);
    final gone = _blessings[i];
    final links = _links;
    if (links != null && (await links.liveOf(gone.id)).isNotEmpty) {
      if (await links.stopAllOf(gone.id) != StopResult.stopped) return false;
    }
    await _store.delete(gone.id);
    if (!mounted) return true;
    final list = [..._blessings]..removeAt(i);
    var next = 0;
    if (list.isNotEmpty) {
      // the one given nearest in time: the next older or the next newer
      final older = i - 1, newer = i;
      if (older < 0) {
        next = newer;
      } else if (newer >= list.length) {
        next = older;
      } else {
        final dOld = gone.utc.difference(list[older].utc).abs(), dNew = list[newer].utc.difference(gone.utc).abs();
        next = dNew < dOld ? newer : older;
      }
    }
    _setBlessings(list, focus: next);
    _engine.setView(SkyView.home);
    _lookHome(next);
    setState(() {
      _showNow();
      _stage = Stage.home;
      _list = false;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final mq = MediaQuery.of(context);
    final top = math.max(62.0, mq.viewPadding.top);
    const inTime = Duration(milliseconds: 700), outTime = Duration(milliseconds: 550), delay = Duration(milliseconds: 100);
    const listTime = Duration(milliseconds: 350);
    // locked: no blessing is handed to any page, even one faded out
    final reading = _locked ? null : (_aside ?? (_blessings.isEmpty ? null : _blessings[_engine.focus.clamp(0, _blessings.length - 1)]));
    if (_inbox.isNotEmpty) _scheduleArrival();
    if (_shortcut != null) _scheduleShortcut();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHead());
    return PopScope(
      canPop: _backLeavesApp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _systemBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBars,
      child: ColoredBox(
        color: p.ground,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<SkyAssets>(
                future: _assets,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('${snap.error}', style: sans(13, 18, p.ink3)));
                  }
                  if (!snap.hasData) return const SizedBox.expand();
                  return SkyWidget(
                    key: const Key('sky'),
                    engine: _engine,
                    assets: snap.data!,
                    palette: p,
                    line: _line,
                    onTapFocused: _openRead,
                    onStats: widget.showStats ? _fill.add : null,
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-home'),
                on: _stage == Stage.home && _lock.ready && !HomeScreen.debugBare && _onboard == Onboard.none,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: Stack(
                  children: [
                    // scrims keep the words readable over the brightest parts of the sky
                    Positioned(left: 0, right: 0, top: 0, height: 190, child: TopScrim(palette: p)),
                    Positioned(left: 0, right: 0, bottom: 0, height: 392, child: BottomScrim(palette: p)),
                    // an iPad: the caption, the ruler and New blessing keep together in a centred
                    // column (a phone's is the whole width)
                    Positioned(
                      left: Widths.side(mq.size.width, 0, Widths.foot),
                      right: Widths.side(mq.size.width, 0, Widths.foot),
                      bottom: 30,
                      // hidden under a ring arriving, whose own words sit there
                      child: Fade(on: !_list && !(_receiving && _arrival is ArrivalRing), inDuration: listTime, outDuration: listTime, child: _locked ? _lockedFoot(p) : _foot(p)),
                    ),
                    // the list view: the same blessings, by date (not built at all while locked)
                    if (!_locked)
                      Positioned.fill(
                        child: Fade(
                          key: const Key('stage-list'),
                          on: _list,
                          inDuration: listTime,
                          outDuration: listTime,
                          // an iPad: the list keeps a reading measure, centred on the dark ground
                          child: ColoredBox(
                            color: p.ground,
                            child: Measure(
                              max: Widths.reading,
                              child: Timeline(blessings: _blessings, palette: p, now: DateTime.now(), on: _list, onOpen: _openFromList),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 172 + top - 62,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _list ? 1 : 0,
                          duration: listTime,
                          curve: easeOut,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [p.ground, p.ground, p.ground.withValues(alpha: 0)],
                                stops: const [0, .76, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: 24, right: 12, top: top, child: KeyedSubtree(key: _headKey, child: _head(p))),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-read'),
                on: _stage == Stage.read,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: EdgeSwipeBack(
                  enabled: _stage == Stage.read && !_locked,
                  onBack: _closeRead,
                  child: ReadLayer(
                    key: _readKey,
                    palette: p,
                  blessing: reading,
                  placement: placement,
                  on: _stage == Stage.read,
                  onBack: _closeRead,
                  onReview: () => reading == null ? null : _openReview(reading, from: Stage.read),
                  onChanges: () => reading == null ? null : openChanges(reading, from: Stage.read),
                  onDelete: _delete,
                  share: _share,
                  links: _links,
                  onSent: _sent,
                  onYourLinks: _links == null ? null : () => _openLinks(from: Stage.read),
                  liveLinks: _liveLinks,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-review'),
                on: _stage == Stage.review,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: EdgeSwipeBack(
                  enabled: _stage == Stage.review && !_locked,
                  onBack: () => _reviewKey.currentState?.back(),
                  child: ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) => ReviewLayer(
                    key: _reviewKey,
                    palette: p,
                    blessing: _reviewing,
                    // kept open (its words, place and recording) under the changes screen opened from it
                    on: _stage == Stage.review || (_stage == Stage.changes && _changesFrom == Stage.review),
                    player: _player,
                    audioPath: _audioOf(_reviewing),
                    words: _wordsOf(_reviewing),
                    knownTags: _knownTags,
                    onSave: _saveReview,
                    onBack: _closeReview,
                    onFinish: _finishReview,
                    onOwnership: (w) => unawaited(_ownershipChanged(w)),
                    onGiven: () => unawaited(_entryGiven()),
                    people: _locked ? const [] : _family.people,
                    onChanges: () {
                      final b = _reviewing;
                      if (b != null) openChanges(b, from: Stage.review);
                    },
                  ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-changes'),
                on: _stage == Stage.changes,
                inDuration: inTime,
                outDuration: outTime,
                child: EdgeSwipeBack(
                  enabled: _stage == Stage.changes && !_locked,
                  onBack: _closeChanges,
                  child: ChangesLayer(
                  key: _changesKey,
                  palette: p,
                  blessing: _changing,
                  on: _stage == Stage.changes,
                  onSave: _saveChanges,
                  onDone: _closeChanges,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-settings'),
                on: _stage == Stage.settings,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _where == null || _locked
                    ? const SizedBox.shrink()
                    : EdgeSwipeBack(
                        enabled: _stage == Stage.settings,
                        onBack: _closeSettings,
                        child: SettingsLayer(
                        palette: p,
                        lock: _lock,
                        where: _where!,
                        language: _settings?.language,
                        version: _version,
                        onBack: _closeSettings,
                        onLock: (on) => _lock.setChosen(on),
                        onLanguage: _setRecordingLanguage,
                        onUseLocation: () => _where?.useMyLocation(),
                        onSetScreenLock: Phone.android ? () => unawaited(NativeLockApi.openSecurity()) : null,
                        onPhoneCheck: phoneCheck ? _openPhoneCheck : null,
                        passingCount: _passing.length,
                        onPassAlong: _openPassing,
                        onYourLinks: _links == null ? null : () => _openLinks(from: Stage.settings),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-passing'),
                on: _stage == Stage.passing,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _locked
                    ? const SizedBox.shrink()
                    : EdgeSwipeBack(
                        enabled: _stage == Stage.passing,
                        onBack: _closePassing,
                        child: PassAlongLayer(palette: p, blessings: _passing, onBack: _closePassing, onOpen: _openAside),
                      ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-links'),
                on: _stage == Stage.links,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _locked
                    ? const SizedBox.shrink()
                    : EdgeSwipeBack(
                        enabled: _stage == Stage.links,
                        onBack: _closeLinks,
                        child: YourLinksLayer(key: _linksKey, palette: p, on: _stage == Stage.links, links: _links, onBack: _closeLinks),
                      ),
              ),
            ),
            // Manage family, and adding or changing a family member: never built while locked
            Positioned.fill(
              child: Fade(
                key: const Key('stage-family'),
                on: _stage == Stage.family,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _locked
                    ? const SizedBox.shrink()
                    : EdgeSwipeBack(
                        enabled: _stage == Stage.family,
                        onBack: _closeFamily,
                        child: FamilyLayer(
                          palette: p,
                          people: _family.people,
                          countLine: (x) => countLine(_family.on(x.id)),
                          onBack: _closeFamily,
                          onOpen: (x) => _openPerson(x, from: Stage.family),
                          onAdd: () => _openPerson(null, from: Stage.family),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-person'),
                on: _stage == Stage.person,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _locked
                    ? const SizedBox.shrink()
                    : EdgeSwipeBack(
                        enabled: _stage == Stage.person,
                        onBack: _closePerson,
                        child: PersonLayer(
                          key: _personKey,
                          palette: p,
                          on: _stage == Stage.person,
                          person: _editing,
                          countLine: _editing == null ? '' : countLine(_family.on(_editing!.id)),
                          blessings: _editing == null ? 0 : _family.on(_editing!.id).length,
                          onBack: _closePerson,
                          onSave: (name, born) => unawaited(_savePerson(name, born)),
                          onRemove: _removePerson,
                          keptBy: _editing == null ? '' : suggestedKeptBy(_family.on(_editing!.id), remembered: _settings?.keptBy),
                          onMakeRing: _links == null || _editing == null ? null : _makeRing,
                          onShareRing: (url, title) {
                            // an iPad's popover: from the middle, not a page left behind
                            NativeShareApi.origin = null;
                            return _share.link(url, title);
                          },
                          onRingSent: (keptBy) => unawaited(_ringSent(keptBy)),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-record'),
                on: _stage == Stage.record,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: RecordLayer(
                  palette: p,
                  session: _session,
                  onBegin: _begin,
                  onClose: _closeRecord,
                  onDiscardEarly: _discardEarly,
                  onAmen: _amen,
                  onLanguage: _setLanguage,
                  onOpenSettings: _recorder.openSettings,
                  onAskAgain: () => _session.askAgain(),
                  active: _stage == Stage.record,
                  practice: _session.practice,
                  // whose it will be, once there are family members; nothing of them while locked
                  whose: _locked || _family.people.isEmpty || _session.practice || _session.draft == null ? null : _family.title(_session.draft!.personId),
                  // nothing of the store while locked, and nothing to enter from the practice
                  onEnter: _locked || _session.practice ? null : () => unawaited(_openEntry()),
                ),
              ),
            ),
            Positioned.fill(
              child: Fade(
                key: const Key('stage-after'),
                on: _stage == Stage.after,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) => AfterLayer(
                    palette: p,
                    blessing: _session.draft,
                    words: _wordsOf(_session.draft) ?? _session.wordsState,
                    heard: _session.words.trim().isNotEmpty || (_session.draft?.rawText.trim().isNotEmpty ?? false),
                    audioPath: _session.audioPath,
                    on: _stage == Stage.after,
                    onReview: _reviewNow,
                    onSave: _saveForLater,
                  ),
                ),
              ),
            ),
            ..._firstRunLayers(p),
            // the app was closed while recording: what was kept, told once
            Positioned.fill(
              child: RecoveredSheet(
                palette: p,
                // shown only once unlocked
                on: _recoveredSheet && _stage == Stage.home && !_locked && _lock.ready,
                recovered: _locked ? const [] : _recovered,
                onReview: _reviewRecovered,
                onLater: _laterRecovered,
              ),
            ),
            // a blessing file that arrived: built only once unlocked
            Positioned.fill(
              child: ReceiveSheet(
                palette: p,
                on: _receiving && !_locked && _lock.ready && _arrival is! ArrivalRing,
                arrival: _locked || _arrival is ArrivalRing ? null : _arrival,
                onKeep: _keepArrival,
                onNotNow: _dismissArrival,
              ),
            ),
            // a family member's ring handed to this phone: read first, then Keep them; built only
            // once unlocked
            if (_receiving && !_locked && _lock.ready && _arrival is ArrivalRing)
              Positioned.fill(
                child: RingArrivalLayer(
                  palette: p,
                  arrival: _arrival as ArrivalRing,
                  more: _family.on('').isNotEmpty,
                  busy: _ringBusy,
                  onKeep: _keepArrival,
                  onNotNow: _dismissArrival,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 120,
              child: ReceiveNotice(palette: p, on: _noticeOn && !_locked, text: _noticeText),
            ),
            if (widget.showStats)
              Positioned(
                right: 12,
                top: top + 52,
                child: SkyStatsOverlay(fill: _fill),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _head(Palette p) {
    if (_locked) {
      return Column(
        key: const Key('locked-head'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.forMe, style: serif(34, 38, p.ink, tracking: -.012)),
          const SizedBox(height: 2),
          Text(Strings.locked, key: const Key('locked-line'), style: sans(13, 18, p.ink2, tracking: .005)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // whose sky this is, and the way to the others; it never grows past the room beside the
              // buttons, and a long name ends in an ellipsis
              Transform.translate(
                offset: const Offset(-6, -3),
                // (its words stop growing at 1.6×; its menu follows the person's own size)
                child: SkySwitch(
                  key: const Key('sky-switch'),
                  palette: p,
                  label: _family.title(_ring),
                  menu: () => _family.menu(_ring),
                  onOpening: _openingSkyMenu,
                  onChosen: (code) => unawaited(_skyMenuChosen(code)),
                  onClosed: () => _skyMenuOpen = false,
                ),
              ),
              const SizedBox(height: 4),
              // one line, so the list below never runs into it; at large text sizes it shrinks to fit
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(countLine(_blessings), key: const Key('count'), style: sans(13, 18, p.ink2, tracking: .005)),
              ),
              // the person's own sky, with blessings that came with a ring handed over
              if (_ring.isEmpty && keptByNames(_blessings).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(Strings.keptForYouBy(keptByNames(_blessings)), key: const Key('kept-for-you'), style: sans(13, 18, p.ink3, tracking: .005)),
                  ),
                ),
              if (_drafts > 0 && !_list)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ReviewBadge(key: const Key('to-review'), palette: p, count: _drafts, onTap: _reviewOldestDraft),
                ),
            ],
          ),
        ),
        // settings ("more") and the list toggle beside it, in one group of liquid glass
        Transform.translate(
          offset: const Offset(0, -3),
          child: HeadButtons(
            palette: p,
            onMore: _openSettings,
            list: _blessings.isNotEmpty || _list ? _list : null,
            onList: () => setState(() => _list = !_list),
          ),
        ),
      ],
    );
  }

  Widget _foot(Palette p) {
    if (_blessings.isEmpty) return _firstRun(p);
    final empty = _blessings.isEmpty;
    final b = empty ? null : _blessings[_shown.clamp(0, _blessings.length - 1)];
    final f = _engine.focus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // the caption: the blessing in focus
        if (b != null)
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedOpacity(
                    opacity: _swapping ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    curve: easeOut,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.longDate, key: const Key('cap-date'), style: sans(13, 18, p.ink2, tracking: .005)),
                        const SizedBox(height: 6),
                        BalancedText(b.shownTitle, textKey: const Key('cap-title'), style: serif(30, 34, p.ink, tracking: -.012)),
                        if (b.from.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(Strings.from(b.from), key: const Key('cap-from'), style: serif(18, 26, p.light, italic: true)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Transform.translate(
                  offset: const Offset(0, 4),
                  child: IconBtn(
                    key: const Key('read'),
                    icon: Glyph.forward,
                    color: p.ink,
                    palette: p,
                    filled: true,
                    semantics: Strings.readBlessing,
                    onTap: _openRead,
                  ),
                ),
              ],
            ),
          ),
        // the ruler of months
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, -6),
                child: IconBtn(
                  key: const Key('older'),
                  icon: Glyph.older,
                  color: p.ink2,
                  palette: p,
                  semantics: Strings.earlier,
                  onTap: !empty && f > 0 ? () => _engine.setFocus(f - 1) : null,
                ),
              ),
              Expanded(
                child: Ruler(key: const Key('ruler'), blessings: _blessings, focus: f, palette: p, now: DateTime.now(), onPick: _pick, begins: _begins),
              ),
              Transform.translate(
                offset: const Offset(0, -6),
                child: IconBtn(
                  key: const Key('newer'),
                  icon: Glyph.newer,
                  color: p.ink2,
                  palette: p,
                  semantics: Strings.later,
                  onTap: !empty && f < _blessings.length - 1 ? () => _engine.setFocus(f + 1) : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        NewBlessingButton(key: const Key('new'), palette: p, onTap: _openRecord),
      ],
    );
  }

  /// Locked: "Unlock" centred low, and New blessing where it always is (it works while locked).
  Widget _lockedFoot(Palette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        UnlockButton(key: const Key('unlock'), palette: p, onTap: _askToUnlock),
        const SizedBox(height: 72),
        NewBlessingButton(key: const Key('new'), palette: p, onTap: _openRecord),
      ],
    );
  }

  /// No blessings yet: one line where the caption would be, and New blessing.
  Widget _firstRun(Palette p) => EmptyRingFoot(
        palette: p,
        // a family member's empty ring names them
        line: _ring.isEmpty || _family.person(_ring) == null ? Strings.firstRun : Strings.emptyRing(_family.person(_ring)!.name),
        onNew: _openRecord,
      );
}

/// An empty ring's foot: its line where the caption would be, and New blessing under it. The line
/// keeps to the lower part of the screen at every text size (drawn smaller when it would not), so it
/// never reaches the count line, the capsule or the status bar.
class EmptyRingFoot extends StatelessWidget {
  const EmptyRingFoot({super.key, required this.palette, required this.line, required this.onNew});
  final Palette palette;
  final String line;
  final VoidCallback onNew;

  /// The most of the screen's height the line may take.
  static const share = .22;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: BalancedText(
            line,
            textKey: const Key('first-run'),
            style: serif(26, 32, p.ink, tracking: -.01),
            textAlign: TextAlign.center,
            maxHeight: MediaQuery.sizeOf(context).height * share,
          ),
        ),
        const SizedBox(height: 36),
        NewBlessingButton(key: const Key('new'), palette: p, onTap: onNew),
      ],
    );
  }
}

/// "• 2 to review": a quiet gold pill under the count line while drafts wait.
class ReviewBadge extends StatefulWidget {
  const ReviewBadge({super.key, required this.palette, required this.count, required this.onTap});
  final Palette palette;
  final int count;
  final VoidCallback onTap;

  @override
  State<ReviewBadge> createState() => _ReviewBadgeState();
}

class _ReviewBadgeState extends State<ReviewBadge> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: Strings.toReviewLabel(widget.count),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        // a 44-point target round a 28-point pill
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 28,
            padding: const EdgeInsets.only(left: 10, right: 12),
            decoration: BoxDecoration(
              color: p.light.withValues(alpha: _down ? .20 : .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: p.light)),
                const SizedBox(width: 7),
                Text(Strings.toReview(widget.count), key: const Key('to-review-text'), style: sans(13, 18, p.light, weight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Unlock": a quiet pill with a small padlock, on the locked sky.
class UnlockButton extends StatefulWidget {
  const UnlockButton({super.key, required this.palette, required this.onTap});
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<UnlockButton> createState() => _UnlockButtonState();
}

class _UnlockButtonState extends State<UnlockButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: Strings.unlock,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          padding: const EdgeInsets.only(left: 16, right: 22),
          decoration: BoxDecoration(
            color: p.ink.withValues(alpha: _down ? .15 : .09),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 18, height: 18, child: GlyphIcon(Glyph.lock, color: p.light)),
              const SizedBox(width: 9),
              Text(Strings.unlock, key: const Key('unlock-text'), style: sans(15, 20, p.ink, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pill that starts a recording.
class NewBlessingButton extends StatefulWidget {
  const NewBlessingButton({super.key, required this.palette, required this.onTap});
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<NewBlessingButton> createState() => _NewBlessingButtonState();
}

class _NewBlessingButtonState extends State<NewBlessingButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: Strings.newBlessing,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 14, right: 20, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: p.ink.withValues(alpha: _down ? .15 : .09),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.ink.withValues(alpha: .55), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.light),
                ),
              ),
              const SizedBox(width: 10),
              // at the largest text it stops growing at 1.6×, as the capsule does, so it stays one line
              // inside its pill on the narrowest phone
              Flexible(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.6,
                  child: Text(Strings.newBlessing,
                      key: const Key('new-text'), style: sans(15, 20, p.ink, weight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
