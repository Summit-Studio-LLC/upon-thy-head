// Polish's light over the words, walked on the simulator with a stand-in for the phone's model
// (stand_in_model.dart: each piece answered after about two seconds). Run by
// tool/polish_light_walk.sh, which films it and sets Reduce Motion, the text size and the app's
// language inside the simulator for each run, then puts them back.
//
//   LIGHT_RUN=normal  A draft long enough for three pieces. Scroll down to "Polish the words",
//                     press it, scroll back up as a person would: piece one lit, the rest dimmed.
//                     Down to piece two while it works, then three; the finish glints, the row reads
//                     "Polished for reading", and the changes screen opens.
//   LIGHT_RUN=still   The same with Reduce Motion on: no band, a steady tint. The script sets it in
//                     the simulator; where that does not reach the app, the test sets Flutter's flag.
//   LIGHT_RUN=es-ax   The app in Spanish at the largest text size: one look while piece one works.
//
// Screenshots (SIMSHOT): ../design/sim/polish-light/.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/polish/model.dart';
import 'package:upon_thy_head/review/polish_light.dart';
import 'package:upon_thy_head/sky/astro.dart';
import 'package:upon_thy_head/strings.dart';

import 'stand_in_model.dart';
import 'support.dart';

const run = String.fromEnvironment('LIGHT_RUN', defaultValue: 'normal');

