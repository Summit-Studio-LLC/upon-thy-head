/// How much of the date a blessing was given on is known. A recording knows the minute; one
/// entered from a written copy may know only the month, or only the year.
enum DatePrecision {
  /// The day (a recording: the minute too).
  day('day'),

  /// The month and year: its light sits on the 15th.
  month('month'),

  /// Only the year: its light sits on July 2, the middle of the year.
  year('year'),

  /// Not yet given: an entry still being written, before "When was it given?" is answered. It has
  /// no light and no place on any ring until it has a date.
  unset('unset');

  const DatePrecision(this.code);

  /// What the store and the blessing file keep.
  final String code;

  static DatePrecision fromCode(String? code) => values.firstWhere((v) => v.code == code, orElse: () => day);
}

/// The local wall time a blessing's light sits at, for a date known to [p]: noon of the day, noon
/// of the 15th, or noon of July 2. No time of day is asked of an entered blessing.
DateTime givenAnchor(DatePrecision p, int year, [int month = 1, int day = 1]) => switch (p) {
      DatePrecision.month => DateTime(year, month, 15, 12),
      DatePrecision.year => DateTime(year, 7, 2, 12),
      DatePrecision.day || DatePrecision.unset => DateTime(year, month, day, 12),
    };

/// The days in [month] of [year].
int daysIn(int year, int month) => DateTime(year, month + 1, 0).day;
