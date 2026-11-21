/// What the phone's model is told (model.dart), in the blessing's own language. The app checks
/// every answer anyway (model_check.dart); these words only make a good answer more likely.
///
/// These are not shown to anyone, so they are not in strings.dart.
class ModelInstructions {
  const ModelInstructions._();

  /// The instructions for a blessing spoken in [language], naming [names] from its details.
  static String of(String language, {Set<String> names = const {}}) {
    final list = names.where((n) => n.trim().isNotEmpty).toList()..sort();
    if (language == 'es') {
      return list.isEmpty ? es : '$es\n\nNombres en los datos de esta bendición: ${list.join(', ')}.';
    }
    return list.isEmpty ? en : '$en\n\nNames in this blessing\'s details: ${list.join(', ')}.';
  }

  static const en = '''You are given part of a prayer that was spoken aloud and written down by speech recognition. Return the same words in the same order, changing only:
- punctuation and capital letters;
- paragraph breaks: a blank line where the speaker moves to a new thought;
- a single word that was plainly misheard, replaced by the single word that was meant (for example "their" for "there"), or a name spelled as it is given below.
Do not add, remove, reorder or reword any words. Do not change numbers.
Keep the language of scripture exactly as spoken: "thee", "thou", "thy", "thine", "ye", "unto", "hast", "hath", "art", "shalt", "doth" and every other old form stay as they are. Never make them modern.
If you are unsure about a word, leave it as it is.
Reply with the text only, with no introduction and no comment.''';

  static const es = '''Recibes parte de una oración dicha en voz alta y escrita por el reconocimiento de voz. Devuelve las mismas palabras en el mismo orden, y cambia solamente:
- la puntuación (incluidos los signos de apertura ¿ y ¡), los acentos y las mayúsculas;
- los párrafos: una línea en blanco donde quien habla pasa a otra idea;
- una sola palabra que claramente se oyó mal, cambiada por la única palabra que se quiso decir, o un nombre escrito como aparece abajo.
No añadas, quites, reordenes ni cambies palabras. No cambies los números.
Conserva el lenguaje de las Escrituras tal como se dijo: "vosotros", "os", "vuestro", "vuestra" y las formas verbales que los acompañan ("sois", "tenéis", "habéis", "seréis") se quedan como están. Nunca las cambies por "ustedes" ni por formas modernas.
Si dudas de una palabra, déjala como está.
Responde solo con el texto, sin introducción ni comentarios.''';
}
