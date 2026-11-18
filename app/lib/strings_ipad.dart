part of 'strings.dart';

// An iPad's words: the sentences that name the device, each written whole for the iPad (an iPad is
// not a phone). Everything else is the phone's. Chosen at launch when the app runs on an iPad
// ([Strings.iPad]); Android never uses them. A new sentence that names "this phone" on iOS needs its
// iPad sentence here too: test/strings_ipad_test.dart fails without it.

class _IPadEnglish extends Words {
  const _IPadEnglish();

  @override
  String get recordingKeptBody => 'The recording stays on this iPad until you have reviewed the words. Then it is erased.';
  @override
  String get wordsNotWrittenYet => 'The words could not be written on this iPad yet. The recording stays here until they can be.';
  @override
  String get wordsNotWritten => 'The words could not be written this time. The recording stays on this iPad.';
  @override
  String get notReviewed => 'Not yet reviewed. The recording stays on this iPad until you finish.';
  @override
  String get wordsNotWrittenHere => 'The words could not be written on this iPad. Listen to the recording and type them here.';
  @override
  String get finishBody => 'The recording will be erased from this iPad. The words stay.';
  @override
  String get deleteBody => 'Its words will be removed from this iPad. This cannot be undone.';
  @override
  String get noPasscode => 'Set a passcode on this iPad to lock your blessings.';
  @override
  String get sameAsPhone => 'Same as this iPad';
  @override
  String get aboutBody => 'Your words stay on this iPad. Nothing leaves it unless you share it.';
  @override
  String get shareNote => 'Once it leaves this iPad, it is no longer private to it.';
  @override
  String get asFileHint => 'Opens in Upon Thy Head on another iPhone or iPad.';
  @override
  String get linkLine2 => 'It is locked on this iPad before it leaves. The server keeps the locked copy, never the key.';
  @override
  String get sentBody => 'Keep a copy on this iPad, or delete it now?';
  @override
  String get passingDeleteBody => 'It is removed from this iPad. A link already sent keeps working until it stops.';
  @override
  String get welcome2 => 'The words are written on this iPad. Nothing leaves it unless you share it.';
  @override
  String get permsLede => 'Tap Allow beside each, and the iPad will ask.';
  @override
  String get speechWhy => 'To write the words down, on this iPad.';
  @override
  String get askingNow => 'The iPad is asking now';
  @override
  String get tryBody => 'Say anything, then hold Amen. You will see what the iPad wrote. Nothing is kept.';
  @override
  String get phoneWrote => 'What the iPad wrote';
  @override
  String get practiceUnavailable =>
      'This iPad cannot write down words in this language yet. A real recording is still kept, and its words are written when the iPad can.';
  @override
  String get addFamilyLede => 'For a child, or anyone in your family. Their blessings are kept on this iPad, on a ring of their own.';
  @override
  String removeBody(String name, int blessings) => switch (blessings) {
        0 => "$name's ring leaves this iPad. There are no blessings on it.",
        1 => "One blessing leaves this iPad with $name's ring. This cannot be undone.",
        _ => "${count(blessings)} blessings leave this iPad with $name's ring. This cannot be undone.",
      };
}

class _IPadSpanish extends _Spanish {
  const _IPadSpanish();

  @override
  String get recordingKeptBody => 'La grabación se queda en este iPad hasta que hayas revisado las palabras. Después se borra.';
  @override
  String get wordsNotWrittenYet => 'Todavía no se pudieron escribir las palabras en este iPad. La grabación se queda aquí hasta que se pueda.';
  @override
  String get wordsNotWritten => 'Esta vez no se pudieron escribir las palabras. La grabación se queda en este iPad.';
  @override
  String get notReviewed => 'Todavía sin revisar. La grabación se queda en este iPad hasta que termines.';
  @override
  String get wordsNotWrittenHere => 'No se pudieron escribir las palabras en este iPad. Escucha la grabación y escríbelas aquí.';
  @override
  String get finishBody => 'La grabación se borrará de este iPad. Las palabras se quedan.';
  @override
  String get deleteBody => 'Sus palabras se quitarán de este iPad. Esto no se puede deshacer.';
  @override
  String get noPasscode => 'Configura un código en este iPad para bloquear tus bendiciones.';
  @override
  String get sameAsPhone => 'Igual que este iPad';
  @override
  String get aboutBody => 'Tus palabras se quedan en este iPad. Nada sale de él a menos que lo compartas.';
  @override
  String get shareNote => 'Una vez que sale de este iPad, ya no es privada.';
  @override
  String get asFileHint => 'Se abre en Upon Thy Head en otro iPhone o iPad.';
  @override
  String get linkLine2 => 'Se cierra en este iPad antes de salir. El servidor guarda la copia cerrada, nunca la llave.';
  @override
  String get sentBody => '¿Guardar una copia en este iPad o eliminarla ahora?';
  @override
  String get passingDeleteBody => 'Se quita de este iPad. Un enlace ya enviado sigue funcionando hasta que se detenga.';
  @override
  String get welcome2 => 'Las palabras se escriben en este iPad. Nada sale de él si tú no lo compartes.';
  @override
  String get permsLede => 'Toca Permitir junto a cada una y el iPad te preguntará.';
  @override
  String get speechWhy => 'Para escribir las palabras, en este iPad.';
  @override
  String get askingNow => 'El iPad está preguntando';
  @override
  String get tryBody => 'Di cualquier cosa y luego mantén presionado Amén. Verás lo que escribió el iPad. No se guarda nada.';
  @override
  String get phoneWrote => 'Lo que escribió el iPad';
  @override
  String get practiceUnavailable =>
      'Este iPad todavía no puede escribir las palabras en este idioma. Una grabación de verdad sí se guarda, y sus palabras se escriben cuando el iPad pueda.';
  @override
  String get addFamilyLede => 'Para un hijo, una hija o cualquier persona de tu familia. Sus bendiciones se guardan en este iPad, en un anillo propio.';
  @override
  String removeBody(String name, int blessings) => switch (blessings) {
        0 => 'El anillo de $name se quitará de este iPad. No tiene bendiciones.',
        1 => 'La única bendición del anillo de $name se irá de este iPad. Esto no se puede deshacer.',
        _ => 'Las ${count(blessings).toLowerCase()} bendiciones del anillo de $name se irán de este iPad. Esto no se puede deshacer.',
      };
}
