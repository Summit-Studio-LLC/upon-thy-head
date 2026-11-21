import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart';

import '../data/blessing.dart';
import '../not_yet.dart';
import '../people/person.dart';
import '../people/whose_choice.dart';
import '../polish/polish.dart';
import '../record/model_offer.dart';
import '../record/session.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/measure.dart';
import '../widgets/sheet.dart';
import 'date_sheet.dart';
import 'player.dart';
import 'tags.dart';

/// Reviewing a blessing: hear the recording, put right the words the phone misheard, and fill
/// in the title, who gave it, who it was for, and its tags. One page over the dimmed sky, the
/// blessing's light near the top as on the reading page (SkyView.review).
///
/// Opened by "Review now" after Amen, by Review on a draft's reading page, and by Edit on a
/// finished one. Everything typed goes into [blessing] at once and is saved a moment later
/// ([onSave]), so nothing is lost if the app is closed mid-review.
class ReviewLayer extends StatefulWidget {
  const ReviewLayer({
    super.key,
    required this.palette,
    required this.blessing,
    required this.on,
    required this.player,
    required this.onSave,
    required this.onBack,
    required this.onFinish,
    this.onChanges,
    this.onOwnership,
    this.people = const [],
    this.audioPath,
    this.words,
    this.knownTags = const [],
    this.onGiven,
  });

  /// An entered blessing's date was set or changed (already saved): its light takes its place.
  final VoidCallback? onGiven;

  final Palette palette;
  final Blessing? blessing;
  final bool on;
  final Player player;

  /// The recording's file, when there is one on the phone; null hides the listen bar.
  final String? audioPath;

  /// Where the words are, when this blessing was just recorded; null when it was not.
  final WordsState? words;

  /// Tags used on any blessing, most used first; those not on this one are offered.
  final List<String> knownTags;

  /// Write [blessing] to the store as it now is.
  final Future<void> Function() onSave;

  /// The back chevron: everything typed is kept (and saved first); a draft stays a draft.
  final VoidCallback onBack;

  /// Done (after "Finish", when a recording would be erased): saved, and no longer a draft.
  final VoidCallback onFinish;

  /// The changes screen, for the polish made to the words.
  final VoidCallback? onChanges;

  /// "For me" or "Passing it along" changed (already saved): the blessing joins or leaves the sky.
  final ValueChanged<Whose>? onOwnership;

  /// The family members kept here: with any, "Whose blessing" is a row of their names
  /// (people/whose_choice.dart); with none, For me | Passing it along as before.
  final List<Person> people;

  /// How long typing rests before it is saved.
  static const saveAfter = Duration(milliseconds: 400);

  @override
  State<ReviewLayer> createState() => ReviewLayerState();
}

