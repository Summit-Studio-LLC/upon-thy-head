// Every custom control pressed as VoiceOver and TalkBack press it: a double-tap sends the node's tap
// action through the semantics tree, never a touch. Before 2026-11-18 most of the app's own buttons
// (PillBtn among them) were labelled for VoiceOver but hid their tap from it, so they had no action
// to send. In English and Spanish.
//
//   flutter test test/screen_reader_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/data/settings.dart';
import 'package:upon_thy_head/home/home_screen.dart';
import 'package:upon_thy_head/home/ruler.dart';
import 'package:upon_thy_head/home/timeline.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/onboarding/first_run.dart';
import 'package:upon_thy_head/onboarding/first_run_screens.dart';
import 'package:upon_thy_head/people/family_pages.dart';
import 'package:upon_thy_head/people/person.dart';
import 'package:upon_thy_head/place/where.dart';
import 'package:upon_thy_head/polish/changes_screen.dart';
import 'package:upon_thy_head/read/read_screen.dart';
import 'package:upon_thy_head/record/record_screen.dart';
import 'package:upon_thy_head/record/session.dart';
import 'package:upon_thy_head/record/transcriber.dart';
import 'package:upon_thy_head/review/player.dart';
import 'package:upon_thy_head/review/review_screen.dart';
import 'package:upon_thy_head/settings/settings_screen.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/share/share_sheet.dart';
import 'package:upon_thy_head/sky/placement.dart';
import 'package:upon_thy_head/strings.dart';
import 'package:upon_thy_head/theme.dart';
import 'package:upon_thy_head/widgets/buttons.dart';
import 'package:upon_thy_head/widgets/icons.dart';
import 'package:upon_thy_head/widgets/over_sky_page.dart';
import 'package:upon_thy_head/widgets/sheet.dart';

import 'first_run_test.dart' show FakeAsker;
import 'lock_place_test.dart' show FakeLocator;
import 'support/semantics.dart';

const p = Palette.lamplight;

Future<void> show(WidgetTester t, Widget child, {bool settle = true}) async {
  t.view.physicalSize = const Size(402, 874) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: const MediaQueryData(size: Size(402, 874), devicePixelRatio: 3, padding: EdgeInsets.only(top: 62), viewPadding: EdgeInsets.only(top: 62)),
    child: CupertinoApp(
      localizationsDelegates: const [m.DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      home: ColoredBox(color: p.ground, child: child),
    ),
  ));
  if (settle) {
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  } else {
    await t.pump();
  }
}

class FakePlayer extends Player {
  double pos = 0;
  bool on = false;
  final List<String> did = [];
  @override
  double get position => pos;
  @override
  double get duration => 60;
  @override
  bool get playing => on;
  @override
  Future<void> load(String path) async {}
  @override
  Future<void> play() async {
    did.add('play');
    on = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    did.add('pause');
    on = false;
    notifyListeners();
  }

  @override
  Future<void> seek(double seconds) async {
    did.add('seek ${seconds.round()}');
    pos = seconds;
    notifyListeners();
  }

  @override
  Future<void> unload() async {}
}

class FakeShare implements ShareApi {
  final List<String> did = [];
  @override
  Future<void> text(String text, String subject) async => did.add('text');
  @override
  Future<void> pdf(Map<String, Object> pdf) async => did.add('pdf');
  @override
  Future<bool> file(String fileName, Uint8List bytes, String title) async {
    did.add('file');
    return false;
  }

  @override
  Future<bool> link(String url, String title) async => false;
  @override
  Future<List<IncomingFile>> receiving(void Function(IncomingFile) onIncoming) async => const [];
  @override
  Future<void> dismiss() async {}
  @override
  Future<void> clean() async {}
}

Blessing surgery() => sampleBlessings().firstWhere((b) => b.id == 'surgery');

