import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/home/ruler.dart';

void main() {
  // the years' labels on home's date bar (fault of 2026-11-21: a ring from 1998 printed
  // "1999200120032005…", the labels on top of each other)
  group('the year labels', () {
    const spans = [1, 2, 3, 4, 5, 6, 8, 12, 20, 29, 30, 45, 60, 100];
    const widths = [230.0, 300.0, 330.0, 700.0];
    // 26: the real font at 11 points; 44: the test font; 90: far wider, as a larger text might be
    const labelWidths = [26.0, 44.0, 90.0];

    for (final span in spans) {
      for (final width in widths) {
        for (final lw in labelWidths) {
          test('$span years across $width, labels $lw wide: never touching, inside the bar, at a regular step', () {
            final start = 2027 - span;
            final labels = rulerYearLabels(startYear: start, years: span, width: width, labelWidth: lw);
            for (final l in labels) {
              expect(l.centre - lw / 2, greaterThanOrEqualTo(0), reason: '${l.year} past the start');
              expect(l.centre + lw / 2, lessThanOrEqualTo(width), reason: '${l.year} past the end');
            }
            for (var i = 1; i < labels.length; i++) {
              final gap = labels[i].centre - labels[i - 1].centre - lw;
              expect(gap, greaterThanOrEqualTo(rulerLabelGap - .001), reason: '${labels[i - 1].year} and ${labels[i].year} too close: $gap');
            }
            final steps = {for (var i = 1; i < labels.length; i++) labels[i].year - labels[i - 1].year};
            expect(steps.length, lessThanOrEqualTo(1), reason: 'one step between all labels: $steps');
            if (steps.isNotEmpty) expect(const [1, 2, 5, 10, 20, 25, 50, 100], contains(steps.single));
            // at least one year is named whenever one fits
            if (lw + 2 <= width) expect(labels, isNotEmpty);
          });
        }
      }
    }

    test('a ring of three years names each year; one of five or more every second, as before', () {
      expect(rulerYearLabels(startYear: 2024, years: 3, width: 330, labelWidth: 26).map((l) => l.year), [2024, 2025, 2026]);
      expect(rulerYearLabels(startYear: 2021, years: 6, width: 330, labelWidth: 26).map((l) => l.year), [2022, 2024, 2026]);
    });

    test('a ring from 1998: round years, every fifth or tenth', () {
      final years = rulerYearLabels(startYear: 1998, years: 29, width: 330, labelWidth: 26).map((l) => l.year).toList();
      expect(years.every((y) => y % 5 == 0), isTrue, reason: '$years');
      expect(years.length, greaterThanOrEqualTo(3));
    });
  });
}