class ReviewLayerState extends State<ReviewLayer> with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _title = TextEditingController(),
      _from = TextEditingController(),
      _for = TextEditingController(),
      _tag = TextEditingController(),
      _words = TextEditingController();
  final FocusNode _titleFocus = FocusNode(),
      _fromFocus = FocusNode(),
      _forFocus = FocusNode(),
      _tagFocus = FocusNode(),
      _wordsFocus = FocusNode();
  List<String> _tags = [];
  bool _finishing = false, _scrolled = false, _loading = false, _dating = false;
  final GlobalKey<DateSheetState> _dateKey = GlobalKey();
  Timer? _saveTimer;
  Future<void>? _saving;

  /// Something typed has not been written to the store yet.
  bool _dirty = false;
  String? _id;

  /// The words as they were when "Polish the words" found nothing; "Nothing to polish." shows
  /// until they change.
  String? _nothingFor;

  Blessing? get _b => widget.blessing;

  /// The words are still being written from the recording.
  bool get _writing => widget.words == WordsState.writing || widget.words == WordsState.none;

  bool get _hasAudio => widget.audioPath != null;

  /// The listen bar is pinned above the keyboard while the words are being typed.
  bool get _pinned => _hasAudio && _wordsFocus.hasFocus;

  /// Entered from a written copy: the page starts with "Given", and its words are never polished.
  bool get _entered => _b?.entered ?? false;

  /// Done waits for a date (at least a year) and some words, on an entered blessing.
  bool get _canFinish => !_entered || (_b!.placed && _words.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      final s = _scroll.hasClients && _scroll.offset > 120;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
    _title.addListener(() => _edited(() => _b!.title = _title.text.trim().isEmpty ? Strings.untitled : _title.text.trim()));
    _from.addListener(() => _edited(() => _b!.from = _from.text.trim()));
    _for.addListener(() => _edited(() => _b!.recipient = _for.text.trim()));
    _words.addListener(() {
      // a correction by hand: the changes polish made keep up with it (those whose words were
      // edited are dropped); the row's count follows
      if (!_writing && !_loading && _b != null && _b!.rawText != _words.text) {
        _edited(() => Polish.correct(_b!, _words.text));
        setState(() {});
      }
    });
    _tag.addListener(() {
      // a comma ends a tag, as return does
      if (!_loading && _tag.text.contains(',')) {
        _addTag();
      } else {
        setState(() {});
      }
    });
    for (final f in [_wordsFocus, _tagFocus]) {
      f.addListener(() => setState(() {}));
    }
    if (widget.on) _open();
  }

  @override
  void didUpdateWidget(ReviewLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (widget.on && (!old.on || widget.blessing?.id != _id)) _open();
    if (!widget.on && old.on) _close();
    if (widget.on && old.audioPath != widget.audioPath) _loadAudio();
    // the words have arrived: put them in the box, unless something is already there
    if (widget.on && old.words == WordsState.writing && widget.words != WordsState.writing && _b != null) {
      if (_words.text.trim().isEmpty) _setQuietly(_words, _b!.rawText);
    }
  }

  /// Words written late (tried again at launch or as the page opened) go into the empty box.
  void wordsArrived() {
    final b = _b;
    if (b == null || !widget.on || _words.text.trim().isNotEmpty) return;
    _setQuietly(_words, b.rawText);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // leaving the app: save what is typed now. Listening carries on while the phone is locked or
    // the app is in the background (ios/Runner/Playback.swift); a phone call still stops it.
    if (widget.on && state != AppLifecycleState.resumed) flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    for (final c in [_scroll, _title, _from, _for, _tag, _words]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _fromFocus, _forFocus, _tagFocus, _wordsFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  /// Fill the page from the blessing, without counting it as typing.
  void _open() {
    final b = _b;
    if (b == null) return;
    _id = b.id;
    _loading = true;
    _title.text = Strings.isUntitled(b.title) ? '' : b.title;
    _from.text = b.from;
    _for.text = b.recipient;
    _forFilled = null;
    _tag.text = '';
    _words.text = _writing ? '' : b.rawText;
    _tags = [...b.tags];
    _nothingFor = null;
    _loading = false;
    _finishing = false;
    _dating = false;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadAudio();
  }

  void _setQuietly(TextEditingController c, String text) {
    _loading = true;
    c.text = text;
    _loading = false;
  }

  Future<void> _loadAudio() async {
    final path = widget.audioPath;
    if (path == null) {
      await widget.player.unload();
    } else if (widget.on) {
      await widget.player.load(path);
    }
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.player.unload();
    _finishing = false;
  }

  /// The "For" name as filled in from the family member chosen, while the field still holds just it
  /// (forAfterWhose).
  String? _forFilled;

  /// "For me", a family member, or "Passing it along": saved at once, and the sky follows. An empty
  /// "For" takes the family member's name.
  Future<void> _setOwnership(Whose w) async {
    final b = _b;
    if (b == null || Whose.ofBlessing(b) == w || !widget.on) return;
    final f = forAfterWhose(text: _for.text, filled: _forFilled, to: w, people: widget.people);
    _forFilled = f.filled;
    if (f.text != _for.text) {
      _setQuietly(_for, f.text);
      b.recipient = f.text.trim();
    }
    setState(() => w.apply(b));
    _dirty = true;
    await flush();
    widget.onOwnership?.call(w);
  }

  void _edited(void Function() write) {
    if (_loading || _b == null || !widget.on) return;
    write();
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(ReviewLayer.saveAfter, flush);
  }

  /// Save now whatever is waiting to be saved (and wait for a save already under way).
  Future<void> flush() async {
    _saveTimer?.cancel();
    final before = _saving;
    if (before != null) await before;
    if (!_dirty) return;
    _dirty = false;
    // once polish was asked for, the rules look again at corrected words; anything new is kept
    final b = _b;
    if (b != null && Polish.refresh(b) && mounted) setState(() {});
    await (_saving = widget.onSave());
  }

  /// "Polish the words": the changes found open on the changes screen; or, if there are none,
  /// "Nothing to polish." in the action's place.
  Future<void> _polish() async {
    final b = _b;
    if (b == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Polish.run(b);
    _dirty = true;
    await flush();
    if (!mounted) return;
    if (b.changes.isEmpty) {
      setState(() => _nothingFor = b.rawText);
    } else {
      setState(() {});
      widget.onChanges?.call();
    }
  }

  void _addTag([String? typed]) {
    final next = TagRules.add(_tags, typed ?? _tag.text);
    _tag.clear();
    setState(() => _tags = next);
    _edited(() => _b!.tags = [...next]);
  }

  void _removeTag(String t) {
    final next = TagRules.remove(_tags, t);
    setState(() => _tags = next);
    _edited(() => _b!.tags = [...next]);
  }

  /// The back chevron (and the edge swipe, and VoiceOver's go back): everything typed is kept, and
  /// it stays a draft.
  /// Android's back: the finish sheet goes, if it is up. True when it went.
  bool closeSheet() {
    if (_dating) {
      setState(() => _dating = false);
      return true;
    }
    if (!_finishing) return false;
    setState(() => _finishing = false);
    return true;
  }

  /// "Given": the date sheet, at the date chosen, or today.
  void openDate() {
    final b = _b;
    if (b == null || !_entered) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final at = b.placed ? b.local : DateTime.now();
    final GivenChoice c = (precision: b.placed ? b.precision : DatePrecision.day, year: at.year, month: at.month, day: at.day);
    _dateKey.currentState?.reset(c);
    setState(() => _dating = true);
  }

  Future<void> _dateChosen(GivenChoice c) async {
    final b = _b;
    setState(() => _dating = false);
    if (b == null) return;
    setGiven(b, c.precision, c.year, c.month, c.day);
    _dirty = true;
    await flush();
    if (mounted) setState(() {});
    widget.onGiven?.call();
  }

  /// The Paste chip: the words copied, put in where the cursor is (or as the words, when there are
  /// none). The clipboard is read only here, when it is pressed.
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final v = _words.value;
    final sel = v.selection;
    final at = sel.isValid ? sel : TextSelection.collapsed(offset: v.text.length);
    final next = v.text.replaceRange(at.start, at.end, text);
    _words.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at.start + text.length));
    setState(() {});
  }

  Future<void> back() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await flush();
    widget.onBack();
  }

  Future<void> _done() async {
    if (!_canFinish) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await flush();
    final b = _b;
    if (b == null) return;
    if (b.draft && _hasAudio) {
      setState(() => _finishing = true);
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final b = _b;
    final mq = MediaQuery.of(context);
    final dy = math.max(62.0, mq.viewPadding.top) - 62;
    final keyboard = mq.viewInsets.bottom;
    final pinned = _pinned && keyboard > 0;
    // at the largest text sizes on a narrow phone the bar's time goes under its line, and the bar grows to hold it
    final barHeight = 56.0 + (ListenBar.stackedTimeHeight(context, p, mq.size.width - 2 * Widths.side(mq.size.width, 16, Widths.reading)) ?? 0);
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final spacer = 232 + dy;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: keyboard + (pinned ? barHeight : 0),
              child: SingleChildScrollView(
                key: const Key('review-scroll'),
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: spacer),
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: math.max(0, h - spacer - keyboard + 16)),
                      // behind the date sheet, out of a screen reader's reach (one Done at a time)
                      child: ExcludeSemantics(excluding: _dating, child: _page(p, b)),
                    ),
                  ],
                ),
              ),
            ),
            // the top darkens under the status bar and the buttons, and goes solid once the page is under them
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 124 + dy,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _scrolled
                          ? [p.ground, p.ground, p.ground.withValues(alpha: 0)]
                          : [p.ground.withValues(alpha: .7), p.ground.withValues(alpha: .35), p.ground.withValues(alpha: 0)],
                      stops: _scrolled ? const [0, .8, 1] : const [0, .45, .85],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              right: 12,
              top: 54 + dy,
              // like an iOS navigation bar, the top bar grows only a little with the text size
              child: ExcludeSemantics(
                excluding: _dating,
                child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconBtn(
                      key: const Key('review-back'),
                      icon: Glyph.older,
                      color: p.ink,
                      palette: p,
                      semantics: Strings.backFromReview,
                      onTap: back,
                    ),
                    LightTextBtn(
                      key: const Key('review-done'),
                      label: Strings.done,
                      palette: p,
                      onTap: _done,
                      enabled: _canFinish,
                      disabledHint: Strings.doneNeedsDateAndWords,
                    ),
                  ],
                ),
              ),
              ),
            ),
            if (pinned)
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                height: barHeight,
                child: DecoratedBox(
                  key: const Key('listen-pinned'),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(top: BorderSide(color: p.ink.withValues(alpha: .08))),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: Widths.side(MediaQuery.sizeOf(context).width, 16, Widths.reading)),
                    child: ListenBar(palette: p, player: widget.player, keys: 'pinned'),
                  ),
                ),
              ),
            // an entered blessing's date
            Positioned.fill(
              child: Sheet(
                palette: p,
                on: _dating,
                barrier: true,
                onDismiss: () => setState(() => _dating = false),
                label: Strings.whenGiven,
                panelKey: const Key('date-panel'),
                child: DateSheet(
                  key: _dateKey,
                  palette: p,
                  initial: (precision: DatePrecision.day, year: DateTime.now().year, month: DateTime.now().month, day: DateTime.now().day),
                  onDone: _dateChosen,
                ),
              ),
            ),
            Positioned.fill(
              child: Sheet(
                palette: p,
                on: _finishing,
                barrier: true,
                onDismiss: () => setState(() => _finishing = false),
                label: Strings.finishTitle,
                panelKey: const Key('finish-sheet'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(Strings.finishTitle, style: serif(22, 28, p.ink)),
                    const SizedBox(height: 6),
                    // the audio rule: a recording whose words are still to come is kept (recovery.dart)
                    Text(widget.words == WordsState.later ? Strings.finishBodyLater : Strings.finishBody, style: sans(15, 22, p.ink2)),
                    const SizedBox(height: 20),
                    SheetButtons(
                      palette: p,
                      left: PillBtn(
                        key: const Key('finish-not-yet'),
                        label: Strings.notYet,
                        palette: p,
                        kind: PillKind.tonal,
                        height: 48,
                        fontSize: 16,
                        onTap: () => setState(() => _finishing = false),
                      ),
                      right: PillBtn(
                        key: const Key('finish-confirm'),
                        label: Strings.finish,
                        palette: p,
                        kind: PillKind.primary,
                        height: 48,
                        fontSize: 16,
                        onTap: () {
                          setState(() => _finishing = false);
                          widget.player.unload();
                          widget.onFinish();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _page(Palette p, Blessing? b) {
    if (b == null) return ColoredBox(color: p.ground);
    final wordStyle = serif(19, 30, p.ink).copyWith(fontFeatures: const [FontFeature.oldstyleFigures()]);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(left: 0, right: 0, bottom: -1000, height: 1000, child: ColoredBox(color: p.ground)),
        // the sky fades into the page above its first line
        Positioned(
          left: 0,
          right: 0,
          top: -76,
          height: 76,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.ground.withValues(alpha: 0), p.ground.withValues(alpha: .55), p.ground],
                  stops: const [0, .5, 1],
                ),
              ),
            ),
          ),
        ),
        Container(
          color: p.ground,
          // an iPad: the page keeps a reading measure, centred (a phone keeps its 28)
          padding: EdgeInsets.fromLTRB(Widths.side(MediaQuery.sizeOf(context).width, 28, Widths.reading), 0, Widths.side(MediaQuery.sizeOf(context).width, 28, Widths.reading), 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // an entered blessing's date is its first row instead
              if (!b.entered) ...[
                Text(b.longDate, key: const Key('review-date'), style: sans(13, 18, p.ink2, tracking: .005)),
                const SizedBox(height: 6),
              ],
              _field(
                key: const Key('review-title'),
                label: Strings.titleLabel,
                controller: _title,
                focus: _titleFocus,
                style: serif(34, 38, p.ink, tracking: -.012),
                placeholder: Strings.titlePlaceholder,
                placeholderColor: p.ink3,
                capitalization: TextCapitalization.sentences,
                action: TextInputAction.next,
                onSubmitted: () => _fromFocus.requestFocus(),
              ),
              const SizedBox(height: 18),
              _rule(p),
              if (b.entered) ...[_givenRow(p, b), _rule(p)],
              _row(p, Strings.fromField, Strings.fromLabel, _from, _fromFocus, const Key('review-from'), next: _forFocus),
              _rule(p),
              _row(p, Strings.forField, Strings.forLabel, _for, _forFocus, const Key('review-for'), next: _tagFocus),
              _rule(p),
              if (widget.onOwnership != null) ...[
                const SizedBox(height: 14),
                if (widget.people.isEmpty)
                  OwnershipChoice(
                    palette: p,
                    value: b.ownership,
                    onChanged: (o) => _setOwnership(o == Ownership.passingOn ? Whose.passing : Whose.me),
                  )
                else
                  WhoseChoice(palette: p, people: widget.people, value: Whose.ofBlessing(b), onChanged: _setOwnership),
                const SizedBox(height: 14),
                _rule(p),
              ],
              const SizedBox(height: 14),
              _tagsBlock(p),
              const SizedBox(height: 22),
              if (_hasAudio) ...[
                // stays in its place (invisible) while pinned above the keyboard, so nothing jumps
                Builder(
                  builder: (context) {
                    final away = _pinned && MediaQuery.viewInsetsOf(context).bottom > 0;
                    return IgnorePointer(
                      ignoring: away,
                      child: ExcludeSemantics(
                        excluding: away,
                        child: Opacity(
                          opacity: away ? 0 : 1,
                          child: ListenBar(key: const Key('listen'), palette: p, player: widget.player),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
              ],
              _wordsBlock(p, b, wordStyle),
            ],
          ),
        ),
      ],
    );
  }

  /// "Given  When was it given?" (or its date), and a calendar: opens the date sheet.
  Widget _givenRow(Palette p, Blessing b) {
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 28;
    final value = b.placed ? b.longDate : Strings.whenGiven;
    final label = Text(Strings.givenField, style: sans(15, 20, p.ink2));
    final shown = Text(value, key: const Key('review-given'), style: sans(17, 22, b.placed ? p.ink : p.light));
    final icon = SizedBox(width: 22, height: 22, child: GlyphIcon(Glyph.calendar, color: p.light));
    return Semantics(
      button: true,
      label: Strings.givenField,
      value: value,
      hint: Strings.givenHint,
      excludeSemantics: true,
      onTap: openDate,
      child: GestureDetector(
        key: const Key('review-given-row'),
        behavior: HitTestBehavior.opaque,
        onTap: openDate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: stacked
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    label,
                    const SizedBox(height: 4),
                    Row(children: [Expanded(child: shown), const SizedBox(width: 8), icon]),
                  ])
                : Row(children: [
                    SizedBox(width: 64 * math.max(1, MediaQuery.textScalerOf(context).scale(15) / 15), child: label),
                    Expanded(child: shown),
                    const SizedBox(width: 8),
                    icon,
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _rule(Palette p) => Container(height: 1, color: p.ink.withValues(alpha: .08));

  Widget _field({
    required Key key,
    required String label,
    required TextEditingController controller,
    required FocusNode focus,
    required TextStyle style,
    required String placeholder,
    required Color placeholderColor,
    required TextCapitalization capitalization,
    required TextInputAction action,
    VoidCallback? onSubmitted,
    int? maxLines,
    int minLines = 1,
  }) {
    final p = widget.palette;
    final dy = math.max(62.0, MediaQuery.viewPaddingOf(context).top) - 62;
    final field = CupertinoTextField(
          key: key,
          controller: controller,
          focusNode: focus,
          style: style,
          placeholder: placeholder,
          placeholderStyle: style.copyWith(color: placeholderColor),
          cursorColor: p.light,
          keyboardAppearance: Brightness.dark,
          textCapitalization: capitalization,
          textInputAction: action,
          onSubmitted: (_) => onSubmitted?.call(),
          maxLines: maxLines,
          minLines: maxLines == null ? null : minLines,
          padding: EdgeInsets.zero,
          decoration: null,
          scrollPadding: EdgeInsets.fromLTRB(20, 150 + dy, 20, 40),
          // Android's own selection handles and its own copy and paste menu, in the sky's gold; the
          // iPhone keeps iOS's. (Android has no per-app dark keyboard: the keyboard follows the
          // phone's own dark theme, and keyboardAppearance is read only by iOS.)
          selectionControls: Phone.android ? m.materialTextSelectionHandleControls : null,
          contextMenuBuilder: Phone.android
              ? (context, s) => m.AdaptiveTextSelectionToolbar.editableText(editableTextState: s)
              : (context, s) => CupertinoAdaptiveTextSelectionToolbar.editableText(editableTextState: s),
        );
    return MergeSemantics(
      child: Semantics(
        label: label,
        child: Phone.android
            ? m.Theme(
                data: m.ThemeData(
                  brightness: Brightness.dark,
                  textSelectionTheme: m.TextSelectionThemeData(selectionHandleColor: p.light, cursorColor: p.light),
                ),
                child: field,
              )
            : field,
      ),
    );
  }

  /// "From  Dad": a quiet label and a name.
  Widget _row(Palette p, String label, String semantics, TextEditingController c, FocusNode f, Key key, {required FocusNode next}) {
    // beside the name up to about the first accessibility size; above it beyond that
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 28;
    final labelText = ExcludeSemantics(child: Text(label, style: sans(15, 20, p.ink2)));
    final children = <Widget>[
      // the label's column grows with the text, so "From" never runs into the name
      if (stacked) Padding(padding: const EdgeInsets.only(top: 12), child: labelText) else SizedBox(width: 64 * math.max(1, MediaQuery.textScalerOf(context).scale(15) / 15), child: labelText),
      _expandIf(
        !stacked,
        Padding(
          padding: EdgeInsets.only(top: stacked ? 4 : 13, bottom: 13),
          child: _field(
            key: key,
            label: semantics,
            controller: c,
            focus: f,
            style: sans(17, 22, p.ink),
            placeholder: Strings.namePlaceholder,
            placeholderColor: p.ink3,
            capitalization: TextCapitalization.words,
            action: TextInputAction.next,
            onSubmitted: next.requestFocus,
            maxLines: null,
          ),
        ),
      ),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: f.requestFocus,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }

  static Widget _expandIf(bool expand, Widget child) => expand ? Expanded(child: child) : child;

  Widget _tagsBlock(Palette p) {
    final suggestions = TagRules.suggest(widget.knownTags, _tags, _tag.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(Strings.tags, style: sans(15, 20, p.ink2))),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in _tags) _TagChip(key: Key('tag-$t'), label: t, palette: p, onRemove: () => _removeTag(t)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 400),
              child: IntrinsicWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: _field(
                    key: const Key('review-tag'),
                    label: Strings.addTag,
                    controller: _tag,
                    focus: _tagFocus,
                    style: sans(15, 20, p.ink),
                    placeholder: Strings.addTag,
                    placeholderColor: p.ink3,
                    capitalization: TextCapitalization.sentences,
                    // iOS draws Done in its own blue and lets no app tint it; the plain return key fits
                    action: TextInputAction.unspecified,
                    onSubmitted: () {
                      if (_tag.text.trim().isEmpty) {
                        _tagFocus.unfocus();
                      } else {
                        _addTag();
                        _tagFocus.requestFocus();
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            key: const Key('tag-suggestions'),
            spacing: 4,
            runSpacing: 4,
            children: [for (final s in suggestions) _Suggestion(key: Key('suggest-$s'), label: s, palette: p, onTap: () => _addTag(s))],
          ),
        ],
      ],
    );
  }

  Widget _wordsBlock(Palette p, Blessing b, TextStyle wordStyle) {
    if (_writing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          liveRegion: true,
          child: Text(Strings.writingWords, key: const Key('review-writing'), style: serif(19, 30, p.ink3, italic: true)),
        ),
        if (Phone.android) ...[const SizedBox(height: 12), WritingProgress(palette: p, path: widget.audioPath)],
      ]);
    }
    // nothing came from the recording: say so once, above the empty box. A recording whose words
    // this version cannot write on this phone (Android, for now) says so while it waits, typed or not.
    final notice = widget.words == WordsState.later
        ? Strings.wordsLaterHere
        : _hasAudio && b.firstText.trim().isEmpty
            ? (widget.words == WordsState.done ? Strings.noWordsHeardHere : Strings.wordsNotWrittenHere)
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[Text(notice, key: const Key('review-no-words'), style: sans(15, 22, p.ink2)), const SizedBox(height: 14)],
        // Android, waiting for the model: the download, offered here too
        if (Phone.android && widget.words == WordsState.later) ...[ModelOffer(palette: p, showBody: false, compact: true), const SizedBox(height: 18)],
        // Android: words written by the phone's own model, to be checked against the recording
        if (Phone.android && _hasAudio && b.firstText.trim().isNotEmpty) ...[
          Text(Strings.wordsCheck, key: const Key('review-check-words'), style: sans(15, 22, p.ink2)),
          const SizedBox(height: 14),
        ],
        if (b.changes.isNotEmpty) ...[
          ExcludeSemantics(child: Text(Strings.spokenWords, key: const Key('review-spoken-label'), style: sans(15, 20, p.ink2))),
          const SizedBox(height: 10),
        ],
        _field(
          key: const Key('review-words'),
          label: Strings.wordsLabel,
          controller: _words,
          focus: _wordsFocus,
          style: wordStyle,
          placeholder: b.entered ? Strings.typeOrPaste : Strings.typeWords,
          placeholderColor: p.ink3,
          capitalization: TextCapitalization.sentences,
          action: TextInputAction.newline,
          maxLines: null,
          minLines: 4,
        ),
        // entered: a Paste chip while there are no words yet; polish never runs on them
        if (b.entered) ...[
          if (_words.text.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Align(alignment: Alignment.centerLeft, child: _PasteChip(key: const Key('review-paste'), palette: p, onTap: paste)),
            ),
        ] else
          _polishBlock(p, b),
      ],
    );
  }

  /// Under the words: "Polish the words"; "Nothing to polish." when it found nothing; and once
  /// there are changes, "Polished for reading · 4 changes ›" to the changes screen.
  Widget _polishBlock(Palette p, Blessing b) {
    if (b.rawText.trim().isEmpty) return const SizedBox.shrink();
    final Widget child;
    if (b.changes.isNotEmpty) {
      final kept = b.changes.where((c) => c.kept).length;
      child = _PolishedRow(
        key: const Key('review-polished'),
        palette: p,
        label: Strings.polishedForReading,
        detail: Strings.polishedRow(kept, b.changes.length),
        onTap: () => widget.onChanges?.call(),
      );
    } else if (_nothingFor == b.rawText) {
      child = Container(
        height: 44,
        alignment: Alignment.centerLeft,
        child: Semantics(liveRegion: true, child: Text(Strings.nothingToPolish, key: const Key('review-nothing'), style: sans(15, 20, p.ink3))),
      );
    } else {
      child = Transform.translate(
        offset: const Offset(-12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _QuietAction(key: const Key('review-polish'), label: Strings.polishWords, hint: Strings.polishWordsHint, palette: p, onTap: _polish),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 18), child: child);
  }
}

