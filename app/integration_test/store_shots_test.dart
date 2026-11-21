// The App Store screenshots: seven screens, plain, in the app's own language (English, or Spanish
// when tool/store_shots.sh has set the app's language inside the simulator). Run by
// tool/store_shots.sh, which takes the simulator's own screenshot on each SIMSHOT line.
//
// Each screen starts from a store emptied and filled with the demonstration blessings below (all
// invented), so no screen leaves anything behind for the next: a recording is discarded within its
// first ten seconds, the entry is left as a draft in a store the next screen empties, and the share
// sheet is stopped at its choices (no link is made, nothing reaches any server).
//
// The recording screen does not need the microphone to have started: the screen is live from Begin
// whatever the recorder does (record/session.dart). The review page is a draft seeded as a recording
// leaves one (the test passage's audio beside it), its small changes placed in its words as polish
// places them.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:upon_thy_head/data/audio.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/store.dart';
import 'package:upon_thy_head/main.dart';
import 'package:upon_thy_head/people/family.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/record/language_menu.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/speech.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/date_sheet.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/widgets/fade.dart';

import 'support.dart';

/// The test passage, put beside the review page's draft as its recording.
const speechAudio = String.fromEnvironment('SPEECH_AUDIO');

/// One blessing of the demonstration, in both languages.
class _Demo {
  const _Demo(this.id, this.title, this.from, this.utc, {this.words = const ['', ''], this.year = false, this.person = ''});
  final String id;
  final List<String> title, from, words;
  final DateTime utc;
  final bool year;
  final String person;
}

const _comfortEn = 'I place my hands upon your head and give you a blessing of comfort.\n\n'
    'Your Heavenly Father knows you and loves you. He has seen how tired you have been, and He wants you to know that He is near. '
    'Rest when you need to rest. Peace will come to you, a little at a time.\n\n'
    'I bless you to feel His love in quiet moments, and to remember that brighter days are ahead. '
    'I say these things in the name of Jesus Christ, amen.';
const _fatherEn = 'I place my hands upon your head and give you a father\'s blessing as this new school year begins.\n\n'
    'I bless you with a clear mind and a calm heart. When the days feel long, remember that you are loved, here at home and in heaven.\n\n'
    'I bless you to be kind to those around you, and to find joy in what you learn. In the name of Jesus Christ, amen.';
const _fatherEs = 'Pongo mis manos sobre tu cabeza y te doy una bendición de padre al comenzar este nuevo año escolar.\n\n'
    'Te bendigo con una mente clara y un corazón tranquilo. Cuando los días se sientan largos, recuerda que te amamos, aquí en casa y en el cielo.\n\n'
    'Te bendigo para que trates con bondad a quienes te rodean, y para que encuentres gozo en lo que aprendes. En el nombre de Jesucristo. Amén.';
const _comfortEs = 'Pongo mis manos sobre tu cabeza y te doy una bendición de consuelo.\n\n'
    'Tu Padre Celestial te conoce y te ama. Él ha visto tu cansancio, y quiere que sepas que está cerca de ti. '
    'Descansa cuando lo necesites. La paz llegará a ti, poco a poco.\n\n'
    'Te bendigo para que sientas Su amor en los momentos de quietud, y para que recuerdes que vienen días mejores. '
    'Digo estas cosas en el nombre de Jesucristo. Amén.';

final _demos = [
  _Demo('d-teacher', ['Set apart as a Relief Society teacher', 'Apartada como maestra de la Sociedad de Socorro'], ['Bishop Hale', 'Obispo Hale'],
      DateTime.utc(2019, 7, 2, 19), year: true),
  _Demo('d-comfort-2020', ['A blessing of comfort', 'Bendición de consuelo'], ['Dad', 'Papá'], DateTime.utc(2020, 3, 22, 2, 10)),
  _Demo('d-sick-2021', ['A blessing for the sick', 'Bendición para los enfermos'], ['Grandpa', 'Abuelo'], DateTime.utc(2021, 1, 17, 23, 30)),
  _Demo('d-leaving', ['Before leaving home', 'Antes de salir de casa'], ['Dad', 'Papá'], DateTime.utc(2022, 8, 28, 1, 15)),
  _Demo('d-comfort', ['A blessing of comfort', 'Bendición de consuelo'], ['Dad', 'Papá'], DateTime.utc(2024, 5, 12, 3, 40),
      words: [_comfortEn, _comfortEs]),
  _Demo('d-sick-2025', ['A blessing for the sick', 'Bendición para los enfermos'], ['Bishop Hale', 'Obispo Hale'], DateTime.utc(2025, 2, 9, 21, 5)),
  _Demo('d-father', ['A father\'s blessing', 'Bendición de padre'], ['Dad', 'Papá'], DateTime.utc(2026, 8, 17, 2, 20),
      words: [_fatherEn, _fatherEs]),
  // Emma's ring
  _Demo('d-emma-father', ['A father\'s blessing', 'Bendición de padre'], ['Dad', 'Papá'], DateTime.utc(2026, 8, 17, 2, 50), person: 'emma',
      words: [_fatherEn, _fatherEs]),
  _Demo('d-emma-sick', ['A blessing for the sick', 'Bendición para los enfermos'], ['Dad', 'Papá'], DateTime.utc(2025, 5, 4, 3, 0), year: true, person: 'emma',
      words: [_comfortEn, _comfortEs]),
];

