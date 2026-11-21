import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/polish/model.dart';
import 'package:upon_thy_head/polish/model_check.dart';
import 'package:upon_thy_head/polish/polish.dart';
import 'package:upon_thy_head/sky/astro.dart';

/// A stand-in for the phone's model: answers each piece with [answer].
class FakeModel implements PhoneModel {
  FakeModel(this.answer, {this.isReady = true, this.delay = Duration.zero});
  final String? Function(String text) answer;
  final bool isReady;
  final Duration delay;
  final asked = <String>[];
  final cancelled = <String>[];
  String? lastInstructions;

  @override
  Future<bool> ready(String language) async => isReady;

  @override
  Future<String?> polish(String text, {required String language, required String instructions, required String id}) async {
    asked.add(text);
    lastInstructions = instructions;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return answer(text);
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}

List<Change> check(String spoken, String answer, {String lang = 'en', Set<String> names = const {}}) => ModelCheck.changes(spoken, answer, language: lang, names: names);

String applied(String spoken, List<Change> cs) => applyChanges(spoken, cs);

/// The result differs from [spoken] only in the allowed ways: the same number of words, each the
/// same apart from capitals, or one word for one word that the check allows; never a scripture
/// word or a number changed.
void expectOnlyAllowed(String spoken, String result, {String lang = 'en'}) {
  final a = wordsOf(spoken), b = wordsOf(result);
  expect(b.length, a.length, reason: 'words added or left out: "$result"');
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) continue;
    expect(ModelCheck.isScripture(a[i], lang), isFalse, reason: 'scripture word "${a[i]}" changed');
    expect(ModelCheck.isNumber(a[i]) || ModelCheck.isNumber(b[i]), isFalse, reason: 'a number changed');
  }
  final changedWords = [
    for (var i = 0; i < a.length; i++)
      if (a[i] != b[i]) i,
  ];
  expect(changedWords.length, lessThanOrEqualTo((a.length * .2).ceil()));
}