/// "Paste", with a clipboard: puts in the words copied.
class _PasteChip extends StatefulWidget {
  const _PasteChip({super.key, required this.palette, required this.onTap});
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_PasteChip> createState() => _PasteChipState();
}

class _PasteChipState extends State<_PasteChip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: Strings.paste,
      hint: Strings.pasteHint,
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
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .14 : .08), borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.clipboard, color: p.light)),
            const SizedBox(width: 10),
            Flexible(child: Text(Strings.paste, style: sans(17, 22, p.ink))),
          ]),
        ),
      ),
    );
  }
}

/// A quiet word in the light colour, as a button.
class _QuietAction extends StatefulWidget {
  const _QuietAction({super.key, required this.label, required this.palette, required this.onTap, this.hint});
  final String label;
  final String? hint;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_QuietAction> createState() => _QuietActionState();
}

class _QuietActionState extends State<_QuietAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.hint,
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: Text(widget.label, style: sans(15, 20, p.light)),
        ),
      ),
    );
  }
}

/// "Polished for reading · 4 changes ›", between two faint rules, as the From and For rows.
class _PolishedRow extends StatefulWidget {
  const _PolishedRow({super.key, required this.palette, required this.label, required this.detail, required this.onTap});
  final Palette palette;
  final String label, detail;
  final VoidCallback onTap;

