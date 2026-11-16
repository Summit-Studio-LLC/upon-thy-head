import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:upon_thy_head/lock/lock.dart';
import 'package:upon_thy_head/strings.dart';

void main() {
  final es = Strings.wordsFor(UiLanguage.spanish), en = Strings.wordsFor(UiLanguage.english);
  tearDown(() => Strings.use(UiLanguage.english));

  group('the app follows the phone', () {
    test('any Spanish first is Spanish; anything else is English', () {
      for (final l in const [Locale('es'), Locale('es', 'US'), Locale('es', 'MX'), Locale('es', 'ES'), Locale('es', '419')]) {
        expect(UiLanguage.forLocales([l, const Locale('en')]), UiLanguage.spanish, reason: '$l');
      }
      for (final l in const [Locale('en', 'US'), Locale('pt', 'BR'), Locale('fr')]) {
        expect(UiLanguage.forLocales([l, const Locale('es')]), UiLanguage.english, reason: '$l');
      }
      expect(UiLanguage.forLocales(const []), UiLanguage.english);
    });

    test('Strings reads the chosen language', () {
      expect(Strings.newBlessing, 'New blessing');
      Strings.use(UiLanguage.spanish);
      expect(Strings.newBlessing, 'Nueva bendición');
      expect(Strings.locale, const Locale('es', 'US'));
      Strings.use(UiLanguage.english);
      expect(Strings.newBlessing, 'New blessing');
    });

    test('the untitled title is known in either language', () {
      expect(Strings.isUntitled('Blessing'), isTrue);
      expect(Strings.isUntitled('Bendición'), isTrue);
      expect(Strings.isUntitled('Bendición de Dad'), isFalse);
    });
  });

  group('Spanish dates', () {
    final sunday = DateTime(2026, 11, 15, 22, 23);
    test('long and short', () {
      expect(es.longDate(sunday), 'domingo, 15 de noviembre de 2026');
      expect(es.shortDate(sunday), '15 nov 2026');
      expect(es.dayMonth(DateTime(2025, 10, 4)), '4 oct');
      expect(es.dayMonthLong(sunday), 'domingo, 15 de noviembre');
      expect(es.dayAndTime(DateTime(2026, 3, 3, 9, 40)), 'martes, 3 de marzo, 9:40 de la mañana');
      expect(es.longDate(DateTime(2024, 1, 1)), 'lunes, 1 de enero de 2024');
    });

    test('every month and day', () {
      const long = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
      const short = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
      for (var m = 1; m <= 12; m++) {
        final d = DateTime(2026, m, 21);
        expect(es.longDate(d), endsWith('21 de ${long[m - 1]} de 2026'));
        expect(es.shortDate(d), '21 ${short[m - 1]} 2026');
        expect(es.countLine(2, d), 'Dos bendiciones desde ${long[m - 1]} de 2026');
      }
      const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
      for (var i = 0; i < 7; i++) {
        expect(es.longDate(DateTime(2026, 11, 16 + i)), startsWith('${days[i]}, '));
      }
    });

    test('times of day in the spoken style', () {
      String t(int h, int m) => es.timeOfDay(DateTime(2026, 1, 1, h, m));
      expect(t(22, 23), '10:23 de la noche');
      expect(t(9, 40), '9:40 de la mañana');
      expect(t(15, 15), '3:15 de la tarde');
      expect(t(12, 5), '12:05 de la tarde');
      expect(t(18, 59), '6:59 de la tarde');
      expect(t(19, 0), '7:00 de la noche');
      expect(t(0, 30), '12:30 de la madrugada');
      expect(t(2, 59), '2:59 de la madrugada');
      expect(t(5, 59), '5:59 de la madrugada');
      expect(t(6, 0), '6:00 de la mañana');
      expect(t(11, 59), '11:59 de la mañana');
    });

    test('"a la" for one o\'clock, "a las" otherwise, in whole sentences', () {
      expect(es.overheadNote(DateTime(2026, 1, 1, 13, 15), daylight: true),
          'Su luz guarda el lugar del cielo que estaba justo encima a la 1:15 de la tarde, detrás de la luz del día.');
      expect(es.overheadNote(DateTime(2026, 1, 1, 22, 23), daylight: false),
          'Su luz guarda el lugar del cielo que estaba justo encima a las 10:23 de la noche.');
      expect(es.recoveredBody([DateTime(2026, 11, 15, 21, 40)]),
          'La app se cerró mientras se grababa una bendición el domingo 15 de noviembre, a las 9:40 de la noche. '
          'Lo que se había grabado está guardado.');
      expect(es.recoveredBody([DateTime(2026, 11, 15, 1, 5)]), contains('a la 1:05 de la madrugada'));
    });
  });

  group('Spanish counts', () {
    final june = DateTime(2024, 6, 9);
    test('the count line in words, singular and plural', () {
      expect(es.countLine(0, june), 'Todavía no hay bendiciones');
      expect(es.countLine(1, june), 'Una bendición desde junio de 2024');
      expect(es.countLine(2, june), 'Dos bendiciones desde junio de 2024');
      expect(es.countLine(5, june), 'Cinco bendiciones desde junio de 2024');
      expect(es.countLine(12, june), 'Doce bendiciones desde junio de 2024');
      expect(es.countLine(21, june), '21 bendiciones desde junio de 2024');
    });

    test('every number that is shown', () {
      expect(es.toReview(1), '1 por revisar');
      expect(es.toReview(3), '3 por revisar');
      expect(es.toReviewLabel(1), 'Una bendición por revisar. Ábrela.');
      expect(es.toReviewLabel(21), '21 bendiciones por revisar. Abre la más antigua.');
      expect(es.changes(1), '1 cambio');
      expect(es.changes(2), '2 cambios');
      expect(es.changes(4), '4 cambios');
      expect(es.changes(21), '21 cambios');
      expect(es.keptOf(1, 2), 'Se conserva 1 de 2');
      expect(es.keptOf(4, 5), 'Se conservan 4 de 5');
      expect(es.polishedRow(2, 2), '2 cambios');
      expect(es.polishedRow(1, 2), 'Se conserva 1 de 2');
      expect(es.polishedRow(0, 2), 'Palabras originales');
      expect(es.polishedFrom(1), startsWith('Pulidas a partir de las palabras dichas, con 1 pequeño cambio. '));
      expect(es.polishedFrom(5), startsWith('Pulidas a partir de las palabras dichas, con 5 pequeños cambios. '));
      expect(es.recoveredTitle(1), 'Se guardó una grabación');
      expect(es.recoveredTitle(2), 'Se guardaron dos grabaciones');
      expect(es.recoveredTitle(5), 'Se guardaron cinco grabaciones');
      expect(es.recoveredTitle(21), 'Se guardaron 21 grabaciones');
      expect(es.recoveredBody([june, june, june, june, june]), startsWith('La app se cerró mientras se grababan cinco bendiciones. '));
      expect(es.stepOf(1, 5), '1 de 5');
    });
  });

  group('the two languages side by side', () {
    test('the vocabulary the whole app agrees on', () {
      expect(es.forMe, 'Para mí');
      expect(es.newBlessing, 'Nueva bendición');
      expect(es.begin, 'Comenzar');
      expect(es.amen, 'Amén');
      expect(es.discard, 'Descartar');
      expect(es.reviewNow, 'Revisar ahora');
      expect(es.saveForLater, 'Guardar para después');
      expect(es.blessingFrom('Dad'), 'Una bendición de Dad');
      expect(es.settings, 'Ajustes');
      expect(es.appLock, 'Bloqueo de la app');
      expect(es.untitled, 'Bendición');
    });

    test('every fixed string has Spanish, and only names stay the same', () {
      final e = en.catalogue, s = es.catalogue;
      expect(s.keys, e.keys);
      // the same in both on purpose: a word Spanish shares
      const same = {'original'};
      for (final k in e.keys) {
        expect(s[k], isNotEmpty, reason: k);
        if (!same.contains(k)) expect(s[k], isNot(e[k]), reason: '$k is still English: "${e[k]}"');
      }
    });

    test('English is exactly as it was', () {
      expect(en.longDate(DateTime(2026, 3, 3)), 'Tuesday, March 3, 2026');
      expect(en.shortDate(DateTime(2026, 3, 3)), 'Mar 3, 2026');
      expect(en.timeOfDay(DateTime(2026, 3, 3, 9, 40)), '9:40 in the morning');
      expect(en.countLine(5, DateTime(2024, 6)), 'Five blessings since June 2024');
      expect(en.lockHint(LockMethod.faceId), 'Asks for Face ID when you open the app. Recording never waits for it.');
      expect(es.lockHint(LockMethod.passcode), 'Pide tu código al abrir la app. Para grabar nunca hace falta.');
      expect(es.near(40.77, -111.89), 'Cerca de 40.8° N, 111.9° O');
    });
  });
}