/// The review page's draft: just recorded, its words as the phone wrote them, with the fillers and
/// repeated words polish takes out.
const _draftEn = (
  title: 'A blessing for the sick',
  from: 'Dad',
  raw: 'I lay my hands upon your head, um, and give you a blessing of health.\n\n'
      'Your body is, is a gift, and it will heal. I bless the doctors and, uh, the nurses who care for you, that they will be guided.\n\n'
      'I bless you with with patience and with peace while you rest. In the name of Jesus Christ, amen.',
  edits: [
    (kind: ChangeKind.filler, was: ', um,', now: ''),
    (kind: ChangeKind.repeat, was: 'is, is', now: 'is'),
    (kind: ChangeKind.filler, was: ', uh,', now: ''),
    (kind: ChangeKind.repeat, was: 'with with', now: 'with'),
  ],
);
const _draftEs = (
  title: 'Bendición para los enfermos',
  from: 'Papá',
  raw: 'Pongo mis manos sobre tu cabeza, eh, y te doy una bendición de salud.\n\n'
      'Tu cuerpo es, es un don, y sanará. Bendigo a los médicos y, este, a las enfermeras que te cuidan, para que sean guiados.\n\n'
      'Te bendigo con con paciencia y con paz mientras descansas. En el nombre de Jesucristo. Amén.',
  edits: [
    (kind: ChangeKind.filler, was: ', eh,', now: ''),
    (kind: ChangeKind.repeat, was: 'es, es', now: 'es'),
    (kind: ChangeKind.filler, was: ', este,', now: ''),
    (kind: ChangeKind.repeat, was: 'con con', now: 'con'),
  ],
);