  @override
  State<_PolishedRow> createState() => _PolishedRowState();
}

class _PolishedRowState extends State<_PolishedRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final rule = BorderSide(color: p.ink.withValues(alpha: .08));
    return Semantics(
      button: true,
      label: '${widget.label}, ${widget.detail}',
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
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(color: p.ink.withValues(alpha: _down ? .04 : 0), border: Border(top: rule, bottom: rule)),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: widget.label, style: sans(15, 20, p.ink)),
                  TextSpan(text: '  ·  ${widget.detail}', style: sans(15, 20, p.ink2)),
                ]),
                key: const Key('review-polished-text'),
              ),
            ),
            SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.newer, color: p.ink3)),
          ]),
        ),
      ),
    );
  }
}

/// Play or pause, back ten seconds, and elapsed / total, over a thin line in the light colour.
class ListenBar extends StatelessWidget {
  const ListenBar({super.key, required this.palette, required this.player, this.keys = 'listen'});
  final Palette palette;
  final Player player;

  /// Its controls' keys start with this ('listen-play', 'pinned-play', ...).
  final String keys;

  static TextStyle _timeStyle(Palette p) => sans(13, 18, p.ink2).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// How tall the time line is when it has to go under the controls at [width], or null when it fits
  /// beside them. At the largest text sizes on a narrow phone it does not, and the pinned bar above
  /// the keyboard needs to know so it can grow to hold it.
  static double? stackedTimeHeight(BuildContext context, Palette p, double width) {
    // the widest a recording's time gets (under a hundred minutes), so the choice does not flip as it plays
    final tp = TextPainter(
      text: TextSpan(text: '00:00 / 00:00', style: _timeStyle(p)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // play and back are 44 each, then 8 and 12 of space, 4 at the end; the line keeps at least 64
    final fits = width - 44 - 44 - 8 - 12 - 4 - tp.width >= 64;
    if (fits) {
      tp.dispose();
      return null;
    }
    tp.layout(maxWidth: math.max(1.0, width - 4));
    final h = tp.height;
    tp.dispose();
    return h + 6;
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final d = player.duration, at = player.position.clamp(0, d == 0 ? 0 : d).toDouble();
        final f = d > 0 ? at / d : 0.0;
        final time = '${clockTime(at)} / ${clockTime(d)}';
        final controls = <Widget>[
            IconBtn(
              key: Key('$keys-play'),
              icon: player.playing ? Glyph.pause : Glyph.play,
              color: p.ink,
              palette: p,
              semantics: player.playing ? Strings.pause : Strings.play,
              onTap: player.loaded ? player.toggle : null,
            ),
            IconBtn(
              key: Key('$keys-back'),
              icon: Glyph.back10,
              color: p.ink2,
              palette: p,
              semantics: Strings.back10,
              onTap: player.loaded ? player.back : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                // VoiceOver and TalkBack: a slider; a swipe up or down moves ten seconds
                builder: (context, box) => Semantics(
                  slider: true,
                  label: Strings.playbackPosition,
                  value: Strings.elapsed(clockTime(at), clockTime(d)),
                  increasedValue: d > 0 && at < d ? Strings.elapsed(clockTime(math.min(d, at + 10)), clockTime(d)) : null,
                  decreasedValue: d > 0 && at > 0 ? Strings.elapsed(clockTime(math.max(0, at - 10)), clockTime(d)) : null,
                  onIncrease: d > 0 && at < d ? () => player.seek(math.min(d, at + 10)) : null,
                  onDecrease: d > 0 && at > 0 ? () => player.seek(math.max(0, at - 10)) : null,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: d > 0 ? (e) => player.seek((e.localPosition.dx / box.maxWidth).clamp(0.0, 1.0) * d) : null,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 44,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 2,
                            decoration: BoxDecoration(color: p.ink.withValues(alpha: .12), borderRadius: BorderRadius.circular(1)),
                          ),
                          FractionallySizedBox(
                            widthFactor: f,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(color: p.light, borderRadius: BorderRadius.circular(1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ),
        ];
        final timeLabel = Semantics(
          label: Strings.elapsed(clockTime(at), clockTime(d)),
          excludeSemantics: true,
          child: Text(
            time,
            key: Key('$keys-time'),
            style: _timeStyle(p),
          ),
        );
        return LayoutBuilder(
          builder: (context, box) {
            // too big to sit beside the line: the time goes under it, at the right, and may wrap
            if (stackedTimeHeight(context, p, box.maxWidth) != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(children: controls),
                  Padding(padding: const EdgeInsets.only(right: 4, bottom: 6), child: timeLabel),
                ],
              );
            }
            return Row(
              children: [
                ...controls,
                const SizedBox(width: 12),
                timeLabel,
                const SizedBox(width: 4),
              ],
            );
          },
        );
      },
    );
  }
}

/// A tag on the blessing, with × to take it off.
class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.label, required this.palette, required this.onRemove});
  final String label;
  final Palette palette;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(color: p.ink.withValues(alpha: .09), borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, style: sans(15, 20, p.ink))),
          Semantics(
            button: true,
            label: Strings.removeTag(label),
            excludeSemantics: true,
            onTap: onRemove,
            child: GestureDetector(
              key: Key('untag-$label'),
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: SizedBox(width: 16, height: 16, child: GlyphIcon(Glyph.cross, color: p.ink2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tag from another blessing, offered quietly: "+ Healing".
class _Suggestion extends StatelessWidget {
  const _Suggestion({super.key, required this.label, required this.palette, required this.onTap});
  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: Strings.suggestTag(label),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: p.ink.withValues(alpha: .08)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text('+ $label', style: sans(15, 20, p.ink3)),
        ),
      ),
    );
  }
}

