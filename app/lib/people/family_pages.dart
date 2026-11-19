import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;

import '../not_yet.dart';
import '../share/links.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/over_sky_page.dart';
import '../widgets/sheet.dart';
import 'hand_over_sheet.dart';
import 'person.dart';

/// Adding a family member (design B1-04), or changing one: a name and an optional birth date
/// ("Their ring begins on this day"). Changing one also offers to remove them; removing someone who
/// has blessings says how many leave the phone with them, and asks first ([ConfirmSheet], as
/// deleting a blessing does).
class PersonLayer extends StatefulWidget {
  const PersonLayer({
    super.key,
    required this.palette,
    required this.on,
    required this.person,
    required this.onBack,
    required this.onSave,
    this.countLine = '',
    this.blessings = 0,
    this.onRemove,
    this.keptBy = '',
    this.onMakeRing,
    this.onShareRing,
    this.onRingSent,
  });

  final Palette palette;
  final bool on;

  /// Handing their ring to their own phone (hand_over_sheet.dart): the "Kept by" name to start
  /// with, making the link, the system share sheet, and once it was sent. Without [onMakeRing]
  /// (no link service) there is no row for it.
  final String keptBy;
  final Future<MakeResult> Function(String keptBy)? onMakeRing;
  final Future<bool> Function(String url, String title)? onShareRing;
  final void Function(String keptBy)? onRingSent;

  /// Null when adding.
  final Person? person;

  /// For one being changed: their count line, and how many blessings are on their ring.
  final String countLine;
  final int blessings;
  final VoidCallback onBack;

  /// Add (or Save) with the name as typed and the birth date, if any.
  final void Function(String name, Day? born) onSave;

  /// Remove, confirmed. False when it could not be done (a link of theirs could not be stopped).
  final Future<bool> Function()? onRemove;

  @override
  State<PersonLayer> createState() => PersonLayerState();
}

