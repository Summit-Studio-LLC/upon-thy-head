import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;

import '../data/blessing.dart';
import '../not_yet.dart';
import '../polish/polish.dart';
import '../record/model_offer.dart';
import '../record/session.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/sheet.dart';
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
    this.audioPath,
    this.words,
    this.knownTags = const [],
  });

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
  final ValueChanged<Ownership>? onOwnership;

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
  bool _finishing = false, _scrolled = false, _loading = false;
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
    _tag.text = '';
    _words.text = _writing ? '' : b.rawText;
    _tags = [...b.tags];
    _nothingFor = null;
    _loading = false;
    _finishing = false;
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

  /// "For me" or "Passing it along": saved at once, and the sky follows.
  Future<void> _setOwnership(Ownership o) async {
    final b = _b;
    if (b == null || b.ownership == o || !widget.on) return;
    setState(() => b.ownership = o);
    _dirty = true;
    await flush();
    widget.onOwnership?.call(o);
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
    if (!_finishing) return false;
    setState(() => _finishing = false);
    return true;
  }

  Future<void> back() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await flush();
    widget.onBack();
  }

  Future<void> _done() async {
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
    const barHeight = 56.0;
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
                      child: _page(p, b),
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
                    LightTextBtn(key: const Key('review-done'), label: Strings.done, palette: p, onTap: _done),
                  ],
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListenBar(palette: p, player: widget.player, keys: 'pinned'),
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
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(b.longDate, key: const Key('review-date'), style: sans(13, 18, p.ink2, tracking: .005)),
              const SizedBox(height: 6),
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
              _row(p, Strings.fromField, Strings.fromLabel, _from, _fromFocus, const Key('review-from'), next: _forFocus),
              _rule(p),
              _row(p, Strings.forField, Strings.forLabel, _for, _forFocus, const Key('review-for'), next: _tagFocus),
              _rule(p),
              if (widget.onOwnership != null) ...[
                const SizedBox(height: 14),
                OwnershipChoice(palette: p, value: b.ownership, onChanged: _setOwnership),
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
          placeholder: Strings.typeWords,
          placeholderColor: p.ink3,
          capitalization: TextCapitalization.sentences,
          action: TextInputAction.newline,
          maxLines: null,
          minLines: 4,
        ),
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

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final d = player.duration, at = player.position.clamp(0, d == 0 ? 0 : d).toDouble();
        final f = d > 0 ? at / d : 0.0;
        final time = '${clockTime(at)} / ${clockTime(d)}';
        return Row(
          children: [
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
                builder: (context, box) => GestureDetector(
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
            const SizedBox(width: 12),
            Semantics(
              label: Strings.elapsed(clockTime(at), clockTime(d)),
              excludeSemantics: true,
              child: Text(
                time,
                key: Key('$keys-time'),
                style: sans(13, 18, p.ink2).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(width: 4),
          ],
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
