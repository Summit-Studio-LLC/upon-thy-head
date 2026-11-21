// A stand-in for the phone's own model, for the simulator walk of polish's light and the widget
// tests. Apple's model cannot run on a Mac or its simulators, so this answers each piece after
// about two seconds with the kinds of change the real one makes: punctuation, capitals, a
// paragraph break, and one misheard word put right.
//
// It lives under integration_test/ and nothing in lib/ imports it, so no build of the app,
// release or otherwise, can reach it.

import 'dart:async';

import 'package:upon_thy_head/polish/model.dart';

class StandInModel implements PhoneModel {
  StandInModel({this.delay = const Duration(seconds: 2), this.isReady = true});

  /// How long each piece takes.
  final Duration delay;
  final bool isReady;

  /// The pieces asked about, in order, and the calls stopped.
  final asked = <String>[];
  final cancelled = <String>[];

  final _waiting = <String, Completer<String?>>{};

  @override
  Future<bool> ready(String language) async => isReady;

  @override
  Future<String?> polish(String text, {required String language, required String instructions, required String id}) {
    asked.add(text);
    final done = _waiting[id] = Completer<String?>();
    Timer(delay, () {
      if (!done.isCompleted) done.complete(answer(text));
      _waiting.remove(id);
    });
    return done.future;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    final w = _waiting.remove(id);
    if (w != null && !w.isCompleted) w.complete(null);
  }

  /// The words as the model would mend them: each fault in [walkBlessing] put right.
  static String answer(String text) {
    var out = text;
    for (final MapEntry(:key, :value) in fixes.entries) {
      out = out.replaceAll(key, value);
    }
    return out;
  }

  static const fixes = {
    // piece one: capitals, a sentence ended, a misheard word
    'heavenly father knows you': 'Heavenly Father knows you',
    'at this time and i bless you': 'at this time. And I bless you',
    'there home': 'their home',
    // piece two: a comma, a paragraph, a misheard word
    'you will no that': 'you will know that',
    'in the days ahead I bless you with health': 'in the days ahead.\n\nI bless you with health',
    'strength and you will': 'strength, and you will',
    // piece three: a name's capitals and a comma, a sentence ended
    'brother james you': 'Brother James, you',
    'to your family and': 'to your family. And',
    // the Spanish look (polish_light_test.dart)
    'padre celestial te conoce': 'Padre Celestial te conoce',
    'en tu trabajo y en tus estudios': 'en tu trabajo, y en tus estudios',
  };
}

/// A blessing long enough for three of the model's pieces (about 3,300 characters), with the faults
/// [StandInModel] mends spread through all three.
const walkBlessing =
    'Brother James, by the authority of the holy Melchizedek Priesthood which I hold, I lay my hands upon your head and give you a blessing at this time and i bless you that you will feel the peace that comes from knowing who you are. '
    'heavenly father knows you. He knows your name and the desires of your heart, and he is aware of the burdens that you carry in these days. '
    'I bless you that the spirit will be with you in there home, that it will be a place of rest and of light for you and for those you love. '
    'I bless you that when you are weary you will remember the covenants you have made, and that you will find strength in keeping them. '
    'I bless you with patience with yourself, for the Lord is patient with you, and he does not ask more of you than you are able to give. '
    'I bless you that the words of the scriptures will open to your mind as you read them, and that you will hear his voice in them. '
    'I bless you with friends who will lift you, and that you will be a friend to those who are alone, as the Saviour was a friend to all. '
    'I bless you that your prayers will be heard, and that the answers will come in the Lord\'s own time and in his own way. '
    'you will no that you have been heard, even when the answer is to wait, and you will be given the faith to wait well. '
    'I bless you that you will be guided in the choices before you, in your work and in your learning, and that doors will open in the days ahead I bless you with health of body and of mind, that you will have strength and you will rise each morning ready for the day. '
    'I bless you that your hands will be steady and your thoughts clear, and that the fears which have troubled you at night will leave you. '
    'I bless you that you will sleep in peace, and that you will wake knowing that you are loved, by your family here and by your Father in Heaven. '
    'I bless you that you will see the good in each day, even in the hard ones, and that you will be grateful for small mercies as they come. '
    'I bless you that you will serve those around you with a willing heart, and that in serving them you will find your own burdens lighter. '
    'I bless you that you will be patient with those who do not understand you, and that they in time will come to see you as the Lord does. '
    'brother james you are a son of God, and he has a work for you to do. You were sent here at this time for a reason, and he will make it known to you. '
    'I bless you that you will be an example of faith to your family and that they will be strengthened by your quiet goodness and your prayers. '
    'I bless you that you will remember this blessing in the days to come, and that its words will return to you when you have need of them. '
    'I bless you that you will feel the love of those who have gone before you, and that you will know they are near and are glad of you. '
    'I bless you that you will endure to the end, and that you will one day return to his presence with honour and with joy. '
    'I leave these blessings with you, and I do it in the name of Jesus Christ, amen.';
