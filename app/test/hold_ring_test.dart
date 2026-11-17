// The ring that discards, then finishes, and the line under it that says so, at every text size:
// the ring's word stays inside the ring, and the line stays below the ring with a gap (found at
// Android's largest font and display size in Spanish, design/sim/android/46).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/record/hold_ring.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hold_ring'));
  tearDown(() {
    Strings.use(UiLanguage.english);
    dir.deleteSync(recursive: true);
  });

  // (logical width, height): iPhone 17 Pro; Pixel 10 Pro at its largest display size (480 dpi × 1.3)
  const screens = [(402.0, 874.0), (328.0, 732.0)];
  // iPhone's text sizes up to its first accessibility size (1.35 here, about AX1), then Android's
  // largest font (2.0), and beyond it
  const scales = [1.0, 1.35, 2.0, 3.0];

  for (final lang in [UiLanguage.english, UiLanguage.spanish]) {
    for (final practice in [false, true]) {
      final word = practice ? 'Amen' : 'Discard';
      testWidgets('${lang.name}, $word: the word in the ring and the line below it, at every size', (t) async {
        Strings.use(lang);
        for (final (w, h) in screens) {
          for (final scale in scales) {
            t.view.physicalSize = Size(w * 3, h * 3);
            t.view.devicePixelRatio = 3;
            final s = RecordSession(recorder: SilentRecorder(), practice: practice, audioDir: '${dir.path}/audio')
              ..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
            await t.runAsync(() async {
              await s.checkPermissions(ask: false);
              await s.begin();
            });
            await t.pumpWidget(MediaQuery(
              data: MediaQueryData(size: Size(w, h), textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: RecordLayer(
                  palette: Palette.lamplight,
                  session: s,
                  active: false,
                  practice: practice,
                  onBegin: () {},
                  onClose: () {},
                  onDiscardEarly: () {},
                  onAmen: () {},
                  onLanguage: (_) {},
                  onOpenSettings: () {},
                ),
              ),
            ));
            await t.pump(const Duration(seconds: 3)); // the ring fades in
            final where = '${w.toInt()}×${h.toInt()} at ${scale}x';
            final ring = t.getRect(find.byKey(const Key('hold')));
            final c = ring.center;
            const r = HoldRing.size / 2;
            final hint = t.getRect(find.byKey(const Key('hold-hint')));
            // one line of hint (the usual size; the test font's square letters wrap Spanish sooner
            // than the real one): the ring is exactly where it always was
            if (hint.height <= 18.5) {
              expect(c.dy, closeTo(h - 136, .5), reason: '$where: the ring has moved with a one-line hint');
            }
            final label = t.getRect(find.byKey(Key(practice ? 'lb-amen' : 'lb-discard')));
            // inside the circle: every corner of the word's box within the ring's radius
            for (final corner in [label.topLeft, label.topRight, label.bottomLeft, label.bottomRight]) {
              expect((corner - c).distance, lessThanOrEqualTo(r), reason: '$where: "$word" leaves the ring ($label, ring at $c)');
            }
            expect(hint.top, greaterThanOrEqualTo(c.dy + r + 8), reason: '$where: the line runs into the ring ($hint, ring at $c)');
            expect(hint.bottom, lessThanOrEqualTo(h), reason: '$where: the line runs off the screen');
            expect(ring.top, greaterThanOrEqualTo(0), reason: '$where: the ring is pushed off the top');
            await t.runAsync(() async {
              s.discard();
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
            await t.pumpWidget(const SizedBox());
            s.dispose();
          }
        }
        t.view.reset();
      });
    }
  }
}
