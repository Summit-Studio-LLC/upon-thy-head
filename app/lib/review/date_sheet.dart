import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../data/given.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/whole_words.dart';

/// What the date sheet chose: how much is known, and the date (the month and day are 1 where they
/// are not known).
typedef GivenChoice = ({DatePrecision precision, int year, int month, int day});

/// "When was it given?": Full date / Month and year / Year only, and wheels to match, drawn by the
/// app (the same on iPhone and Android). No date after today. Shown in a [Sheet] on the entry page.
class DateSheet extends StatefulWidget {
  const DateSheet({super.key, required this.palette, required this.initial, required this.onDone, this.today});

  final Palette palette;

  /// Where the wheels start: the date already chosen, or today.
  final GivenChoice initial;

  final ValueChanged<GivenChoice> onDone;

  /// Today, for tests; else the phone's.
  final DateTime? today;

  /// The earliest year on the wheel.
  static const firstYear = 1900;

  @override
  State<DateSheet> createState() => DateSheetState();
}

class DateSheetState extends State<DateSheet> {
  late DatePrecision _precision;
  late int _year, _month, _day;
  FixedExtentScrollController _years = FixedExtentScrollController(), _months = FixedExtentScrollController(), _days = FixedExtentScrollController();

  /// Bumped when the wheels are made again (the sheet opens again, or its kind changes), so each
  /// new wheel starts at the choice made.
  int _gen = 0;