void main() {
  late SemanticsHandle handle;
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('screen_reader');
  });
  tearDown(() {
    Strings.use(UiLanguage.english);
    dir.deleteSync(recursive: true);
  });

  for (final lang in UiLanguage.values) {
    group(lang.name, () {
      setUp(() => Strings.use(lang));

      testWidgets('the shared buttons: PillBtn, TextBtn, LightTextBtn, IconBtn, OpenRow', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        await show(
            t,
            Column(children: [
              PillBtn(label: Strings.continueLabel, palette: p, kind: PillKind.primary, onTap: () => pressed.add('pill')),
              PillBtn(label: Strings.notNow, palette: p, kind: PillKind.quiet, enabled: false, onTap: null),
              TextBtn(label: Strings.close, palette: p, onTap: () => pressed.add('text')),
              LightTextBtn(label: Strings.done, palette: p, onTap: () => pressed.add('light')),
              IconBtn(icon: Glyph.more, color: p.ink, palette: p, semantics: Strings.more, onTap: () => pressed.add('icon')),
              IconBtn(icon: Glyph.older, color: p.ink, palette: p, semantics: Strings.earlier, onTap: null),
              OpenRow(palette: p, semantics: Strings.yourLinks, onTap: () => pressed.add('row'), child: const SizedBox(height: 44)),
            ]));
        await activate(t, Strings.continueLabel);
        await activate(t, Strings.close);
        await activate(t, Strings.done);
        await activate(t, Strings.more);
        await activate(t, Strings.yourLinks);
        expect(pressed, ['pill', 'text', 'light', 'icon', 'row']);
        // the dimmed ones are said to be unavailable, and do nothing
        expect(nodeLabelled(t, Strings.notNow).getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);
        expect(nodeLabelled(t, Strings.earlier).getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);
        expect(unpressable(t), isEmpty);
        handle.dispose();
      });

      testWidgets('the home: New blessing, Unlock, the drafts badge, the ruler', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        final picked = <int>[];
        final bs = sampleBlessings();
        await show(
            t,
            Column(children: [
              NewBlessingButton(palette: p, onTap: () => pressed.add('new')),
              UnlockButton(palette: p, onTap: () => pressed.add('unlock')),
              ReviewBadge(palette: p, count: 2, onTap: () => pressed.add('review')),
              SizedBox(
                width: 300,
                child: Ruler(blessings: bs, focus: 2, palette: p, now: DateTime(2026, 11, 18), onPick: (i, {required fresh}) => picked.add(i)),
              ),
            ]));
        await activate(t, Strings.newBlessing);
        await activate(t, Strings.unlock);
        await activate(t, Strings.toReviewLabel(2));
        expect(pressed, ['new', 'unlock', 'review']);
        // the ruler is a slider: its value is the blessing in focus, and a swipe up or down turns
        final ruler = nodeLabelled(t, Strings.rulerLabel);
        expect(ruler.getSemanticsData().flagsCollection.isSlider, isTrue);
        expect(ruler.getSemanticsData().value, '${bs[2].longDate}. ${bs[2].shownTitle}');
        await activate(t, Strings.rulerLabel, action: SemanticsAction.increase);
        await activate(t, Strings.rulerLabel, action: SemanticsAction.decrease);
        expect(picked, [3, 1]);
        expect(unpressable(t), isEmpty);
        handle.dispose();
      });

      testWidgets('the list: each row opens its blessing', (t) async {
        handle = t.ensureSemantics();
        final opened = <int>[];
        final bs = sampleBlessings();
        await show(t, Timeline(blessings: bs, palette: p, now: DateTime(2026, 11, 18), on: true, onOpen: opened.add));
        await activate(t, RegExp('^${RegExp.escape(bs.last.longDate)}'));
        expect(opened, [bs.length - 1]);
        expect(unpressable(t), isEmpty);
        handle.dispose();
      });

      testWidgets('recording: Begin, Close, then the ring (Discard asks first; Amen finishes)', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        final s = RecordSession(recorder: SilentRecorder(), audioDir: '${dir.path}/audio')..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
        await t.runAsync(() => s.checkPermissions(ask: false));
        Widget layer() => RecordLayer(
              palette: p,
              session: s,
              active: false,
              onBegin: () => pressed.add('begin'),
              onClose: () => pressed.add('close'),
              onDiscardEarly: () => pressed.add('discard'),
              onAmen: () => pressed.add('amen'),
              onLanguage: (_) {},
              onOpenSettings: () {},
            );
        await show(t, layer());
        expect(unpressable(t), isEmpty);
        await activate(t, Strings.beginLabel);
        await activate(t, Strings.close);
        expect(pressed, ['begin', 'close']);
        await t.runAsync(() => s.begin());
        for (var i = 0; i < 30; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        // the first ten seconds: a double-tap on the ring asks before anything is thrown away
        await activate(t, Strings.discardLabel);
        expect(s.sheet, isTrue);
        expect(pressed, ['begin', 'close'], reason: 'nothing discarded on a double-tap');
        await t.pump(const Duration(seconds: 1));
        await activate(t, Strings.keepListening);
        expect(s.sheet, isFalse);
        // TalkBack's double-tap-and-hold is the hold itself
        await activate(t, Strings.discardLabel, action: SemanticsAction.longPress);
        expect(pressed.last, 'discard');
        expect(unpressable(t), isEmpty);
        await t.runAsync(() async {
          s.discard();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpWidget(const SizedBox());
        s.dispose();
        // Amen (the ring after ten seconds; a practice has it from the start): a double-tap finishes
        final practice = RecordSession(recorder: SilentRecorder(), practice: true, audioDir: '${dir.path}/practice')
          ..draft = draftBlessing(DateTime.now(), place: saltLakeTemple);
        await t.runAsync(() async {
          await practice.checkPermissions(ask: false);
          await practice.begin();
        });
        await show(
            t,
            RecordLayer(
              palette: p,
              session: practice,
              active: false,
              practice: true,
              onBegin: () {},
              onClose: () {},
              onDiscardEarly: () => pressed.add('discard'),
              onAmen: () => pressed.add('amen'),
              onLanguage: (_) {},
              onOpenSettings: () {},
            ));
        await activate(t, Strings.amenLabel);
        expect(pressed.last, 'amen');
        expect(nodeLabelled(t, Strings.amenLabel).getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
        expect(unpressable(t), isEmpty);
        await t.runAsync(() async {
          practice.discard();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpWidget(const SizedBox());
        practice.dispose();
        handle.dispose();
      });

      testWidgets('first run: the opening, Continue, Allow, Settings, and the later steps', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        await show(t, OpeningLayer(palette: p, onTap: () => pressed.add('opening')));
        await activate(t, Strings.appName);
        await show(t, WelcomeLayer(palette: p, onContinue: () => pressed.add('welcome')));
        await activate(t, Strings.continueLabel);
        final settings = await t.runAsync(() => Settings.open('${dir.path}/settings.json'));
        final a = FakeAsker();
        final perms = FirstRunPermissions(asker: a, settings: settings!);
        await t.runAsync(perms.load);
        await show(t, PermissionsLayer(palette: p, state: perms, onContinue: () => pressed.add('permissions')));
        expect(unpressable(t), isEmpty);
        await t.runAsync(() async {
          await activate(t, Strings.allowFor(perms.row(PermissionKind.microphone)!.title));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        expect(a.asked, ['microphone']);
        await t.pump(const Duration(seconds: 1));
        await t.runAsync(() async {
          await activate(t, Strings.allowFor(perms.row(PermissionKind.speech)!.title));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await activate(t, Strings.continueLabel);
        await show(t, RehearsalAskLayer(palette: p, onTry: () => pressed.add('try'), onNotNow: () => pressed.add('not now')));
        await pressEach(t, () => show(t, RehearsalAskLayer(palette: p, onTry: () => pressed.add('try'), onNotNow: () => pressed.add('not now'))));
        await pressEach(t, () => show(t, ModelAskLayer(palette: p, onNext: () => pressed.add('model'))));
        await pressEach(t, () => show(t, SharedLineLayer(palette: p, onContinue: () => pressed.add('shared line'))));
        await pressEach(t, () => show(t, SharedPreviewLayer(palette: p, blessing: surgery(), onKeep: () => pressed.add('keep'), onNotNow: () => pressed.add('shared not now'))));
        expect(pressed, containsAll(['opening', 'welcome', 'permissions', 'try', 'not now', 'model', 'shared line', 'keep', 'shared not now']));
        // a refused row offers Settings, pressable too
        final refused = FakeAsker(mic: Permission.denied);
        final perms2 = FirstRunPermissions(asker: refused, settings: settings);
        await t.runAsync(perms2.load);
        await show(t, PermissionsLayer(palette: p, state: perms2, onContinue: () {}));
        await t.runAsync(() async {
          await activate(t, Strings.settingsFor(perms2.row(PermissionKind.microphone)!.title));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        expect(refused.settingsOpened, 1);
        handle.dispose();
      });

      testWidgets('a sheet\'s two buttons', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        await show(
            t,
            ConfirmSheet(
              palette: p,
              on: true,
              title: Strings.discardTitle,
              body: Strings.discardBody,
              dangerLabel: Strings.discard,
              safeLabel: Strings.keepListening,
              onDanger: () => pressed.add('danger'),
              onSafe: () => pressed.add('safe'),
            ));
        await activate(t, Strings.discard);
        await activate(t, Strings.keepListening);
        expect(pressed, ['danger', 'safe']);
        handle.dispose();
      });

      testWidgets('reading: Back, Share, Edit, Delete; the share sheet\'s rows', (t) async {
        handle = t.ensureSemantics();
        final pressed = <String>[];
        final share = FakeShare();
        Future<void> read() => show(
            t,
            ReadLayer(
              palette: p,
              blessing: surgery(),
              placement: const OverheadPlacement(),
              on: true,
              onBack: () => pressed.add('back'),
              onReview: () => pressed.add('review'),
              onDelete: () async {
                pressed.add('delete');
                return false;
              },
              onChanges: () => pressed.add('changes'),
              share: share,
            ));
        await read();
        expect(unpressable(t), isEmpty);
        final all = await pressEach(t, read);
        expect(all, containsAll([Strings.back, Strings.share]));
        expect(pressed, containsAll(['back', 'review']));
        // the share sheet: its rows each do their one thing
        await read();
        await activate(t, Strings.share);
        await t.pump(const Duration(seconds: 1));
        expect(unpressable(t), isEmpty);
        await t.runAsync(() async {
          await activate(t, Strings.textChip);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        expect(share.did, contains('text'));
        handle.dispose();
      });

      testWidgets('the share sheet on its own: every button', (t) async {
        handle = t.ensureSemantics();
        final share = FakeShare();
        var closed = 0;
        Future<void> sheet() =>
            show(t, ShareSheet(palette: p, on: true, blessing: surgery(), share: share, links: null, onClose: () => closed++, onSent: (_, _) {}));
        await sheet();
        expect(unpressable(t), isEmpty);
        await t.runAsync(() async {
          await pressEach(t, sheet);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        expect(share.did, isNotEmpty);
        handle.dispose();
      });

      testWidgets('review: the chips, the polished row, the listen bar', (t) async {
        handle = t.ensureSemantics();
        final player = FakePlayer();
        final b = surgery()..draft = true;
        final pressed = <String>[];
        Future<void> review() => show(
            t,
            ReviewLayer(
              palette: p,
              blessing: b,
              on: true,
              player: player,
              audioPath: '${dir.path}/a.m4a',
              knownTags: const ['healing', 'family'],
              onSave: () async {},
              onBack: () => pressed.add('back'),
              onFinish: () => pressed.add('finish'),
              onChanges: () => pressed.add('changes'),
              onOwnership: (_) {},
            ));
        await review();
        expect(unpressable(t), isEmpty);
        await activate(t, Strings.play);
        expect(player.did, contains('play'));
        await activate(t, Strings.back10);
        expect(player.did.last, startsWith('seek'));
        final all = await pressEach(t, review);
        expect(all, containsAll([Strings.removeTag('Comfort'), Strings.done]));
        expect(pressed, contains('back'));
        // the listen bar on its own: the seek line is a slider
        await show(t, ListenBar(palette: p, player: player..pos = 20));
        await activate(t, Strings.playbackPosition, action: SemanticsAction.increase);
        expect(player.did.last, 'seek 30');
        handle.dispose();
      });

      testWidgets('the changes page: Restore all / Keep all', (t) async {
        handle = t.ensureSemantics();
        final b = surgery();
        await show(t, ChangesLayer(palette: p, blessing: b, on: true, onSave: () async {}, onDone: () {}));
        expect(unpressable(t), isEmpty);
        final before = b.changes.where((c) => c.kept).length;
        await activate(t, Strings.restoreAll);
        await t.pump(const Duration(seconds: 1));
        expect(b.changes.where((c) => c.kept).length, lessThan(before));
        handle.dispose();
      });

      testWidgets('Settings: the switch, the words, the language', (t) async {
        handle = t.ensureSemantics();
        final settings = await t.runAsync(() => Settings.open('${dir.path}/settings.json'));
        final lock = AppLock(api: NoLockApi(methodIs: LockMethod.faceId));
        await t.runAsync(() => lock.init(settings!, unlocked: true));
        final where = BlessingPlace(settings: settings!, locator: FakeLocator(LocationStatus.granted));
        final pressed = <String>[];
        Future<void> page() => show(
            t,
            SettingsLayer(
              palette: p,
              lock: lock,
              where: where,
              language: null,
              version: '1.0',
              onBack: () => pressed.add('back'),
              onLock: (on) => pressed.add('lock $on'),
              onLanguage: (_) {},
              onUseLocation: () => pressed.add('location'),
              onPassAlong: () => pressed.add('pass along'),
              onYourLinks: () => pressed.add('links'),
            ));
        await page();
        expect(unpressable(t), isEmpty);
        await pressEach(t, page);
        expect(pressed, containsAll(['back', 'lock false', 'pass along', 'links']));
        handle.dispose();
      });

      testWidgets('family pages: the rows and buttons', (t) async {
        handle = t.ensureSemantics();
        final emma = Person(id: 'e', name: 'Emma', born: Day(2008, 8, 3), created: DateTime.utc(2026));
        final pressed = <String>[];
        Future<void> family() => show(
            t,
            FamilyLayer(
                palette: p, people: [emma], countLine: (_) => Strings.countLine(2, DateTime(2008, 8)), onBack: () => pressed.add('back'), onOpen: (_) => pressed.add('open'), onAdd: () => pressed.add('add')));
        await family();
        expect(unpressable(t), isEmpty);
        await pressEach(t, family);
        expect(pressed, containsAll(['back', 'open', 'add']));
        Future<void> person() => show(
            t,
            PersonLayer(
                palette: p, on: true, person: emma, blessings: 2, countLine: 'x', onBack: () => pressed.add('person back'), onSave: (_, _) {}, onRemove: () async {
              pressed.add('remove');
              return false;
            }));
        await person();
        expect(unpressable(t), isEmpty);
        await pressEach(t, person);
        expect(pressed, containsAll(['person back']));
        handle.dispose();
      });
    });
  }
}
