// The review page with the phone's own model: "Polish the words" shows "Polishing…" while it works,
// leaving the page stops it and adds nothing, and when it finishes its changes open on the changes
// screen beside the rules' (once the words that changed have glinted). With no model, the page is as
// it always was, but for the glint.
//
//   flutter test test/polish_model_widget_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/polish/model.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';

import 'polish_model_test.dart' show FakeModel;
import 'screen_reader_test.dart' show show, FakePlayer, p;

Blessing recorded() => Blessing(
      id: 'w',
      title: 'Blessing',
      from: 'Dad',
      utc: DateTime.utc(2026, 11, 1),
      utcOffset: Duration.zero,
      place: const Place(40, -111),
      rawText: 'I bless you, um, with peace and there home will be blessed',
      language: 'en',
    );

/// The review page, which [_PageState.close] closes, as leaving it does.
class _Page extends StatefulWidget {
  const _Page({super.key, required this.b, required this.onChanges});
  final Blessing b;
  final VoidCallback onChanges;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  bool on = true;
  void close() => setState(() => on = false);
  @override
  Widget build(BuildContext context) => ReviewLayer(
        palette: p,
        blessing: widget.b,
        on: on,
        player: FakePlayer(),
        onSave: () async {},
        onBack: () {},
        onFinish: () {},
        onChanges: widget.onChanges,
      );
}

void main() {
  tearDown(() => phoneModel = const NoModel());

  for (final lang in UiLanguage.values) {
    group(lang.name, () {
      setUp(() => Strings.use(lang));
      tearDown(() => Strings.use(UiLanguage.english));

      testWidgets('Polishing… while the model works; then the changes screen, rules and model together', (t) async {
        final model = FakeModel((s) => s.replaceAll('there home', 'their home.'), delay: const Duration(seconds: 2));
        phoneModel = model;
        final b = recorded();
        var opened = 0;
        final key = GlobalKey<_PageState>();
        await show(t, _Page(key: key, b: b, onChanges: () => opened++));
        await t.tap(find.byKey(const Key('review-polish')));
        await t.pump();
        expect(find.byKey(const Key('review-polishing')), findsOneWidget);
        expect(find.text(Strings.polishing), findsOneWidget);
        expect(find.byKey(const Key('review-polish')), findsNothing, reason: 'no second press while it works');
        await t.pump(const Duration(seconds: 3));
        await t.pump();
        // the changed words glint, then the changes screen opens
        await t.pump(ReviewLayerState.glintTime);
        expect(opened, 1);
        expect(b.changes.where((c) => c.source == 'rules'), isNotEmpty);
        expect(b.changes.where((c) => c.source == ModelSource.name), isNotEmpty);
        expect(b.polishedText, contains('their home.'));
        expect(find.byKey(const Key('review-polished')), findsOneWidget);
      });

      testWidgets('leaving while it works stops it, and nothing is added', (t) async {
        final model = FakeModel((s) => '$s.', delay: const Duration(seconds: 2));
        phoneModel = model;
        final b = recorded();
        var opened = 0;
        final key = GlobalKey<_PageState>();
        await show(t, _Page(key: key, b: b, onChanges: () => opened++));
        await t.tap(find.byKey(const Key('review-polish')));
        await t.pump();
        expect(find.byKey(const Key('review-polishing')), findsOneWidget);
        key.currentState!.close();
        await t.pump();
        expect(model.cancelled, isNotEmpty);
        await t.pump(const Duration(seconds: 3));
        expect(opened, 0);
        expect(b.changes, isEmpty);
        expect(b.polishAsked, isFalse);
      });

      testWidgets('no model: polish is the rules at once, as before', (t) async {
        phoneModel = FakeModel((s) => '$s.', isReady: false);
        final b = recorded();
        var opened = 0;
        final key = GlobalKey<_PageState>();
        await show(t, _Page(key: key, b: b, onChanges: () => opened++));
        await t.tap(find.byKey(const Key('review-polish')));
        await t.pump();
        expect(find.byKey(const Key('review-polishing')), findsNothing);
        expect(opened, 0, reason: 'the glint first');
        await t.pump(ReviewLayerState.glintTime);
        expect(opened, 1);
        expect(b.changes.every((c) => c.source == 'rules'), isTrue);
      });
    });
  }
}