  void _renew() {
    final old = [_years, _months, _days];
    _years = FixedExtentScrollController(initialItem: _year - DateSheet.firstYear);
    _months = FixedExtentScrollController(initialItem: _month - 1);
    _days = FixedExtentScrollController(initialItem: _day - 1);
    _gen++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  DateTime get _today => widget.today ?? DateTime.now();

  /// What is chosen now (for tests).
  GivenChoice get choice => (
        precision: _precision,
        year: _year,
        month: _precision == DatePrecision.year ? 1 : _month,
        day: _precision == DatePrecision.day ? _day : 1,
      );

  @override
  void initState() {
    super.initState();
    reset(widget.initial);
  }

  /// Start again from [c] (the sheet opens again).
  void reset(GivenChoice c) {
    _precision = c.precision == DatePrecision.unset ? DatePrecision.day : c.precision;
    _year = c.year;
    _month = c.month;
    _day = c.day;
    _clamp();
    _renew();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _years.dispose();
    _months.dispose();
    _days.dispose();
    super.dispose();
  }

  int get _lastMonth => _year == _today.year ? _today.month : 12;
  int get _lastDay => _year == _today.year && _month == _today.month ? _today.day : daysIn(_year, _month);

  /// Never past today, never a day the month does not have.
  void _clamp() {
    _year = _year.clamp(DateSheet.firstYear, _today.year);
    _month = _month.clamp(1, _lastMonth);
    _day = _day.clamp(1, _lastDay);
  }

  void _set({int? year, int? month, int? day}) {
    final before = (m: _month, d: _day);
    setState(() {
      _year = year ?? _year;
      _month = month ?? _month;
      _day = day ?? _day;
      _clamp();
    });
    // a wheel whose choice was cut back (a shorter month, this year) turns to it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (before.m != _month && _months.hasClients && _months.selectedItem != _month - 1) _months.jumpToItem(_month - 1);
      if (before.d != _day && _days.hasClients && _days.selectedItem != _day - 1) _days.jumpToItem(_day - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2).scale(1);
    final extent = 40.0 * math.max(1.0, scale);
    final wheelStyle = sans(22, 28, p.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final months = Strings.months;
    Widget wheel({
      required Key key,
      required String label,
      required FixedExtentScrollController controller,
      required int count,
      required String Function(int) text,
      required ValueChanged<int> onChanged,
      int flex = 1,
    }) =>
        Expanded(
          flex: flex,
          child: Semantics(
            label: label,
            child: CupertinoPicker.builder(
              key: key,
              scrollController: controller,
              itemExtent: extent,
              diameterRatio: 1.6,
              squeeze: 1,
              useMagnifier: false,
              backgroundColor: const Color(0x00000000),
              selectionOverlay: const SizedBox.shrink(),
              onSelectedItemChanged: onChanged,
              childCount: count,
              itemBuilder: (context, i) => Center(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 2,
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(text(i), style: wheelStyle, maxLines: 1)),
                ),
              ),
            ),
          ),
        );
    final monthWheel = wheel(
      key: const Key('wheel-month'),
      label: Strings.monthWheel,
      controller: _months,
      count: _lastMonth,
      text: (i) => months[i],
      onChanged: (i) => _set(month: i + 1),
      flex: 5,
    );
    final dayWheel = wheel(
      key: const Key('wheel-day'),
      label: Strings.dayWheel,
      controller: _days,
      count: _lastDay,
      text: (i) => '${i + 1}',
      onChanged: (i) => _set(day: i + 1),
      flex: 2,
    );
    final yearWheel = wheel(
      key: const Key('wheel-year'),
      label: Strings.yearWheel,
      controller: _years,
      count: _today.year - DateSheet.firstYear + 1,
      text: (i) => '${DateSheet.firstYear + i}',
      onChanged: (i) => _set(year: DateSheet.firstYear + i),
      flex: 3,
    );
    // Spanish puts the day before the month
    final dayFirst = Strings.language == UiLanguage.spanish;
    final wheels = switch (_precision) {
      DatePrecision.year => [const Spacer(flex: 3), yearWheel, const Spacer(flex: 3)],
      DatePrecision.month => [const Spacer(), monthWheel, yearWheel, const Spacer()],
      _ => dayFirst ? [dayWheel, monthWheel, yearWheel] : [monthWheel, dayWheel, yearWheel],
    };
    final note = Strings.precisionNote(_precision, givenAnchor(_precision, _year, _month, 15));
    return Column(
      key: const Key('date-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WholeWords(Strings.whenGiven, maxScale: titleMaxScale, style: serif(26, 32, p.ink)),
        const SizedBox(height: 16),
        PrecisionChoice(palette: p, value: _precision, onChanged: (v) {
          if (v == _precision) return;
          setState(() {
            _precision = v;
            _renew();
          });
        }),
        const SizedBox(height: 12),
        SizedBox(
          height: extent * 5,
          child: Stack(children: [
            // the band the chosen row sits in
            Positioned(
              left: 0,
              right: 0,
              top: extent * 2,
              height: extent,
              child: DecoratedBox(decoration: BoxDecoration(color: p.ink.withValues(alpha: .07), borderRadius: BorderRadius.circular(12))),
            ),
            // one key per arrangement, so the wheels are made again (at their choices) when it changes
            Row(key: ValueKey(_gen), children: [for (final w in wheels) w]),
          ]),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 12),
                child: SizedBox(width: 20, height: 20, child: GlyphIcon(Glyph.sky, color: p.light)),
              ),
            ),
            Expanded(child: Text(note, key: const Key('date-note'), style: sans(15, 22, p.ink2))),
          ]),
        ],
        const SizedBox(height: 20),
        PillBtn(
          key: const Key('date-done'),
          label: Strings.done,
          palette: p,
          kind: PillKind.primary,
          height: 52,
          onTap: () => widget.onDone(choice),
        ),
      ],
    );
  }
}

/// Full date | Month and year | Year only.
class PrecisionChoice extends StatelessWidget {
  const PrecisionChoice({super.key, required this.palette, required this.value, required this.onChanged});
  final Palette palette;
  final DatePrecision value;
  final ValueChanged<DatePrecision> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget part(DatePrecision v, String label) {
      final on = value == v;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          inMutuallyExclusiveGroup: true,
          label: label,
          excludeSemantics: true,
          onTap: () => onChanged(v),
          child: GestureDetector(
            key: Key('precision-${v.code}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(color: on ? p.ink.withValues(alpha: .16) : const Color(0x00000000), borderRadius: BorderRadius.circular(22)),
              child: WholeWords(label, textAlign: TextAlign.center, style: sans(15, 20, on ? p.ink : p.ink2, weight: on ? FontWeight.w500 : FontWeight.w400)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.ink.withValues(alpha: .06), borderRadius: BorderRadius.circular(26)),
      child: Row(children: [
        part(DatePrecision.day, Strings.fullDateChoice),
        part(DatePrecision.month, Strings.monthAndYear),
        part(DatePrecision.year, Strings.yearOnly),
      ]),
    );
  }
}
