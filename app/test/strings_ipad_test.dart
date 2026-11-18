// On an iPad no sentence of the app calls it a phone or an iPhone (lib/strings_ipad.dart), in
// English and Spanish; on an iPhone every sentence is exactly as it was.
//
//   flutter test test/strings_ipad_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/strings.dart';

/// Shown only on Android, never on an iPad.
const android = {
  'asFileHintAndroid', 'sameAsPhoneAndroid', 'aboutBodyAndroid', 'notificationsWhy', 'noScreenLock', 'wordsLater', 'wordsLaterHere',
  'finishBodyLater', 'modelReady', 'wordsCheck', 'microphoneRefusedAndroid', 'microphoneSettingsAndroid', 'allowMicrophone',
  'permsLedeAndroid', 'locationWhyAndroid', 'lockWhyAndroid', 'modelBody', 'modelNoRoom', 'modelOnPhone',
};

/// "this phone", "the phone", "este teléfono", "this iPhone": anything that names the device as a phone.
final phone = RegExp(r'\b(this|the|a|another) phone\b|\bphone\b|\bthis iPhone\b|teléfono|celular|este iPhone|\bel iPhone\b', caseSensitive: false);

void main() {
  tearDown(() {
    Strings.iPad = false;
    Strings.use(UiLanguage.english);
  });

  for (final lang in UiLanguage.values) {
    test('iPad, ${lang.name}: no sentence names a phone', () {
      Strings.iPad = true;
      final w = Strings.wordsFor(lang);
      final bad = <String>[
        for (final e in w.catalogue.entries)
          if (!android.contains(e.key) && phone.hasMatch(e.value.replaceAll(RegExp('icr[oó]fono', caseSensitive: false), ''))) '${e.key}: ${e.value}',
        for (final n in [0, 1, 7])
          if (phone.hasMatch(w.removeBody('Emma', n))) 'removeBody($n): ${w.removeBody('Emma', n)}',
      ];
      expect(bad, isEmpty, reason: bad.join('\n'));
      expect(w.language, lang);
    });

    test('iPhone, ${lang.name}: every sentence as before', () {
      Strings.iPad = false;
      final phoneWords = Strings.wordsFor(lang).catalogue;
      Strings.iPad = true;
      final iPadWords = Strings.wordsFor(lang).catalogue;
      final changed = [for (final k in phoneWords.keys) if (phoneWords[k] != iPadWords[k]) k];
      // only the sentences that name the device differ, and each of them names the iPad
      for (final k in changed) {
        expect(iPadWords[k], contains('iPad'), reason: k);
        expect(phone.hasMatch(phoneWords[k]!) || phoneWords[k]!.contains('iPhone'), isTrue, reason: k);
      }
      expect(changed, isNotEmpty);
    });
  }

  test('detectIPad is false off iOS (the host)', () => expect(Strings.detectIPad(), isFalse));
}
