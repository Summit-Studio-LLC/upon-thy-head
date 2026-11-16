import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import '../data/audio.dart';
import '../data/blessing.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../lock/lock.dart';
import '../place/where.dart';
import '../polish/changes_screen.dart';
import '../read/read_screen.dart';
import '../record/after_screen.dart';
import '../record/record_screen.dart';
import '../record/recovered_sheet.dart';
import '../record/recovery.dart';
import '../record/session.dart';
import '../record/speech.dart';
import '../record/transcriber.dart';
import '../review/player.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import '../share/share.dart';
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
import '../widgets/fade.dart';
import '../widgets/icons.dart';
import '../widgets/scrims.dart';
import 'ruler.dart';
import 'sky_stats.dart';
import 'timeline.dart';

/// Which screen is over the sky.
enum Stage { home, record, after, read, review, changes, settings }

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
  });

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

  /// The blessings marked "for me", oldest first. Only these are in the sky.
  List<Blessing> _blessings = [];
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

  BlessingStore get _store => widget.store;

  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  late final Recorder _recorder = widget.recorder ?? (_ios ? NativeSpeech.instance : SilentRecorder());
  late final Transcriber _transcriber = widget.transcriber ?? (_ios ? NativeSpeech.instance : const SilentTranscriber());
  late final Player _player = widget.player ?? (_ios ? NativePlayer() : SilentPlayer());
  late final AudioJoiner _joiner = widget.joiner ?? (_ios ? NativeSpeech.instance : const FileJoiner());
  late final AppLock _lock = widget.lock ?? AppLock(api: _ios ? NativeLockApi() : NoLockApi());
  late final Locator _locator = widget.locator ?? (_ios ? NativeLocator() : const NoLocator());
  late final ShareApi _share = widget.share ?? (_ios ? NativeShareApi() : NoShareApi());

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

  /// The remembered language, and where recordings go; read once at start.
  late final Future<(Settings, String)> _speechSetup = Future.wait<Object>([
    Settings.open(),
    defaultAudioDir(),
  ]).then((r) => (r[0] as Settings, r[1] as String));

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
    await _lock.init(settings);
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
  }

  /// Locked: nothing of any blessing stays on screen or in the sky. A recording under way, or its
  /// after-Amen screen, stays; only its own new light is in the sky.
  void _hideBlessings() {
    // the system share sheet goes too, with anything made for it
    unawaited(_share.dismiss());
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
    return _store.list(ownership: Ownership.forMe);
  }

  /// Blessings saved before their words were written (closed just after Amen, or recovered):
  /// the words are written now from the audio, one at a time, as after any Amen.
  Future<void> _writeMissingWords() async {
    final List<Blessing> all;
    try {
      all = await _store.list();
    } catch (e) {
      return debugPrint('words: $e');
    }
    for (final stored in all) {
      final path = _audioOf(stored);
      if (path == null) continue;
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
        state = t.unavailable ? WordsState.unavailable : WordsState.done;
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
      if (t.unavailable) return debugPrint('words: ${b.id} still cannot be written here');
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

  static WordsStatus _statusOf(WordsState s) => switch (s) {
        WordsState.done => WordsStatus.written,
        WordsState.unavailable => WordsStatus.unavailable,
        WordsState.failed => WordsStatus.failed,
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
    placement.apply(_blessings);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from Settings: look again at what is allowed
    if (state == AppLifecycleState.resumed && _stage == Stage.record && !_session.live) {
      _session.checkPermissions(ask: false);
    }
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
    _lock.removeListener(_onLock);
    _lock.api.onActive = null;
    _swapTimer?.cancel();
    _demoTimer?.cancel();
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
    final draft = draftBlessing(DateTime.now(), place: _where?.place ?? saltLakeTemple);
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
    if (identical(s, _session) && !s.live) await s.checkPermissions();
    // then, the first time ever, where blessings are given (after the microphone and speech
    // questions, never once Begin is pressed; Begin never waits for it)
    bool ready() => identical(s, _session) && !s.live && _stage == Stage.record;
    if (ready()) await _where?.onRecordScreen(stillReady: ready);
  }

  /// The pull-down on the Begin screen. The choice is remembered: it is the same setting the
  /// Settings page shows, so someone who records in Spanish on an English phone chooses once.
  void _setLanguage(SpeechLanguage l) {
    _session.setLanguage(l);
    unawaited(_settings?.setLanguage(l.code));
  }

  void _begin() {
    if (!_session.canBegin) {
      _session.checkPermissions();
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

  /// The draft goes at the end of the line, the place for "now", and is the light in focus.
  void _placeDraft(Blessing draft) {
    // locked: only its own light; nothing of any earlier blessing
    final all = _locked ? [draft] : [..._blessings, draft];
    placement.apply(all, now: draft.utc);
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
    _session.discard();
    _engine.show?.stop();
    _setBlessings(_blessings, focus: _homeFocus);
    _engine.setView(SkyView.home);
    _lookHome(_homeFocus);
    setState(() => _stage = Stage.home);
  }

  void _amen() {
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
    final list = [..._blessings, draft]..sort((a, b) => a.utc.compareTo(b.utc));
    final i = list.indexOf(draft);
    _setBlessings(list, focus: i);
    return i;
  }

  /// "Save for later": the new blessing joins the sky and the sky comes back.
  Future<void> _saveForLater() async {
    final i = await _joinSky();
    if (i == null) return;
    _engine.setView(SkyView.home);
    _lookHome(i);
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
    _knownTags = await _store.allTags();
    if (!mounted) return;
    _reviewing = b;
    _reviewFrom = from;
    _engine.setView(SkyView.review);
    _engine.lookAt(_engine.focus);
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
    if (identical(b, _session.draft)) return _session.wordsState;
    final w = _writing[b.id];
    if (w != null) return w;
    return switch (b.wordsStatus) {
      WordsStatus.written => WordsState.done,
      WordsStatus.unavailable => WordsState.unavailable,
      WordsStatus.failed => WordsState.failed,
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

  /// The back chevron: a draft stays a draft; back where the page was opened from.
  void _closeReview() {
    if (_reviewFrom == Stage.read) {
      _engine.setView(SkyView.read);
      _engine.lookAt(_engine.focus);
      setState(() => _stage = Stage.read);
    } else {
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
  Future<void> _finishReview() async {
    final b = _reviewing;
    if (b == null) return;
    b.draft = false;
    await _saveReview();
    await _store.eraseAudio(b);
    if (!mounted) return;
    _engine.setView(SkyView.read);
    _engine.lookAt(_engine.focus);
    setState(() => _stage = Stage.read);
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

  /// How many blessings in the sky are still drafts.
  int get _drafts => _blessings.where((b) => b.draft).length;

  /// The badge: the review page of the oldest draft.
  Future<void> _reviewOldestDraft() async {
    if (_stage != Stage.home || _recoveredSheet) return;
    final i = _blessings.indexWhere((b) => b.draft);
    if (i < 0) return;
    _engine.setFocus(i, instant: true);
    _showNow();
    await _openReview(_blessings[i], from: Stage.home);
  }

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

  // ---- reading ----

  /// Read the blessing in focus: the page rises and the sky frames its light alone.
  void _openRead() {
    if (_blessings.isEmpty || (_stage != Stage.home)) return;
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

  void _closeRead() {
    _engine.setView(SkyView.home);
    _engine.lookAt(_engine.focus);
    setState(() {
      _stage = Stage.home;
      _list = false;
    });
  }


  /// Delete the blessing being read, go home, and turn to the nearest one left.
  Future<void> _delete() async {
    final i = _engine.focus;
    final gone = _blessings[i];
    await _store.delete(gone.id);
    if (!mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final mq = MediaQuery.of(context);
    final top = math.max(62.0, mq.viewPadding.top);
    const inTime = Duration(milliseconds: 700), outTime = Duration(milliseconds: 550), delay = Duration(milliseconds: 100);
    const listTime = Duration(milliseconds: 350);
    // locked: no blessing is handed to any page, even one faded out
    final reading = _blessings.isEmpty || _locked ? null : _blessings[_engine.focus.clamp(0, _blessings.length - 1)];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
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
                on: _stage == Stage.home && _lock.ready && !HomeScreen.debugBare,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: Stack(
                  children: [
                    // scrims keep the words readable over the brightest parts of the sky
                    Positioned(left: 0, right: 0, top: 0, height: 190, child: TopScrim(palette: p)),
                    Positioned(left: 0, right: 0, bottom: 0, height: 392, child: BottomScrim(palette: p)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 30,
                      child: Fade(on: !_list, inDuration: listTime, outDuration: listTime, child: _locked ? _lockedFoot(p) : _foot(p)),
                    ),
                    // the list view: the same blessings, by date (not built at all while locked)
                    if (!_locked)
                      Positioned.fill(
                        child: Fade(
                          key: const Key('stage-list'),
                          on: _list,
                          inDuration: listTime,
                          outDuration: listTime,
                          child: Timeline(blessings: _blessings, palette: p, now: DateTime.now(), on: _list, onOpen: _openFromList),
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
                    Positioned(left: 24, right: 12, top: top, child: _head(p)),
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
                child: ReadLayer(
                  palette: p,
                  blessing: reading,
                  placement: placement,
                  on: _stage == Stage.read,
                  onBack: _closeRead,
                  onReview: () => reading == null ? null : _openReview(reading, from: Stage.read),
                  onChanges: () => reading == null ? null : openChanges(reading, from: Stage.read),
                  onDelete: _delete,
                  share: _share,
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
                    onChanges: () {
                      final b = _reviewing;
                      if (b != null) openChanges(b, from: Stage.review);
                    },
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
            Positioned.fill(
              child: Fade(
                key: const Key('stage-settings'),
                on: _stage == Stage.settings,
                inDuration: inTime,
                outDuration: outTime,
                delay: delay,
                child: _where == null || _locked
                    ? const SizedBox.shrink()
                    : SettingsLayer(
                        palette: p,
                        lock: _lock,
                        where: _where!,
                        language: _settings?.language,
                        version: _version,
                        onBack: _closeSettings,
                        onLock: (on) => _lock.setChosen(on),
                        onLanguage: _setRecordingLanguage,
                        onUseLocation: () => _where?.useMyLocation(),
                        onPhoneCheck: phoneCheck ? _openPhoneCheck : null,
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
                  active: _stage == Stage.record,
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
                    words: _session.wordsState,
                    heard: _session.words.trim().isNotEmpty,
                    on: _stage == Stage.after,
                    onReview: _reviewNow,
                    onSave: _saveForLater,
                  ),
                ),
              ),
            ),
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
            if (widget.showStats)
              Positioned(
                right: 12,
                top: top + 52,
                child: SkyStatsOverlay(fill: _fill),
              ),
          ],
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
              Text(Strings.forMe, style: serif(34, 38, p.ink, tracking: -.012)),
              const SizedBox(height: 2),
              // one line, so the list below never runs into it; at large text sizes it shrinks to fit
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(countLine(_blessings), key: const Key('count'), style: sans(13, 18, p.ink2, tracking: .005)),
              ),
              if (_drafts > 0 && !_list)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ReviewBadge(key: const Key('to-review'), palette: p, count: _drafts, onTap: _reviewOldestDraft),
                ),
            ],
          ),
        ),
        // settings: a quiet "more", in the same weight as the list toggle beside it
        Transform.translate(
          offset: const Offset(0, -2),
          child: IconBtn(
            key: const Key('more'),
            icon: Glyph.more,
            color: p.ink,
            palette: p,
            semantics: Strings.more,
            onTap: _openSettings,
          ),
        ),
        if (_blessings.isNotEmpty || _list)
          Transform.translate(
            offset: const Offset(0, -2),
            child: IconBtn(
              key: const Key('list'),
              icon: _list ? Glyph.sky : Glyph.list,
              color: p.ink,
              palette: p,
              semantics: _list ? Strings.showAsSky : Strings.showAsList,
              onTap: () => setState(() => _list = !_list),
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
                child: Ruler(key: const Key('ruler'), blessings: _blessings, focus: f, palette: p, now: DateTime.now(), onPick: _pick),
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
  Widget _firstRun(Palette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: BalancedText(
            Strings.firstRun,
            textKey: const Key('first-run'),
            style: serif(26, 32, p.ink, tracking: -.01),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 36),
        NewBlessingButton(key: const Key('new'), palette: p, onTap: _openRecord),
      ],
    );
  }
}

/// "Five blessings since June 2024".
String countLine(List<Blessing> blessings) {
  if (blessings.isEmpty) return Strings.countLine(0, DateTime(0));
  final first = blessings.map((b) => b.local).reduce((a, b) => a.isBefore(b) ? a : b);
  return Strings.countLine(blessings.length, first);
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
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          padding: const EdgeInsets.only(left: 14, right: 20),
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
              Text(Strings.newBlessing, style: sans(15, 20, p.ink, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
