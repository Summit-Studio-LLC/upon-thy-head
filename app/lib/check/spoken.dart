// The words spoken into the prepared recordings (integration_test/audio/*.m4a), shared by the
// integration tests and the phone check page.

/// What was spoken into integration_test/audio/*.m4a, made on a Mac with `say`
/// (Samantha, en_US; Paulina, es_MX) with three seconds of silence between paragraphs,
/// then `afconvert -f m4af -d aac@16000 -c 1 -b 24000`, the format the app records in.
/// The English is the sample blessing's words as spoken ("Comfort before surgery").
const spokenEnglish = 'Emma, I lay my hands upon your head, um, right now, to give you a blessing of comfort.\n\n'
    'Your Heavenly Father knows you. He knows about, He knows the worry you have carried these weeks, and He wants you to know that you have not carried it alone.\n\n'
    'I bless you with, with peace as you go into this surgery, and I bless the hands of those who are going to be caring for you. Be patient with your body as it heals. your strength, it\'s going to come back to you in its time.\n\n'
    'I say these things in the name of Jesus Christ, amen.';

const spokenSpanish = 'Emma, pongo mis manos sobre tu cabeza para darte una bendición de consuelo.\n\n'
    'Tu Padre Celestial te conoce, y sabe la preocupación que has llevado estas semanas. Te bendigo con paz, y con fuerza para los días que vienen.\n\n'
    'Digo estas cosas en el nombre de Jesucristo, amén.';

/// Words only: lower case, no punctuation; accents kept.
List<String> words(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^\p{L}\p{N}' ]+", unicode: true), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Word errors (substitutions + deletions + insertions) between what was said and what came back.
({int errors, int spoken, int subs, int dels, int ins}) wordErrors(String said, String heard) {
  final a = words(said), b = words(heard);
  // d[i][j]: edits to turn a[0..i) into b[0..j); keep the kind of each step
  final d = List.generate(a.length + 1, (i) => List.generate(b.length + 1, (j) => i + j));
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final sub = d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      d[i][j] = [sub, d[i - 1][j] + 1, d[i][j - 1] + 1].reduce((x, y) => x < y ? x : y);
    }
  }
  var i = a.length, j = b.length, subs = 0, dels = 0, ins = 0;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) {
      if (a[i - 1] != b[j - 1]) subs++;
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      dels++;
      i--;
    } else {
      ins++;
      j--;
    }
  }
  return (errors: d[a.length][b.length], spoken: a.length, subs: subs, dels: dels, ins: ins);
}