/// The entry page: a blessing Emma was given as a little girl, its words pasted from a written copy.
const _entryEn = (
  title: 'A blessing of comfort',
  from: 'Grandpa',
  tag: 'Comfort',
  words: 'Emma, I place my hands upon your head and give you a blessing of comfort.\n\n'
      'Your Heavenly Father loves you. He knows that you miss your friends, and He will help you feel at home in your new school.\n\n'
      'I bless you with peace tonight and with a happy heart tomorrow. In the name of Jesus Christ, amen.',
);
const _entryEs = (
  title: 'Bendición de consuelo',
  from: 'Abuelo',
  tag: 'Consuelo',
  words: 'Emma, pongo mis manos sobre tu cabeza y te doy una bendición de consuelo.\n\n'
      'Tu Padre Celestial te ama. Él sabe que extrañas a tus amigos, y te ayudará a sentirte en casa en tu nueva escuela.\n\n'
      'Te bendigo con paz esta noche y con un corazón alegre mañana. En el nombre de Jesucristo. Amén.',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store screenshots', timeout: const Timeout(Duration(minutes: 12)), (t) async {
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, {int seconds = 30, required String what}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await wait(900);
      debugPrint('SIMSHOT $name');
      await wait(1500);
    }

    Future<void> tap(String key, {int settle = 1200}) async {
      await t.tap(find.byKey(Key(key)).hitTestable().first);
      await wait(settle);
    }

    bool stage(String name) => t.widget<Fade>(find.byKey(Key('stage-$name'))).on;

    // ---- the language and the device, as main() sets them ----
    Strings.iPad = Strings.detectIPad();
    Strings.use(UiLanguage.forLocales(binding.platformDispatcher.locales));
    final es = Strings.language == UiLanguage.spanish ? 1 : 0;
    debugPrint('STORE SHOTS ${Strings.language.name}, ${Strings.iPad ? 'iPad' : 'iPhone'}');
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    await NativeSpeech.instance.debugFeed(null);

    final made = DateTime.utc(2026, 11, 1);
    late BlessingStore store;

    /// The store emptied and filled with the demonstration; the app on it, on the sky.
    Future<void> open({Blessing? extra}) async {
      await t.pumpWidget(const SizedBox());
      await wait(300);
      store = await freshSeededStore(empty: true);
      for (final x in await store.people()) {
        await store.removePerson(x.id);
      }
      for (final l in await store.links()) {
        await store.removeLink(l.id);
      }
      await store.addPerson(Person(id: 'emma', name: 'Emma', born: const Day(2014, 4, 9), created: made));
      for (final d in _demos) {
        await store.create(Blessing(
          id: d.id,
          title: d.title[es],
          from: d.from[es],
          utc: d.utc,
          utcOffset: const Duration(hours: -6),
          place: samplePlace,
          personId: d.person,
          rawText: d.words[es],
          draft: false,
          language: es == 1 ? 'es' : 'en',
          precision: d.year ? DatePrecision.year : DatePrecision.day,
          entered: d.year,
          created: made,
          updated: made,
        ));
      }
      if (extra != null) await store.create(extra);
      await t.pumpWidget(glassScope(UponThyHeadApp(store: store, stats: false, demo: false, lock: unlockedLock())));
      final sky = find.byKey(const Key('sky'));
      await until(() => sky.evaluate().isNotEmpty, what: 'the sky');
      await wait(1500);
      // the app remembers the ring last shown (an entry for Emma turns to hers): mine
      await tap('sky-switch', settle: 1000);
      await tap('pull-down-${SkyMenu.me}', settle: 2400);
    }

    // ---- 1. home ----
    await open();
    await shot('01-home');

    // ---- 2. recording, listening ----
    RecordSession session() => t.widget<RecordLayer>(find.byType(RecordLayer)).session;
    await tap('new', settle: 2600);
    expect(stage('record'), isTrue);
    await until(() => session().permissions != null, what: 'permissions');
    expect(session().permissions!.allGranted, isTrue, reason: 'tool/sim_permissions.sh grant');
    t.state<LanguageControlState>(find.byKey(const Key('language'))).debugPick(es == 1 ? SpeechLanguage.spanish : SpeechLanguage.english);
    await wait(500);
    await t.tap(find.byKey(const Key('begin')));
    await until(() => session().live, seconds: 3, what: 'Begin');
    await until(() => session().elapsed >= 4, what: 'four seconds');
    await shot('02-recording');
    // within the first ten seconds the ring discards: nothing is kept
    if (session().elapsed < 8.5) {
      final g = await t.startGesture(t.getCenter(find.byKey(const Key('hold'))));
      await wait(1100);
      await g.up();
      await wait(800);
    }
    if (session().live) session().discard();
    await wait(800);

    // ---- 3. review: a draft just recorded, polished, its changes undoable ----
    final dr = es == 1 ? _draftEs : _draftEn;
    final audioDir = await defaultAudioDir();
    Directory(audioDir).createSync(recursive: true);
    var audioName = '';
    if (speechAudio.isNotEmpty && File('$speechAudio/${es == 1 ? 'es' : 'en'}.m4a').existsSync()) {
      audioName = 'd-draft.m4a';
      File('$speechAudio/${es == 1 ? 'es' : 'en'}.m4a').copySync(p.join(audioDir, audioName));
    }
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    await open(
        extra: Blessing(
      id: 'd-draft',
      title: dr.title,
      from: dr.from,
      utc: now,
      utcOffset: DateTime.now().timeZoneOffset,
      place: samplePlace,
      personId: 'emma',
      recipient: 'Emma',
      tags: [es == 1 ? 'Sanación' : 'Healing'],
      rawText: dr.raw,
      firstText: dr.raw,
      changes: locateChanges(dr.raw, dr.edits, source: 'rules'),
      polishAsked: true,
      draft: true,
      audio: audioName,
      language: es == 1 ? 'es' : 'en',
      created: now,
      updated: now,
    ));
    // the draft is on Emma's ring: her sky, then its "to review"
    await tap('sky-switch', settle: 1000);
    await tap('pull-down-${SkyMenu.person('emma')}', settle: 2400);
    await tap('to-review', settle: 2600);
    expect(stage('review'), isTrue);
    final polished = find.byKey(const Key('review-polished'));
    await until(() => polished.evaluate().isNotEmpty, what: 'the polished row');
    await Scrollable.ensureVisible(t.element(polished), alignment: .92);
    // a little lower, so the title is not under the top bar's fade
    final rs = t.state<ScrollableState>(find.descendant(of: find.byKey(const Key('review-scroll')), matching: find.byType(Scrollable)).first).position;
    rs.jumpTo((rs.pixels - 40).clamp(0, rs.maxScrollExtent));
    await wait(400);
    // a title that wraps (Spanish) needs more: its top clear of the bar, the polished row still in view
    final title = find.byKey(const Key('review-title'));
    if (title.evaluate().isNotEmpty) {
      final top = t.getTopLeft(title.first).dy;
      final clear = MediaQuery.of(t.element(polished)).padding.top + 70;
      final room = MediaQuery.of(t.element(polished)).size.height - t.getBottomLeft(polished).dy - 8;
      if (top < clear) {
        rs.jumpTo((rs.pixels - (clear - top).clamp(0, room)).clamp(0, rs.maxScrollExtent));
      }
    }
    await wait(800);
    await shot('03-review');

    // ---- 4. reading a blessing of comfort ----
    await open();
    if (!stage('list')) await tap('list', settle: 1600);
    final row = find.byKey(const Key('row-d-comfort'));
    await t.ensureVisible(row);
    await wait(600);
    await t.tap(row);
    await wait(2600);
    expect(stage('read'), isTrue);
    await shot('04-reading');

    // ---- 5. family: the glass menu open ----
    await open();
    await tap('sky-switch', settle: 1400);
    expect(find.byKey(Key('pull-down-${SkyMenu.person('emma')}')), findsOneWidget);
    await shot('05-family');

    // ---- 6. entering a past blessing: year only, who gave it, the words pasted ----
    await open();
    final en = es == 1 ? _entryEs : _entryEn;
    await tap('new', settle: 2200);
    await until(() => find.byKey(const Key('enter-past')).hitTestable().evaluate().isNotEmpty, what: 'Enter a past blessing');
    await tap('enter-past', settle: 2000);
    expect(stage('review'), isTrue);
    Future<void> type(String key, String value) async {
      final f = find.byKey(Key(key));
      await Scrollable.ensureVisible(t.element(f), alignment: .4);
      await wait(300);
      await t.tap(f);
      await wait(400);
      final field = find.descendant(of: f, matching: find.byType(EditableText));
      await t.enterText(field.evaluate().isEmpty ? f : field, value);
      await wait(500);
    }

    await type('review-title', en.title);
    await type('review-from', en.from);
    await type('review-for', 'Emma');
    final emma = find.byKey(const Key('review-person-emma'));
    await Scrollable.ensureVisible(t.element(emma), alignment: .5);
    await wait(300);
    await t.tap(emma);
    await wait(700);
    await type('review-tag', '${en.tag},');
    await type('review-words', en.words);
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(800);
    // the date: year only, 2019
    final given = find.byKey(const Key('review-given-row'));
    await Scrollable.ensureVisible(t.element(given), alignment: .3);
    await wait(400);
    await tap('review-given-row', settle: 900);
    await tap('precision-${DatePrecision.year.code}', settle: 700);
    DateSheetState sheet() => t.state<DateSheetState>(find.byType(DateSheet));
    for (var i = 0; i < 8 && sheet().choice.year != 2019; i++) {
      final extent = t.widget<CupertinoPicker>(find.byKey(const Key('wheel-year'))).itemExtent;
      final step = (sheet().choice.year - 2019).clamp(-12, 12);
      await t.timedDrag(find.byKey(const Key('wheel-year')), Offset(0, step * extent), Duration(milliseconds: (step.abs() * extent * 25).round()));
      await wait(900);
    }
    expect(sheet().choice.year, 2019);
    await tap('date-done', settle: 1500);
    final scroll = find.descendant(of: find.byKey(const Key('review-scroll')), matching: find.byType(Scrollable)).first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await wait(900);
    await shot('06-entry');

    // ---- 7. sharing: the choices, stopped there ----
    await open();
    // the app remembers the list being open
    if (!stage('list')) await tap('list', settle: 1600);
    final fatherRow = find.byKey(const Key('row-d-father'));
    await t.ensureVisible(fatherRow);
    await wait(600);
    await t.tap(fatherRow);
    await wait(2600);
    expect(stage('read'), isTrue);
    expect(find.byKey(const Key('read-no-words')), findsNothing);
    await tap('read-share', settle: 1400);
    await until(() => find.byKey(const Key('share-choose')).evaluate().isNotEmpty, what: 'the share choices');
    await shot('07-sharing');
    debugPrint('STORE SHOTS DONE');
  });
}
