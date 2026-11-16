import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/share/share.dart';
import 'package:upon_thy_head/strings.dart';

/// The polished sample's words, as the reading page shows them.
const surgeryWords = 'Emma, I lay my hands upon your head to give you a blessing of comfort.\n\n'
    'Your Heavenly Father knows you. He knows the worry you have carried these weeks, and He wants you to know that you have not carried it alone.\n\n'
    'I bless you with peace as you go into this surgery, and I bless the hands of those who will care for you. Be patient with your body as it heals. Strength will return to you in its time.\n\n'
    'I say these things in the name of Jesus Christ, amen.';

Blessing plain({String title = 'A quiet one', String from = '', String recipient = '', String raw = 'Be still.', List<Change>? changes}) => Blessing(
      id: 'x',
      title: title,
      from: from,
      recipient: recipient,
      utc: DateTime.utc(2026, 11, 15, 4, 23),
      utcOffset: const Duration(hours: -7), // given at 9:23 pm on the 14th, where it was
      place: samplePlace,
      rawText: raw,
      changes: changes,
      draft: false,
    );

void main() {
  final en = Strings.wordsFor(UiLanguage.english), es = Strings.wordsFor(UiLanguage.spanish);
  final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
  tearDown(() => Strings.use(UiLanguage.english));

  group('the text', () {
    test('the sample: title, long date, giver, recipient, a blank line, the polished words', () {
      expect(shareText(surgery, en), 'Comfort before surgery\nTuesday, March 3, 2026\nA blessing from Dad\nFor Emma\n\n$surgeryWords');
    });

    test('in Spanish the labels and date are Spanish; the title and words are untouched', () {
      expect(shareText(surgery, es), 'Comfort before surgery\nmartes, 3 de marzo de 2026\nUna bendición de Dad\nPara Emma\n\n$surgeryWords');
    });

    test('the current language is used when none is given', () {
      Strings.use(UiLanguage.spanish);
      expect(shareText(surgery), shareText(surgery, es));
    });

    test('the spoken words when no change is kept', () {
      final b = sampleBlessings().firstWhere((b) => b.id == 'surgery');
      for (final c in b.changes) {
        c.kept = false;
      }
      expect(shareText(b, en), endsWith('\n\n${b.rawText}'));
      expect(shareText(b, en), contains('um, right now'));
    });

    test('no giver, no recipient, one line', () {
      expect(shareText(plain(), en), 'A quiet one\nSaturday, November 14, 2026\n\nBe still.');
      expect(shareText(plain(), es), 'A quiet one\nsábado, 14 de noviembre de 2026\n\nBe still.');
    });

    test('a recipient without a giver, names trimmed', () {
      expect(shareText(plain(recipient: '  Ana '), en), 'A quiet one\nSaturday, November 14, 2026\nFor Ana\n\nBe still.');
      expect(shareText(plain(from: ' Abuelo ', recipient: 'Ana'), es),
          'A quiet one\nsábado, 14 de noviembre de 2026\nUna bendición de Abuelo\nPara Ana\n\nBe still.');
    });

    test('paragraphs as the reading page splits them: blank lines between, spaces trimmed, a line break kept', () {
      final b = plain(raw: '  First.  \n \n\n\nSecond,\nstill second.\n\n   \n\nThird.\n');
      expect(shareText(b, en), endsWith('\n\nFirst.\n\nSecond,\nstill second.\n\nThird.'));
    });

    test('no words: the heading alone', () {
      expect(shareText(plain(raw: '  '), en), 'A quiet one\nSaturday, November 14, 2026');
    });

    test('an untitled blessing reads as the phone\'s word for it', () {
      expect(shareText(plain(title: 'Bendición'), en), startsWith('Blessing\n'));
      expect(shareText(plain(title: 'Blessing'), es), startsWith('Bendición\n'));
    });
  });

  group('the file name', () {
    test('the title and the date', () {
      expect(shareFileName(surgery, en), 'Comfort before surgery, March 3, 2026.pdf');
      expect(shareFileName(surgery, es), 'Comfort before surgery, 3 de marzo de 2026.pdf');
      expect(shareFileName(plain(), en), 'A quiet one, November 14, 2026.pdf');
    });

    test('characters a file name cannot hold are taken out, words kept apart', () {
      expect(shareFileName(plain(title: 'Mother/daughter: before the move'), en), 'Mother daughter before the move, November 14, 2026.pdf');
      expect(shareFileName(plain(title: r'a\b*c?d"e<f>g|h'), en), 'a b c d e f g h, November 14, 2026.pdf');
      expect(shareFileName(plain(title: '...hidden\nline\ttab.'), en), 'hidden line tab, November 14, 2026.pdf');
      expect(shareFileName(plain(title: 'Bendición de Papá: ¿mañana?'), es), 'Bendición de Papá ¿mañana, 14 de noviembre de 2026.pdf');
    });

    test('a title of only unsafe characters falls back to the untitled word', () {
      expect(shareFileName(plain(title: '/:/'), en), 'Blessing, November 14, 2026.pdf');
      expect(shareFileName(plain(title: '/:/'), es), 'Bendición, 14 de noviembre de 2026.pdf');
    });

    test('a very long title is cut at a word, well under the file system\'s limit', () {
      final long = List.filled(40, 'comfort/peace:').join(' ');
      final name = shareFileName(plain(title: long), en);
      expect(name, endsWith('…, November 14, 2026.pdf'));
      expect(name.contains('/') || name.contains(':'), isFalse);
      expect(name.runes.length, lessThan(140));
      expect(name.codeUnits.length, lessThan(255));
      expect(name, isNot(contains('  ')));
    });
  });

  group('the PDF', () {
    test('what the native side is given', () {
      final m = sharePdf(surgery, en);
      expect(m['fileName'], 'Comfort before surgery, March 3, 2026.pdf');
      expect(m['title'], 'Comfort before surgery');
      expect(m['date'], 'Tuesday, March 3, 2026');
      expect(m['from'], 'A blessing from Dad');
      expect(m['recipient'], 'For Emma');
      expect(m['paragraphs'], surgeryWords.split('\n\n'));
      expect(m['pageOf'], '{n} of {total}');
      expect(sharePdf(surgery, es)['pageOf'], '{n} de {total}');
      expect(sharePdf(plain(), en)['from'], '');
      expect(sharePdf(plain(), en)['recipient'], '');
    });

    test('every new string has its Spanish', () {
      for (final k in ['share', 'shareTitle', 'asText', 'asTextHint', 'asPdf', 'asPdfHint', 'shareNote']) {
        expect(es.catalogue[k], isNot(en.catalogue[k]), reason: k);
      }
      expect(en.pageOf(2, 3), '2 of 3');
      expect(es.pageOf(2, 3), '2 de 3');
      expect(es.fullDate(DateTime(2026, 3, 3)), '3 de marzo de 2026');
    });
  });
}
