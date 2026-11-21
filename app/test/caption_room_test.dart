import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/home/caption_room.dart';
import 'package:upon_thy_head/theme.dart';

// Home's caption at the largest text on iPhone ran up over the ring (found 2026-11-21): it now
// grows only as far as the room between the ring and the ruler.
void main() {
  const ink = Color(0xFFFFFFFF);
  Widget caption(String date, String title, String from) => CaptionRoom(
        date: date,
        title: title,
        from: from,
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(date, key: const Key('cap-date'), style: sans(13, 18, ink, tracking: .005)),
                const SizedBox(height: 6),
                Text(title, key: const Key('cap-title'), style: serif(30, 34, ink, tracking: -.012)),
                const SizedBox(height: 4),
                Text(from, style: serif(18, 26, ink, italic: true)),
              ]),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 44, height: 44),
          ]),
        ),
      );

  Future<Rect> show(WidgetTester t, double scale, double room) async {
    await t.pumpWidget(MediaQuery(
      data: MediaQueryData(size: const Size(402, 874), textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 402,
            height: room,
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(child: caption('Sunday, October 4, 2026', 'Before the new job', 'From Dad')),
            ]),
          ),
        ),
      ),
    ));
    return t.getRect(find.byType(CaptionRoom));
  }

  for (final scale in [1.0, 1.76, 2.35, 3.1]) {
    testWidgets('text ×$scale: the caption keeps within its room, and is never made larger than the person\'s size', (t) async {
      // iPhone 17 Pro: from under the ring to the ruler, the room home gives it
      const room = 874 - (874 * .4 + 40) - 30 - 140;
      final r = await show(t, scale, room);
      expect(t.takeException(), isNull);
      expect(r.height, lessThanOrEqualTo(room + .5));
      final title = t.widget<RichText>(find.descendant(of: find.byKey(const Key('cap-title')), matching: find.byType(RichText)));
      expect(title.textScaler.scale(30), lessThanOrEqualTo(30 * scale + .01));
    });
  }

  testWidgets('at the usual size it is left as it was', (t) async {
    await show(t, 1, 400);
    final title = t.widget<RichText>(find.descendant(of: find.byKey(const Key('cap-title')), matching: find.byType(RichText)));
    expect(title.textScaler.scale(30), 30);
  });
}