void main() {
  const spoken =
      'brother james i lay my hands upon thy head and bless thee with peace '
      'the lord knows there needs and he will comfort thee in the days ahead';

  group('the check keeps', () {
    test('punctuation and capitals only', () {
      const answer =
          'Brother James, I lay my hands upon thy head and bless thee with peace. '
          'The Lord knows there needs, and He will comfort thee in the days ahead.';
      final cs = check(spoken, answer, names: {'James'});
      expect(cs, isNotEmpty);
      expect(cs.every((c) => c.kind == ChangeKind.punctuation), isTrue);
      expect(cs.every((c) => c.size == ChangeSize.light), isTrue);
      final r = applied(spoken, cs);
      expect(r, answer);
      expectOnlyAllowed(spoken, r);
    });

    test('a paragraph break, made a blank line', () {
      const s = 'I bless you with peace. And I bless you with strength.';
      final cs = check(s, 'I bless you with peace.\nAnd I bless you with strength.');
      expect(cs, hasLength(1));
      expect(cs.single.now, 'peace.\n\nAnd');
      expect(cs.single.size, ChangeSize.light);
      expect(applied(s, cs), 'I bless you with peace.\n\nAnd I bless you with strength.');
    });

    test('"there" for "their": one word, the next size up', () {
      final cs = check(spoken, spoken.replaceFirst('there needs', 'their needs'));
      expect(cs, hasLength(1));
      expect(cs.single.was, 'there');
      expect(cs.single.now, 'their');
      expect(cs.single.kind, ChangeKind.grammar);
      expect(cs.single.size, ChangeSize.moderate);
    });

    test('a name spelled as the details spell it', () {
      const s = 'Sister Katherine, I bless you.';
      final cs = check(s, 'Sister Kathryn, I bless you.', names: {'Kathryn'});
      expect(cs.single.now, 'Kathryn');
      expect(check(s, 'Sister Margaret, I bless you.', names: {'Kathryn'}), isEmpty);
      expect(check(s, 'Sister Kathryn, I bless you.'), isEmpty, reason: 'no such name in the details');
    });

    test('Spanish: accents and opening marks', () {
      const s = 'hermana ana te bendigo con paz como esta tu corazon hoy';
      const answer = 'Hermana Ana, te bendigo con paz. ¿Cómo está tu corazón hoy?';
      final cs = check(s, answer, lang: 'es', names: {'Ana'});
      final r = applied(s, cs);
      expect(r, answer);
      expectOnlyAllowed(s, r.replaceAll('ó', 'o').replaceAll('á', 'a'), lang: 'es');
    });

    test('Spanish: vosotros forms come through', () {
      const s = 'os bendigo para que seais fuertes y vosotros tendreis paz';
      final cs = check(s, 'Os bendigo para que seáis fuertes, y vosotros tendréis paz.', lang: 'es');
      expect(applied(s, cs), 'Os bendigo para que seáis fuertes, y vosotros tendréis paz.');
      // but never made modern
      final modern = check(s, 'Los bendigo para que sean fuertes, y ustedes tendrán paz.', lang: 'es');
      final r = applied(s, modern);
      expect(r, isNot(contains('ustedes')));
      expect(r, isNot(contains('sean')));
      expect(r, isNot(contains('tendrán')));
    });

    test('an introduction line and a note are taken off', () {
      const s = 'I bless you with peace and I bless you with strength';
      final cs = check(s, 'Here is the corrected text:\n\nI bless you with peace, and I bless you with strength.\n\nNote: I added punctuation.');
      expect(applied(s, cs), 'I bless you with peace, and I bless you with strength.');
      final quoted = check(s, 'Sure! Here is the text: "I bless you with peace, and I bless you with strength."');
      expect(applied(s, quoted), 'I bless you with peace, and I bless you with strength.');
    });
  });

  group('the check drops', () {
    test('"thee" made "you"', () {
      final cs = check(spoken, spoken.replaceFirst('bless thee', 'bless you'));
      expect(cs, isEmpty);
      final archaic = check('I bless you with peace', 'I bless thee with peace');
      expect(archaic, isEmpty);
    });

    test('every scripture word, though the rest is kept', () {
      const s = 'thou art blessed and thou shalt have peace unto the end';
      final cs = check(s, 'You are blessed, and you will have peace until the end.');
      final r = applied(s, cs);
      expect(wordsOf(r), wordsOf(s));
    });

    test('a sentence reworded', () {
      const s = 'I bless you that you will feel the comfort of the spirit each day.';
      final cs = check(s, 'I bless you to feel comforted by the Spirit every single day.');
      final r = applied(s, cs);
      expectOnlyAllowed(s, r);
      expect(wordsOf(r), wordsOf(s).map((w) => w).toList());
    });

    test('a sentence added at the end', () {
      const s = 'I bless you with peace and with strength';
      final cs = check(s, 'I bless you with peace and with strength. May God be with you always.');
      final r = applied(s, cs);
      expect(wordsOf(r), wordsOf(s));
      expectOnlyAllowed(s, r);
    });

    test('words left out', () {
      const s = 'I bless you that you may that you may know the Lord loves you';
      final cs = check(s, 'I bless you that you may know the Lord loves you.');
      final r = applied(s, cs);
      expect(wordsOf(r), wordsOf(s));
    });

    test('words moved', () {
      const s = 'with peace and strength I bless you';
      final r = applied(s, check(s, 'I bless you with peace and strength.'));
      expect(wordsOf(r), wordsOf(s));
    });

    test('a phrase for a phrase', () {
      const s = 'and I say these things in the name of Jesus Christ amen';
      final r = applied(s, check(s, 'And I say these words in the holy name of Jesus Christ. Amen.'));
      expectOnlyAllowed(s, r);
      expect(r, isNot(contains('holy')));
    });

    test('a number changed', () {
      const s = 'you will serve for two years in a far land';
      expect(check(s, 'You will serve for three years in a far land.').where((c) => c.now.contains('three')), isEmpty);
      expect(check('you are 12 years old', 'You are 13 years old.').where((c) => c.now.contains('13')), isEmpty);
      expect(check('I bless you to go to the temple', 'I bless you to go two the temple.').where((c) => c.now.contains('two')), isEmpty);
    });

    test('a name changed that the details do not hold', () {
      const s = 'I bless you as Sarah prayed for you';
      final r = applied(s, check(s, 'I bless you, as Sara prayed for you.'));
      expect(r, contains('Sarah'));
    });

    test('a word far from the one heard', () {
      const s = 'I bless you with love';
      expect(applied(s, check(s, 'I bless you with joy.')), contains('love'));
    });

    test('the whole text rewritten: the piece is dropped', () {
      const s = 'I bless you that you will be strong and have peace in your home';
      final cs = check(s, 'May you find strength, and may your household be filled with tranquility.');
      expect(cs, isEmpty);
    });

    test('an empty answer', () {
      expect(check(spoken, ''), isEmpty);
      expect(check(spoken, '   \n'), isEmpty);
    });

    test('markup, emoji and the like in the gaps', () {
      const s = 'I bless you with peace';
      final r = applied(s, check(s, '**I bless you** with peace 🙏'));
      expect(r, s);
    });

    test('two words run together', () {
      const s = 'every day of your life';
      expect(applied(s, check(s, 'everyday of your life')), s);
    });

    test('a paragraph already in the spoken words is never joined', () {
      const s = 'I bless you with peace.\n\nI bless you with strength.';
      expect(check(s, 'I bless you with peace. I bless you with strength.'), isEmpty);
    });

    test('a capital taken from a name or "I"', () {
      const s = 'and the Lord knows I love you';
      final r = applied(s, check(s, 'and the lord knows i love you.'));
      expect(r, contains('Lord'));
      expect(r, contains(' I '));
    });
  });

  test('after every kept change, only allowed differences remain (a mixed answer)', () {
    const s =
        'brother tom thou art called to serve and i bless thee that there family will know peace '
        'for for many years and you will be strong in the lord';
    const answer =
        'Here is the corrected text:\nBrother Tom, you are called to serve, and I bless you that their family will know great peace '
        'for many years. And you will be very strong in the Lord.';
    final cs = check(s, answer, names: {'Tom'});
    final r = applied(s, cs);
    expectOnlyAllowed(s, r);
    expect(r, contains('thou art'));
    expect(r, contains('bless thee'));
    expect(r, contains('their family'));
    expect(r, isNot(contains('great')));
    expect(r, isNot(contains('very')));
    expect(r, contains('for for'), reason: 'the model may not leave words out; that is the rules\' job');
  });

  group('pieces and stitching', () {
    test('a long blessing is cut at sentence ends, every piece within the limit', () {
      final s = List.generate(60, (i) => 'I bless you with blessing number word $i and peace in your home').join('. ');
      final ps = ModelSource.pieces(s, max: 300);
      expect(ps.length, greaterThan(5));
      for (final p in ps) {
        expect(p.text.length, lessThanOrEqualTo(300));
        expect(s.substring(p.start, p.start + p.text.length), p.text);
      }
      // nothing lost but the spaces between pieces
      expect(ps.map((p) => p.text).join(' '), s);
      expect(ps.take(ps.length - 1).every((p) => p.text.endsWith('.')), isTrue);
    });

    test('with no sentence ends, cut after a pause, then between words', () {
      final s = List.generate(80, (i) => 'and peace').join(', ');
      final ps = ModelSource.pieces(s, max: 200);
      for (final p in ps) {
        expect(p.text.length, lessThanOrEqualTo(200));
        if (p != ps.last) expect(p.text.endsWith(','), isTrue);
      }
      final bare = List.generate(80, (i) => 'peace').join(' ');
      final bp = ModelSource.pieces(bare, max: 100);
      expect(bp.map((p) => p.text).join(' '), bare);
    });

    test('changes from several pieces land at the right offsets', () async {
      final sentences = [for (var i = 0; i < 30; i++) 'brother sam i bless thee that there home will have peace and joy in the years ahead number $i'];
      final s = sentences.join('.\n\n');
      // the model capitalises, adds a comma, and puts "their" right, in every piece
      final model = FakeModel((t) => t.replaceAll('brother sam i', 'Brother Sam, I').replaceAll('there home', 'their home'));
      final b = Blessing(id: 'x', title: 'A blessing', from: 'Dad', utc: DateTime.utc(2026), utcOffset: Duration.zero, place: const Place(0, 0), rawText: s, language: 'en');
      final cs = await ModelSource(model).find(s, 'en', names: {'Sam'});
      expect(model.asked.length, greaterThan(1));
      expect(model.asked.every((t) => t.length <= ModelSource.pieceChars), isTrue);
      for (final c in cs) {
        expect(s.substring(c.start, c.end), c.was);
      }
      final r = applyChanges(s, cs);
      expect('Brother Sam, I'.allMatches(r).length, 30);
      expect('their home'.allMatches(r).length, 30);
      expect('there home'.allMatches(r), isEmpty);
      expect(r, contains('bless thee'));
      b.changes = cs;
      expect(b.polishedText, r);
    });
  });

  group('polish with a model', () {
    Blessing blessing(String words, {String language = 'en'}) =>
        Blessing(id: 'b', title: 'Blessing', from: 'Dad', utc: DateTime.utc(2026), utcOffset: Duration.zero, place: const Place(0, 0), rawText: words, language: language);

    test('no model: exactly the rules', () async {
      const w = 'I bless you, um, with with peace';
      final a = blessing(w), b = blessing(w);
      final n1 = Polish.run(a);
      final n2 = await Polish.runWithModel(b, model: FakeModel((t) => 'I bless you with peace and joy.', isReady: false));
      expect(n2, n1);
      expect(b.changes.map((c) => c.toString()), a.changes.map((c) => c.toString()));
      expect(b.polishAsked, isTrue);
    });

    test('rules and model together; the rules win where both change the same words', () async {
      const w = 'brother james um i bless you with with peace and there home';
      final b = blessing(w);
      final model = FakeModel((t) => 'Brother James, um, I bless you with with peace, and their home.');
      await Polish.runWithModel(b, model: model, names: {'James'});
      final rules = b.changes.where((c) => c.source == Change.rulesSource).toList();
      final fromModel = b.changes.where((c) => c.source == ModelSource.name).toList();
      expect(rules, isNotEmpty);
      expect(fromModel, isNotEmpty);
      for (final m in fromModel) {
        expect(rules.any((r) => r.overlaps(m)), isFalse);
      }
      expect(b.polishedText, contains('their home'));
      expect(b.polishedText, isNot(contains('with with')));
      expect(b.polishedText, isNot(contains('um')));
      expect(b.rawText, w, reason: 'the spoken words are never changed');
    });

    test('a correction afterwards runs the rules again, never the model', () async {
      final b = blessing('I bless you with peace and there home');
      final model = FakeModel((t) => '$t.');
      await Polish.runWithModel(b, model: model);
      final asked = model.asked.length;
      Polish.correct(b, 'I bless you with with peace and there home');
      Polish.refresh(b);
      expect(model.asked.length, asked);
      expect(b.changes.any((c) => c.kind == ChangeKind.repeat), isTrue);
    });

    test('a refused or failed piece gets the rules alone; the rest carries on', () async {
      final s = List.generate(10, (i) => 'and there home will have peace number $i').join('. ');
      var n = 0;
      final model = FakeModel((t) => n++ == 1 ? null : t.replaceAll('there home', 'their home'));
      final cs = await ModelSource(model).find(s, 'en');
      final r = applyChanges(s, cs);
      expect(model.asked.length, greaterThanOrEqualTo(1));
      if (model.asked.length > 1) expect('there home'.allMatches(r).length, greaterThan(0));
    });

    test('leaving stops the work: nothing is added', () async {
      final b = blessing('I bless you with with peace and there home');
      final model = FakeModel((t) => '$t.', delay: const Duration(milliseconds: 50));
      final work = PolishWork();
      final f = Polish.runWithModel(b, model: model, work: work);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      work.cancel();
      expect(await f, isNull);
      expect(b.changes, isEmpty);
      expect(model.cancelled, isNotEmpty);
    });

    test('words corrected while the model worked: its changes follow them', () async {
      final b = blessing('Peace be with you. I bless there home');
      final model = FakeModel((t) => t.replaceAll('there home', 'their home.'), delay: const Duration(milliseconds: 20));
      final f = Polish.runWithModel(b, model: model);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      Polish.correct(b, 'Peace be with you always. I bless there home');
      await f;
      expect(b.polishedText, 'Peace be with you always. I bless their home.');
    });

    test('the instructions are in the blessing\'s language and name its details', () async {
      final en = FakeModel((t) => t);
      await ModelSource(en).find('I bless you', 'en', names: {'Kathryn'});
      expect(en.lastInstructions, contains('thee'));
      expect(en.lastInstructions, contains('Kathryn'));
      final es = FakeModel((t) => t);
      await ModelSource(es).find('te bendigo', 'es');
      expect(es.lastInstructions, contains('vosotros'));
    });

    test('names come from the details', () {
      final b = blessing('x')
        ..from = 'Dad'
        ..recipient = 'Kathryn Lee';
      expect(Polish.namesOf(b, ['Tom']), {'Dad', 'Kathryn', 'Lee', 'Tom'});
    });
  });

  test('a piece over its time limit is stopped; the next goes on', () async {
    final s = List.generate(30, (i) => 'and there home will have peace number word $i').join('. ');
    var n = 0;
    final slow = _SlowFirst(() => n++);
    final cs = await ModelSource(slow, pieceTime: const Duration(milliseconds: 100)).find(s, 'en');
    expect(slow.cancelled, hasLength(1));
    expect(n, greaterThan(1));
    expect(applyChanges(s, cs), contains('their home'));
    expect(applyChanges(s, cs).substring(0, 40), contains('there home'), reason: 'the first piece timed out: rules alone');
  });
}

class _SlowFirst implements PhoneModel {
  _SlowFirst(this.next);
  final int Function() next;
  final cancelled = <String>[];
  @override
  Future<bool> ready(String language) async => true;
  @override
  Future<String?> polish(String text, {required String language, required String instructions, required String id}) async {
    if (next() == 0) await Future<void>.delayed(const Duration(seconds: 1));
    return text.replaceAll('there home', 'their home');
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}
