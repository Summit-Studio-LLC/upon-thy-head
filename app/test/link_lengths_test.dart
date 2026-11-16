// How long a link is for blessings of different lengths (docs/blessing-file.md, "In a link").
//
// Always: the sample "Comfort before surgery" and a blessing-style text in each language.
// With LINK_CORPUS=<folder> holding en_prose.txt and es_prose.txt (paragraphs separated by a blank
// line), also 100, 300, 600, 1,500 and 2,500 words of each, cut at a word. The figures in the doc
// came from the King James and Reina-Valera 1909 Gospel of John, public domain, as a stand-in for
// real blessings, which Noah is to supply.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/data/blessing.dart';
import 'package:upon_thy_head/data/samples.dart';
import 'package:upon_thy_head/polish/change.dart';
import 'package:upon_thy_head/share/blessing_file.dart';
import 'package:upon_thy_head/share/link.dart';

const enStyle = 'Emma, by the authority of the holy Melchizedek Priesthood which I hold, I place my hands upon your head '
    'and give you a blessing at the start of this new school year.\n\n'
    'Your Heavenly Father loves you. He knows your name, and He knows the questions you carry when you walk into a room '
    'full of people you do not know yet. I bless you with courage to say hello first, and with the kindness to notice '
    'the one who sits alone.\n\n'
    'I bless you with a clear mind as you study. When the work is hard, remember that you can ask Him for help, and that '
    'help will come, sometimes through a teacher, sometimes through a friend, and sometimes as a quiet thought that you '
    'will know is not your own.\n\n'
    'I bless your body with health, and your sleep with rest. I bless you that the friends you choose will lift you, '
    'and that you will lift them.\n\n'
    'Know that your mother and I are proud of you, not for what you do but for who you are. We pray for you every night.\n\n'
    'I leave these words with you in the name of Jesus Christ, amen.';

const esStyle = 'Emma, por la autoridad del santo Sacerdocio de Melquisedec que poseo, pongo mis manos sobre tu cabeza '
    'y te doy una bendición al comenzar este nuevo año escolar.\n\n'
    'Tu Padre Celestial te ama. Él conoce tu nombre, y conoce las preguntas que llevas cuando entras a un salón lleno de '
    'personas que todavía no conoces. Te bendigo con valor para saludar primero, y con la bondad de fijarte en quien '
    'se sienta solo.\n\n'
    'Te bendigo con una mente clara al estudiar. Cuando el trabajo sea difícil, recuerda que puedes pedirle ayuda, y que '
    'la ayuda llegará, a veces por medio de una maestra, a veces por medio de una amiga, y a veces como un pensamiento '
    'tranquilo que sabrás que no es tuyo.\n\n'
    'Bendigo tu cuerpo con salud, y tu sueño con descanso. Te bendigo para que los amigos que escojas te levanten, y '
    'para que tú los levantes a ellos.\n\n'
    'Sabe que tu madre y yo estamos orgullosos de ti, no por lo que haces sino por quien eres. Oramos por ti cada noche.\n\n'
    'Te dejo estas palabras en el nombre de Jesucristo, amén.';

int wordCount(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// The first [n] words of [text], keeping its paragraph breaks.
String firstWords(String text, int n) {
  final out = <String>[];
  var left = n;
  for (final para in text.split(RegExp(r'\n\s*\n'))) {
    if (left <= 0) break;
    final ws = para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    out.add(ws.take(left).join(' '));
    left -= ws.length;
  }
  return out.join('\n\n');
}

Blessing blessingOf(String words, String lang) => Blessing(
      id: newBlessingId(),
      title: lang == 'es' ? 'Al comenzar el año escolar' : 'At the start of the school year',
      from: lang == 'es' ? 'Papá' : 'Dad',
      recipient: 'Emma',
      utc: DateTime.utc(2026, 8, 18, 2, 30),
      utcOffset: const Duration(hours: -6),
      place: samplePlace,
      rawText: words,
      tags: lang == 'es' ? ['Escuela', 'Familia'] : ['School', 'Family'],
      language: lang,
      draft: false,
    );

String row(String what, int words, Blessing b) {
  final rec = BlessingRecord.of(b);
  final json = rec.toCompactBytes().length;
  final file = rec.toFileBytes().length;
  final link = blessingLink(rec);
  // LINK_OUT=<file>: the links, one a line, for tool/link_check.swift to open with Apple's frameworks
  final out = Platform.environment['LINK_OUT'];
  if (out != null) File(out).writeAsStringSync('$link\n', mode: FileMode.append);
  expect((readBlessingLink(link) as BlessingReadOk).record.sameAs(b), isTrue);
  return '| $what | $words | $file | $json | ${link.length} |';
}

void main() {
  test('link lengths', () {
    final lines = <String>['| text | words | file bytes | compact JSON bytes | link characters |', '|---|---:|---:|---:|---:|'];
    final surgery = sampleBlessings().firstWhere((b) => b.id == 'surgery');
    lines.add(row('sample "Comfort before surgery" (5 changes)', wordCount(surgery.rawText), surgery));
    final noChanges = BlessingRecord.of(surgery).toBlessing(place: samplePlace)..changes = <Change>[];
    lines.add(row('the same without its changes', wordCount(surgery.rawText), noChanges));
    lines.add(row('blessing-style, English', wordCount(enStyle), blessingOf(enStyle, 'en')));
    lines.add(row('blessing-style, Spanish', wordCount(esStyle), blessingOf(esStyle, 'es')));
    final dir = Platform.environment['LINK_CORPUS'];
    if (dir != null) {
      for (final lang in ['en', 'es']) {
        final text = File('$dir/${lang}_prose.txt').readAsStringSync();
        for (final n in [100, 300, 600, 1500, 2500]) {
          final words = firstWords(text, n);
          lines.add(row('prose, ${lang == 'en' ? 'English' : 'Spanish'}', wordCount(words), blessingOf(words, lang)));
        }
      }
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}
