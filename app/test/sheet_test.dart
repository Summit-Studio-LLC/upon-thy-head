import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/sheet.dart';

void main() {
  // A sheet that is off is slid below the screen but still built. VoiceOver must not reach it
  // (found 2026-11-16: "A recording was kept | Later" was readable on the sky with no sheet up).
  for (final barrier in [false, true]) {
    testWidgets('a sheet that is off is out of VoiceOver\'s reach (barrier: $barrier)', (t) async {
      final semantics = t.ensureSemantics();
      Widget sheet(bool on) => MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Sheet(
                palette: Palette.vigil,
                on: on,
                barrier: barrier,
                label: 'A recording was kept',
                child: const Text('Later'),
              ),
            ),
          );
      await t.pumpWidget(sheet(false));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('A recording was kept'), findsNothing);
      expect(find.bySemanticsLabel('Later'), findsNothing);
      await t.pumpWidget(sheet(true));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('A recording was kept')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Later')), findsWidgets);
      semantics.dispose();
    });
  }
}