/// "For me | Passing it along": whose blessing this is. A blessing passed along has no light in the
/// sky and is not counted; it waits in "To pass along" to be sent.
class OwnershipChoice extends StatelessWidget {
  const OwnershipChoice({super.key, required this.palette, required this.value, required this.onChanged});
  final Palette palette;
  final Ownership value;
  final ValueChanged<Ownership> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget part(Ownership o, String label, Key key) {
      final on = value == o;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          inMutuallyExclusiveGroup: true,
          label: label,
          excludeSemantics: true,
          onTap: () => onChanged(o),
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(o),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(color: on ? p.light : const Color(0x00000000), borderRadius: BorderRadius.circular(20)),
              child: Text(label, textAlign: TextAlign.center, style: sans(15, 20, on ? p.ground : p.ink2, weight: on ? FontWeight.w500 : FontWeight.w400)),
            ),
          ),
        ),
      );
    }

    return Column(key: const Key('review-whose'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Strings.whoFor, style: sans(13, 18, p.ink3)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: p.ink.withValues(alpha: .07), borderRadius: BorderRadius.circular(23)),
        child: Row(children: [
          part(Ownership.forMe, Strings.forMeChoice, const Key('review-for-me')),
          part(Ownership.passingOn, Strings.passingAlong, const Key('review-passing')),
        ]),
      ),
    ]);
  }
}