class PersonLayerState extends State<PersonLayer> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  Day? _born;
  bool _picking = false, _removing = false, _busy = false, _handing = false;
  String? _removeNote;
  DateTime _pending = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reset();
    _name.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(PersonLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.on && !oldWidget.on) || widget.person?.id != oldWidget.person?.id) _reset();
    if (!widget.on && oldWidget.on) {
      _nameFocus.unfocus();
      _picking = _removing = _handing = false;
    }
  }

  void _reset() {
    _name.text = widget.person?.name ?? '';
    _born = widget.person?.born;
    _picking = _removing = _busy = _handing = false;
    _removeNote = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Android's back: the date or the remove sheet goes, if one is up. True when one went.
  bool closeSheet() {
    if (!_picking && !_removing && !_handing) return false;
    setState(() => _picking = _removing = _handing = false);
    return true;
  }

  bool get _ready => cleanName(_name.text).isNotEmpty;

  void _save() {
    if (!_ready) return;
    _nameFocus.unfocus();
    widget.onSave(cleanName(_name.text), _born);
  }

  void _pick() {
    _nameFocus.unfocus();
    final now = DateTime.now();
    final b = _born?.local;
    _pending = b == null || b.isAfter(now) ? DateTime(now.year, now.month, now.day) : b;
    setState(() => _picking = true);
  }

  Future<void> _remove() async {
    final remove = widget.onRemove;
    if (remove == null || _busy) return;
    _busy = true;
    final ok = await remove();
    _busy = false;
    if (!mounted) return;
    setState(() {
      if (ok) {
        _removing = false;
      } else {
        _removeNote = Strings.deleteStopOffline;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final person = widget.person;
    final adding = person == null;
    final born = _born;
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 28;
    Widget row(String label, Widget value, {VoidCallback? onTap}) {
      final l = ExcludeSemantics(child: Text(label, style: sans(15, 20, p.ink2)));
      final double labelWidth = 72 * math.max(1.0, MediaQuery.textScalerOf(context).scale(15) / 15);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: stacked
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.only(top: 12), child: l),
                  Padding(padding: const EdgeInsets.only(top: 4, bottom: 14), child: value),
                ])
              : Row(children: [
                  SizedBox(width: labelWidth, child: l),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 15), child: value)),
                ]),
        ),
      );
    }

    Widget rule() => Container(height: 1, color: p.ink.withValues(alpha: .10));

    final field = CupertinoTextField(
      key: const Key('person-name'),
      controller: _name,
      focusNode: _nameFocus,
      style: sans(17, 22, p.ink),
      placeholder: Strings.personName,
      placeholderStyle: sans(17, 22, p.ink3),
      cursorColor: p.light,
      keyboardAppearance: Brightness.dark,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      maxLength: nameLimit,
      onSubmitted: (_) => _nameFocus.unfocus(),
      padding: EdgeInsets.zero,
      decoration: null,
      selectionControls: Phone.android ? m.materialTextSelectionHandleControls : null,
      contextMenuBuilder: Phone.android
          ? (context, s) => m.AdaptiveTextSelectionToolbar.editableText(editableTextState: s)
          : (context, s) => CupertinoAdaptiveTextSelectionToolbar.editableText(editableTextState: s),
    );
    final nameField = MergeSemantics(
      child: Semantics(
        label: Strings.personName,
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
    final bornText = born == null ? Strings.bornNotSet : Strings.longDate(born.local).replaceFirst(RegExp(r'^[^,]+, '), '');
    final bornValue = Semantics(
      button: true,
      label: '${Strings.born}, ${born == null ? Strings.noDate : bornText}',
      excludeSemantics: true,
      onTap: _pick,
      child: Text(bornText, key: const Key('person-born'), style: sans(17, 22, born == null ? p.ink3 : p.ink)),
    );

    return Stack(children: [
      Positioned.fill(
        child: OverSkyPage(
          palette: p,
          title: adding ? Strings.addFamilyMember : person.name,
          titleKey: const Key('person-title'),
          lede: adding ? Strings.addFamilyLede : (widget.countLine.isEmpty ? Strings.editPersonLede : widget.countLine),
          backKey: const Key('person-back'),
          scrollKey: const Key('person-scroll'),
          onBack: widget.onBack,
          children: [
            row(Strings.personName, nameField, onTap: _nameFocus.requestFocus),
            rule(),
            row(Strings.born, bornValue, onTap: _pick),
            rule(),
            const SizedBox(height: 12),
            Text(Strings.bornNote, key: const Key('person-born-note'), style: sans(14, 20, p.ink3)),
            const SizedBox(height: 28),
            Opacity(
              opacity: _ready ? 1 : .4,
              child: PillBtn(
                key: const Key('person-save'),
                label: adding ? Strings.add : Strings.save,
                palette: p,
                kind: PillKind.primary,
                enabled: _ready,
                onTap: _ready ? _save : null,
              ),
            ),
            // never suggested: one quiet row, only for someone with blessings to hand over
            if (!adding && widget.blessings > 0 && widget.onMakeRing != null) ...[
              const SizedBox(height: 28),
              Container(height: 1, color: p.ink.withValues(alpha: .10)),
              OpenRow(
                key: const Key('person-hand-over'),
                palette: p,
                semantics: [Strings.handOverRow(person.name), if (person.handed != null) Strings.handedOn(person.name, person.handed!.toLocal())].join('. '),
                onTap: () => setState(() {
                  _nameFocus.unfocus();
                  _handing = true;
                }),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Strings.handOverRow(person.name), style: sans(16, 21, p.ink)),
                  if (person.handed != null) ...[
                    const SizedBox(height: 3),
                    Text(Strings.handedOn(person.name, person.handed!.toLocal()), key: const Key('person-handed'), style: sans(13, 18, p.ink3)),
                  ],
                ]),
              ),
              Container(height: 1, color: p.ink.withValues(alpha: .10)),
            ],
            if (!adding && widget.onRemove != null) ...[
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: _QuietBtn(
                    key: const Key('person-remove'),
                    label: Strings.removePerson(person.name),
                    color: p.danger,
                    palette: p,
                    onTap: () => setState(() {
                      _nameFocus.unfocus();
                      _removeNote = null;
                      _removing = true;
                    }),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      Positioned.fill(
        child: Sheet(
          palette: p,
          on: _picking && widget.on,
          barrier: true,
          label: Strings.born,
          panelKey: const Key('born-sheet'),
          onDismiss: () => setState(() => _picking = false),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(Strings.born, style: serif(22, 28, p.ink)),
            const SizedBox(height: 4),
            Text(Strings.bornNote, style: sans(14, 20, p.ink3)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(dateTimePickerTextStyle: sans(21, 26, p.ink)),
                ),
                child: _picking
                    ? CupertinoDatePicker(
                        key: const Key('born-picker'),
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: _pending,
                        minimumYear: 1900,
                        maximumDate: () {
                          final n = DateTime.now();
                          return DateTime(n.year, n.month, n.day, 23, 59);
                        }(),
                        onDateTimeChanged: (d) => _pending = d,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
            SheetButtons(
              palette: p,
              left: PillBtn(
                key: const Key('born-none'),
                label: Strings.noDate,
                palette: p,
                kind: PillKind.tonal,
                height: 48,
                fontSize: 16,
                onTap: () => setState(() {
                  _born = null;
                  _picking = false;
                }),
              ),
              right: PillBtn(
                key: const Key('born-done'),
                label: Strings.done,
                palette: p,
                kind: PillKind.primary,
                height: 48,
                fontSize: 16,
                onTap: () => setState(() {
                  _born = Day.of(_pending);
                  _picking = false;
                }),
              ),
            ),
          ]),
        ),
      ),
      if (person != null && widget.onMakeRing != null)
        Positioned.fill(
          child: HandOverSheet(
            palette: p,
            on: _handing && widget.on,
            person: person,
            countLine: widget.countLine,
            keptBy: widget.keptBy,
            onMake: widget.onMakeRing!,
            onShare: widget.onShareRing ?? (_, _) async => false,
            onSent: (name) => widget.onRingSent?.call(name),
            onClose: () => setState(() => _handing = false),
            // delete it now: asked once more, as removing them is
            onDelete: () => setState(() {
              _handing = false;
              _removeNote = null;
              _removing = true;
            }),
          ),
        ),
      if (person != null)
        Positioned.fill(
          child: ConfirmSheet(
            palette: p,
            on: _removing && widget.on,
            barrier: true,
            title: Strings.removeTitle(person.name),
            body: Strings.removeBody(person.name, widget.blessings),
            note: _removeNote,
            noteKey: const Key('remove-note'),
            dangerLabel: Strings.remove,
            safeLabel: Strings.keep,
            onDanger: () => unawaited(_remove()),
            onSafe: () => setState(() => _removing = false),
            panelKey: const Key('remove-sheet'),
            dangerKey: const Key('remove-confirm'),
            safeKey: const Key('remove-keep'),
          ),
        ),
    ]);
  }
}

/// "Manage family": each family member with their count; a row opens their page. And a way to add
/// another.
class FamilyLayer extends StatelessWidget {
  const FamilyLayer({
    super.key,
    required this.palette,
    required this.people,
    required this.countLine,
    required this.onBack,
    required this.onOpen,
    required this.onAdd,
  });

  final Palette palette;
  final List<Person> people;

  /// Each one's "Seven blessings since August 2008".
  final String Function(Person) countLine;
  final VoidCallback onBack, onAdd;
  final ValueChanged<Person> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return OverSkyPage(
      palette: p,
      title: Strings.manageFamily,
      titleKey: const Key('family-title'),
      lede: Strings.manageLede,
      backKey: const Key('family-back'),
      scrollKey: const Key('family-scroll'),
      onBack: onBack,
      children: [
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(Strings.manageNone, key: const Key('family-none'), style: sans(15, 22, p.ink3)),
          ),
        for (final person in people) ...[
          OpenRow(
            key: Key('family-row-${person.id}'),
            palette: p,
            semantics: [person.name, countLine(person), if (person.born != null) Strings.bornOn(person.born!.local)].join('. '),
            onTap: () => onOpen(person),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(person.name, style: serif(20, 26, p.ink)),
              const SizedBox(height: 3),
              Text(countLine(person), key: Key('family-count-${person.id}'), style: sans(13, 18, p.ink2)),
              if (person.born != null) ...[
                const SizedBox(height: 1),
                Text(Strings.bornOn(person.born!.local), style: sans(13, 18, p.ink3)),
              ],
            ]),
          ),
          Container(height: 1, color: p.ink.withValues(alpha: .10)),
        ],
        const SizedBox(height: 24),
        PillBtn(key: const Key('family-add'), label: Strings.addFamilyMember, palette: p, kind: PillKind.tonal, height: 48, fontSize: 16, onTap: onAdd),
      ],
    );
  }
}

/// A quiet word as a button, in [color] (as the reading page's "Delete this blessing").
class _QuietBtn extends StatefulWidget {
  const _QuietBtn({super.key, required this.label, required this.color, required this.palette, required this.onTap});
  final String label;
  final Color color;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<_QuietBtn> createState() => _QuietBtnState();
}

class _QuietBtnState extends State<_QuietBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: widget.palette.ink.withValues(alpha: _down ? .07 : 0), borderRadius: BorderRadius.circular(22)),
          child: Text(widget.label, style: sans(15, 20, widget.color)),
        ),
      ),
    );
  }
}