/// A Spanish blessing for the look at the largest text size (two pieces).
const walkBlessingEs =
    'Hermano Santiago, por la autoridad del santo Sacerdocio de Melquisedec que poseo, pongo mis manos sobre tu cabeza y te doy una bendición en este momento. '
    'padre celestial te conoce y te ama, y sabe de las cargas que llevas en estos días. '
    'Te bendigo para que sientas su paz en tu corazón cuando tengas miedo, y para que recuerdes los convenios que has hecho y encuentres fuerza al guardarlos. '
    'Te bendigo con paciencia contigo mismo, porque el Señor es paciente contigo y no te pide más de lo que puedes dar. '
    'Te bendigo para que las palabras de las Escrituras se abran a tu mente cuando las leas, y para que oigas su voz en ellas. '
    'Te bendigo con amigos que te levanten, y para que tú seas amigo de los que están solos, como el Salvador fue amigo de todos. '
    'Te bendigo para que tus oraciones sean oídas, y para que las respuestas lleguen en el tiempo del Señor y a su manera. '
    'Te bendigo para que seas guiado en las decisiones que tienes por delante, en tu trabajo y en tus estudios, y para que se abran puertas en los días que vienen. '
    'Te bendigo con salud del cuerpo y de la mente, para que tengas fuerza y te levantes cada mañana listo para el día. '
    'Te bendigo para que duermas en paz, y para que despiertes sabiendo que eres amado por tu familia aquí y por tu Padre Celestial. '
    'Te bendigo para que veas lo bueno de cada día, aun en los días difíciles, y para que seas agradecido por las pequeñas misericordias. '
    'Te dejo estas bendiciones, y lo hago en el nombre de Jesucristo, amén.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('polish light: $run', timeout: const Timeout(Duration(minutes: 5)), (tester) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    /// A screenshot now (the script takes it as it reads the line), then a moment for it.
    Future<void> shot(String name) async {
      debugPrint('SIMSHOT polish-light/$name');
      await wait(250);
    }

    final es = run == 'es-ax';
    debugPrint('LIGHT RUN $run: disableAnimations=${binding.platformDispatcher.accessibilityFeatures.disableAnimations} '
        'textScale=${binding.platformDispatcher.textScaleFactor} locales=${binding.platformDispatcher.locales}');
    if (run == 'still' && !binding.platformDispatcher.accessibilityFeatures.disableAnimations) {
      // the script turns Reduce Motion on inside the simulator, but on this simulator it does not
      // reach the app (as found for reduce_motion_test.dart); the same flag is set as that test does
      debugPrint('LIGHT RUN still: the simulator setting did not reach the app; using the test value');
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    expect(Strings.language, es ? UiLanguage.spanish : UiLanguage.english);

    final store = await freshSeededStore(empty: true);
    final now = DateTime.now().toUtc();
    final text = es ? walkBlessingEs : walkBlessing;
    await store.create(Blessing(
      id: 'light-walk',
      title: es ? 'Antes del nuevo trabajo' : 'Before the new job',
      from: 'Dad',
      utc: now.subtract(const Duration(days: 1)),
      utcOffset: DateTime.now().timeZoneOffset,
      place: const Place(40.76, -111.89),
      rawText: text,
      firstText: text,
      language: es ? 'es' : 'en',
    ));
    // about two seconds a piece, a little over so a person's scroll can keep up on film
    // (the Spanish run is a look at the largest text, where a person's scroll is slower: more time)
    final model = StandInModel(delay: Duration(milliseconds: es ? 12000 : 2800));
    phoneModel = model;

    await tester.pumpWidget(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock()));
    await until(() => find.byKey(const Key('to-review')).evaluate().isNotEmpty, seconds: 40, what: 'the drafts badge');
    await wait(1500);
    debugPrint('FILM START');
    await wait(800);
    await tester.tap(find.byKey(const Key('to-review')));
    await wait(2200);

    PolishLight light() => tester.widget<PolishLight>(find.byKey(const Key('review-light')));
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    /// Where in the screen the words at [offset] are.
    double yOf(int offset) {
      final words = find.byKey(const Key('review-words'));
      RenderEditable? e;
      void visit(RenderObject o) {
        if (e != null) return;
        if (o is RenderEditable) {
          e = o;
          return;
        }
        o.visitChildren(visit);
      }

      visit(tester.renderObject(words));
      final box = e!.getBoxesForSelection(TextSelection(baseOffset: offset, extentOffset: offset + 1)).first;
      return e!.localToGlobal(Offset(0, box.top)).dy;
    }

    // drags start in the page's right margin, beside the words (the left edge is the back swipe), so they scroll and never touch the text
    /// A person's drag bringing the screen's y [from] up to [to].
    Future<void> drag(double from, double to) async {
      var left = from - to;
      while (left.abs() > 4) {
        final step = left.clamp(-screenH * .55, screenH * .55);
        await tester.timedDragFrom(Offset(screenW - 14, screenH * .6), Offset(0, -step), const Duration(milliseconds: 500));
        await wait(150);
        left -= step;
      }
    }

    /// Bring the words at [offset] to near the top of the screen.
    Future<void> bring(int offset) async {
      await drag(yOf(offset), screenH * .22);
      await wait(100);
      // momentum may carry it on; correct once
      final y = yOf(offset);
      if ((y - screenH * .22).abs() > 60) await drag(y, screenH * .22);
    }

    // down to "Polish the words", as a person reads to the end of the words
    final polish = find.byKey(const Key('review-polish'));
    for (var i = 0; i < 40 && tester.getRect(polish).bottom > screenH - 120; i++) {
      await tester.timedDragFrom(Offset(screenW - 14, screenH * .6), Offset(0, -screenH * .5), const Duration(milliseconds: 900));
      await wait(500);
    }
    await wait(600);
    await tester.tap(polish);
    await wait(500);
    expect(find.byKey(const Key('review-polishing')), findsOneWidget);
    await until(() => light().at == 0, what: 'piece one');
    final pieces = light().pieces;
    debugPrint('PIECES ${pieces.length}: ${[for (final p in pieces) '${p.start}-${p.end}']}');
    if (!es) expect(pieces, hasLength(3));

    if (es) {
      // the last words dimmed, and the light beside "Puliendo…", brought up from the screen's foot
      final row = find.byKey(const Key('review-polishing'));
      await drag(tester.getRect(row).center.dy, screenH * .62);
      await wait(400);
      await shot('es-ax-01-polishing');
      // up into piece one as it works
      await drag(yOf(pieces[0].end - 120), screenH * .35);
      await wait(500);
      expect(light().at, 0);
      await shot('es-ax-02-piece-one');
      await until(() => light().at >= pieces.length, seconds: 30, what: 'the end');
      await wait(300);
      await shot('es-ax-03-finish');
      debugPrint('FILM END');
      await wait(1500);
      return;
    }

    // back up to the start of the words with a flick, as a person would: piece one lit, the rest dimmed
    await tester.flingFrom(Offset(screenW - 14, screenH * .3), Offset(0, screenH * .6), 6000);
    await wait(500);
    await drag(yOf(0), screenH * .22);
    await wait(150);
    await shot('$run-01-start');

    // on down to where piece two begins, and watch it there
    await bring(pieces[1].start - 160);
    await until(() => light().at >= 1, what: 'piece two');
    expect(light().at, 1, reason: 'the walk kept up');
    await wait(600);
    await shot('$run-02-piece-two');

    // piece three, and the finish
    await bring(pieces[2].start + 200);
    await until(() => light().at >= 3, seconds: 20, what: 'the finish');
    await wait(run == 'still' ? 420 : 300);
    await shot('$run-03-finish');
    expect(find.byKey(const Key('review-polished')), findsOneWidget);
    // the changes screen, once the glint has settled
    await wait(2000);
    await shot('$run-04-changes');
    debugPrint('FILM END');
    await wait(1500);
    debugPrint('LIGHT DONE');
  });
}
