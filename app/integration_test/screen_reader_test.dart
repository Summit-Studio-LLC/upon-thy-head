// The main path in the real app, pressed only as VoiceOver and TalkBack press: each step is the
// node's semantics action (what iOS's accessibilityActivate and Android's ACTION_CLICK send), never
// a touch. New blessing, Begin, the ring in its first ten seconds (asks first), Keep listening, Amen
// by a double-tap, Save for later. Then the app locked: nothing in the semantics tree names any
// blessing or family member. In English and Spanish.
//
//   flutter drive -d <simulator> --driver=test_driver/integration_test.dart \
//     --target=integration_test/screen_reader_test.dart
// (tool/integration_tests.sh runs it with the others.)

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final lang in UiLanguage.values) {
    testWidgets('${lang.name}: the main path by screen reader, then the locked home says nothing private', (tester) async {
      Strings.use(lang);
      final handle = tester.ensureSemantics();
      Future<void> wait(int ms) async {
        final end = DateTime.now().add(Duration(milliseconds: ms));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      SemanticsOwner owner() => tester.binding.renderViews.first.owner!.semanticsOwner!;
      List<SemanticsNode> nodes() {
        final out = <SemanticsNode>[];
        void walk(SemanticsNode n) {
          out.add(n);
          n.visitChildren((c) {
            walk(c);
            return true;
          });
        }

        final root = owner().rootSemanticsNode;
        if (root != null) walk(root);
        return out;
      }

      // what a screen reader can be told: every label, value and hint in the tree, shown or not
      List<String> said() => [
            for (final n in nodes())
              for (final s in [n.getSemanticsData().label, n.getSemanticsData().value, n.getSemanticsData().hint, n.getSemanticsData().tooltip])
                if (s.isNotEmpty) s,
          ];

      Future<void> press(String label, {SemanticsAction action = SemanticsAction.tap}) async {
        SemanticsNode? found;
        for (var i = 0; i < 100 && found == null; i++) {
          found = nodes().where((n) => n.getSemanticsData().label == label && n.getSemanticsData().hasAction(action)).firstOrNull;
          if (found == null) await wait(50);
        }
        expect(found, isNotNull, reason: 'no "$label" a screen reader can press; the tree says: ${said()}');
        owner().performAction(found!.id, action);
        await tester.pump();
      }

      bool stage(String name) => tester.widget<Fade>(find.byKey(Key('stage-$name'))).on;

      final store = await freshSeededStore();
      const kin = 'Rosalind Quill';
      // freshSeededStore empties the blessings, not the people: the English run left this one
      for (final x in await store.people()) {
        if (x.id == 'p_rq') await store.removePerson(x.id);
      }
      await store.addPerson(Person(id: 'p_rq', name: kin, created: DateTime.now().toUtc()));
      final lock = AppLock(api: NativeLockApi(), startUnlocked: true);
      await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: lock));
      for (var i = 0; i < 600 && find.byKey(const Key('sky')).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await wait(1500);

      // ---- New blessing, by the screen reader ----
      await press(Strings.newBlessing);
      await wait(2600);
      expect(stage('record'), isTrue, reason: 'New blessing did not open the recording screen');
      final session = tester.widget<RecordLayer>(find.byType(RecordLayer)).session;

      // ---- Begin ----
      await press(Strings.beginLabel);
      await wait(1500);
      expect(session.live, isTrue, reason: 'Begin did not start the recording');

      // ---- the ring in its first ten seconds: a double-tap asks, and nothing is thrown away ----
      await press(Strings.discardLabel);
      await wait(900);
      expect(session.sheet, isTrue, reason: 'the ring did not ask');
      expect(session.live, isTrue);
      await press(Strings.keepListening);
      await wait(700);
      expect(session.sheet, isFalse);
      expect(session.live, isTrue);

      // ---- Amen, by a double-tap, after ten seconds ----
      while (session.elapsed < 11) {
        await wait(200);
      }
      await press(Strings.amenLabel);
      await wait(2600);
      expect(stage('after'), isTrue, reason: 'Amen did not finish');
      expect(session.live, isFalse);

      // ---- Save for later: home ----
      await press(Strings.saveForLater);
      await wait(3000);
      expect(stage('home'), isTrue);

      // ---- locked: the tree is as quiet as the screen ----
      lock.lock();
      await wait(2000);
      expect(lock.locked, isTrue);
      final words = said();
      final private = <String>[
        kin,
        for (final b in sampleBlessings()) ...[
          b.title,
          if (b.from.isNotEmpty) b.from,
          if (b.recipient.isNotEmpty) b.recipient,
          ...b.tags,
          if (b.words.isNotEmpty) b.words.substring(0, b.words.length < 24 ? b.words.length : 24),
        ],
      ];
      for (final secret in private) {
        expect(words.where((w) => w.contains(secret)), isEmpty, reason: '"$secret" is in the locked home\'s semantics tree');
      }
      // and its two buttons still press
      expect(nodes().any((n) => n.getSemanticsData().label == Strings.unlock && n.getSemanticsData().hasAction(SemanticsAction.tap)), isTrue);
      await press(Strings.newBlessing);
      await wait(2600);
      expect(stage('record'), isTrue, reason: 'New blessing while locked did not open the recording screen');
      final lockedWords = said();
      for (final secret in private) {
        expect(lockedWords.where((w) => w.contains(secret)), isEmpty, reason: '"$secret" is in the locked recording screen\'s semantics tree');
      }
      // ignore: avoid_print
      print('SCREEN READER ${lang.name}: main path pressed by semantics; locked tree checked against ${private.length} private strings');
      handle.dispose();
      Strings.use(UiLanguage.english);
    });
  }
}
