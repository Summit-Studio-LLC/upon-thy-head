// A pill beside other things in a row keeps its own width; a pill spanning its column stops at a
// phone's width. Build 12 went out with the first kind 420 points wide, which crushed the title
// beside Stop on Your links ("RIGHT OVERFLOWED BY 86 PIXELS").
//
//   flutter test test/pill_width_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/buttons.dart';
import 'package:upon_thy_head/widgets/measure.dart';

Widget _host(double width, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child)),
    );

void main() {
  const p = Palette.lamplight;
  const key = Key('pill');

  testWidgets('beside a title in a row, as Stop on Your links: its own width, nothing overflows', (t) async {
    await t.pumpWidget(_host(
      346,
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Comfort before surgery', key: const Key('title'), style: serif(19, 25, p.ink)),
            Text('Sent today · stops December 21', style: sans(13, 18, p.ink2)),
          ]),
        ),
        const SizedBox(width: 12),
        PillBtn(key: key, label: 'Stop', palette: p, kind: PillKind.tonal, height: 40, fontSize: 15, onTap: () {}),
      ]),
    ));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byKey(key)).width, lessThan(120));
    expect(t.getSize(find.byKey(const Key('title'))).width, greaterThan(150));
  });

  testWidgets('spanning a phone column: the column\'s width', (t) async {
    await t.pumpWidget(_host(
      346,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PillBtn(key: key, label: 'Continue', palette: p, kind: PillKind.primary, onTap: () {}),
      ]),
    ));
    expect(t.takeException(), isNull);
    final pill = t.getSize(find.descendant(of: find.byKey(key), matching: find.byType(AnimatedContainer)));
    expect(pill.width, 346);
  });

  testWidgets('spanning an iPad column: a phone\'s width, centred', (t) async {
    await t.pumpWidget(_host(
      700,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PillBtn(key: key, label: 'Continue', palette: p, kind: PillKind.primary, onTap: () {}),
      ]),
    ));
    expect(t.takeException(), isNull);
    final box = find.descendant(of: find.byKey(key), matching: find.byType(AnimatedContainer));
    expect(t.getSize(box).width, Widths.pill);
    expect(t.getTopLeft(box).dx, (700 - Widths.pill) / 2);
  });
}
