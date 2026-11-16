import 'dart:ui' show Locale;

import 'lock/lock.dart';
import 'record/transcriber.dart';

/// The language the app's own words are in. It follows the phone's first language and has no
/// switch of its own; the language a blessing is recorded in is a separate setting.
enum UiLanguage {
  english(Locale('en', 'US')),
  spanish(Locale('es', 'US'));

  const UiLanguage(this.locale);
  final Locale locale;

  /// Spanish when the phone's first language is any Spanish; English otherwise.
  static UiLanguage forLocales(List<Locale> locales) =>
      locales.isNotEmpty && locales.first.languageCode == 'es' ? UiLanguage.spanish : UiLanguage.english;
}

/// Every word the app shows, in one place.
///
/// [Words] holds the English; [_Spanish] `implements` it, so a Spanish string left out does not
/// compile. [Strings] is how the rest of the app reads them: `Strings.forMe` is the current
/// language's. Sentences are written whole for each language, never assembled from the other's
/// pieces.
class Strings {
  const Strings._();

  static Words _w = const Words();

  /// The words for [l]. main() sets it from the phone before the first frame.
  static void use(UiLanguage l) => _w = wordsFor(l);
  static UiLanguage get language => _w.language;
  static Locale get locale => _w.language.locale;
  static Words wordsFor(UiLanguage l) => switch (l) {
        UiLanguage.english => const Words(),
        UiLanguage.spanish => const _Spanish(),
      };

  /// Whether [title] is the title a blessing carries until it is reviewed, in either language
  /// (a draft keeps the word it was made with when the phone's language changes).
  static bool isUntitled(String title) => UiLanguage.values.any((l) => wordsFor(l).untitled == title);

  // ---- the current language's words, one line each ----
  static List<String> get months => _w.months;
  static List<String> get days => _w.days;
  static String longDate(DateTime d) => _w.longDate(d);
  static String shortDate(DateTime d) => _w.shortDate(d);
  static String timeOfDay(DateTime d) => _w.timeOfDay(d);
  static String dayAndTime(DateTime d) => _w.dayAndTime(d);
  static String dayMonthLong(DateTime d) => _w.dayMonthLong(d);
  static String dayMonth(DateTime d) => _w.dayMonth(d);
  static String get forMe => _w.forMe;
  static String get showAsList => _w.showAsList;
  static String get showAsSky => _w.showAsSky;
  static String get readBlessing => _w.readBlessing;
  static String get earlier => _w.earlier;
  static String get later => _w.later;
  static String get newBlessing => _w.newBlessing;
  static String from(String name) => _w.from(name);
  static String get firstRun => _w.firstRun;
  static String toReview(int n) => _w.toReview(n);
  static String toReviewLabel(int n) => _w.toReviewLabel(n);
  static String get notReviewedNote => _w.notReviewedNote;
  static String countLine(int n, DateTime first) => _w.countLine(n, first);
  static String get close => _w.close;
  static String get begin => _w.begin;
  static String get beginLabel => _w.beginLabel;
  static String get nothingRecorded => _w.nothingRecorded;
  static String get listening => _w.listening;
  static String get discard => _w.discard;
  static String get amen => _w.amen;
  static String get holdToDiscard => _w.holdToDiscard;
  static String get holdToFinish => _w.holdToFinish;
  static String get discardLabel => _w.discardLabel;
  static String get amenLabel => _w.amenLabel;
  static String get discardTitle => _w.discardTitle;
  static String get discardBody => _w.discardBody;
  static String get keepListening => _w.keepListening;
  static String get paused => _w.paused;
  static String languageName(SpeechLanguage l) => _w.languageName(l);
  static String languageLabel(SpeechLanguage l) => _w.languageLabel(l);
  static String refused({required bool microphone, required bool speech}) => _w.refused(microphone: microphone, speech: speech);
  static String get openSettings => _w.openSettings;
  static String get untitled => _w.untitled;
  static String get wordsKept => _w.wordsKept;
  static String get writingWords => _w.writingWords;
  static String get recordingKeptBody => _w.recordingKeptBody;
  static String get noWordsHeard => _w.noWordsHeard;
  static String get recordingKept => _w.recordingKept;
  static String get wordsNotWrittenYet => _w.wordsNotWrittenYet;
  static String get wordsNotWritten => _w.wordsNotWritten;
  static String get reviewNow => _w.reviewNow;
  static String get saveForLater => _w.saveForLater;
  static String recoveredTitle(int n) => _w.recoveredTitle(n);
  static String recoveredBody(List<DateTime> began) => _w.recoveredBody(began);
  static String get recoveredLater => _w.recoveredLater;
  static String get back => _w.back;
  static String get edit => _w.edit;
  static String blessingFrom(String name) => _w.blessingFrom(name);
  static String forName(String name) => _w.forName(name);
  static String get asSpoken => _w.asSpoken;
  static String get noWords => _w.noWords;
  static String overheadNote(DateTime local, {required bool daylight}) => _w.overheadNote(local, daylight: daylight);
  static String get ringNote => _w.ringNote;
  static String get editTitle => _w.editTitle;
  static String get titleField => _w.titleField;
  static String get fromField => _w.fromField;
  static String get save => _w.save;
  static String get cancel => _w.cancel;
  static String get done => _w.done;
  static String get review => _w.review;
  static String get reviewThis => _w.reviewThis;
  static String get notReviewed => _w.notReviewed;
  static String get backFromReview => _w.backFromReview;
  static String get titlePlaceholder => _w.titlePlaceholder;
  static String get titleLabel => _w.titleLabel;
  static String get forField => _w.forField;
  static String get fromLabel => _w.fromLabel;
  static String get forLabel => _w.forLabel;
  static String get namePlaceholder => _w.namePlaceholder;
  static String get tags => _w.tags;
  static String get addTag => _w.addTag;
  static String removeTag(String t) => _w.removeTag(t);
  static String suggestTag(String t) => _w.suggestTag(t);
  static String get play => _w.play;
  static String get pause => _w.pause;
  static String get back10 => _w.back10;
  static String elapsed(String at, String of) => _w.elapsed(at, of);
  static String get wordsLabel => _w.wordsLabel;
  static String get wordsNotWrittenHere => _w.wordsNotWrittenHere;
  static String get noWordsHeardHere => _w.noWordsHeardHere;
  static String get typeWords => _w.typeWords;
  static String get finishTitle => _w.finishTitle;
  static String get finishBody => _w.finishBody;
  static String get finish => _w.finish;
  static String get notYet => _w.notYet;
  static String get deleteBlessing => _w.deleteBlessing;
  static String get deleteTitle => _w.deleteTitle;
  static String get deleteBody => _w.deleteBody;
  static String get delete => _w.delete;
  static String get keep => _w.keep;
  static String get polishWords => _w.polishWords;
  static String get polishWordsHint => _w.polishWordsHint;
  static String get nothingToPolish => _w.nothingToPolish;
  static String get spokenWords => _w.spokenWords;
  static String get polishedForReading => _w.polishedForReading;
  static String changes(int n) => _w.changes(n);
  static String keptOf(int k, int n) => _w.keptOf(k, n);
  static String get originalWords => _w.originalWords;
  static String polishedRow(int kept, int n) => _w.polishedRow(kept, n);
  static String get restoreAll => _w.restoreAll;
  static String get usePolished => _w.usePolished;
  static String get restoreOriginal => _w.restoreOriginal;
  static String get next => _w.next;
  static String get original => _w.original;
  static String get polished => _w.polished;
  static String get leftOut => _w.leftOut;
  static String get previousChange => _w.previousChange;
  static String get nextChange => _w.nextChange;
  static String stepOf(int i, int n) => _w.stepOf(i, n);
  static String get sizeLight => _w.sizeLight;
  static String get sizeModerate => _w.sizeModerate;
  static String get sizeHeavy => _w.sizeHeavy;
  static String get changeLight => _w.changeLight;
  static String get changeModerate => _w.changeModerate;
  static String get changeHeavy => _w.changeHeavy;
  static String get kindFiller => _w.kindFiller;
  static String get kindRepeat => _w.kindRepeat;
  static String get kindReworded => _w.kindReworded;
  static String get kindGrammar => _w.kindGrammar;
  static String get kindPunctuation => _w.kindPunctuation;
  static String changeLabel(String size, String kind, String was, String now, bool kept) => _w.changeLabel(size, kind, was, now, kept);
  static String polishedFrom(int kept) => _w.polishedFrom(kept);
  static String get reviewChanges => _w.reviewChanges;
  static String get locked => _w.locked;
  static String get unlock => _w.unlock;
  static String get unlockReason => _w.unlockReason;
  static String get turnOffLockReason => _w.turnOffLockReason;
  static String get more => _w.more;
  static String get settings => _w.settings;
  static String get backFromSettings => _w.backFromSettings;
  static String get appLock => _w.appLock;
  static String lockHint(LockMethod m) => _w.lockHint(m);
  static String get noPasscode => _w.noPasscode;
  static String get recordingLanguage => _w.recordingLanguage;
  static String get recordingLanguageHint => _w.recordingLanguageHint;
  static String get sameAsPhone => _w.sameAsPhone;
  static String get whereGiven => _w.whereGiven;
  static String get nearTemple => _w.nearTemple;
  static String near(double lat, double lon) => _w.near(lat, lon);
  static String get whereHint => _w.whereHint;
  static String get useMyLocation => _w.useMyLocation;
  static String get about => _w.about;
  static String get aboutBody => _w.aboutBody;
  static String version(String v) => _w.version(v);
  static String fullDate(DateTime d) => _w.fullDate(d);
  static String get share => _w.share;
  static String get shareTitle => _w.shareTitle;
  static String get asText => _w.asText;
  static String get asTextHint => _w.asTextHint;
  static String get asPdf => _w.asPdf;
  static String get asPdfHint => _w.asPdfHint;
  static String get shareNote => _w.shareNote;
  static String pageOf(int n, int total) => _w.pageOf(n, total);
  static String get asFile => _w.asFile;
  static String get asFileHint => _w.asFileHint;
  static String get aBlessing => _w.aBlessing;
  static String get receiveAsk => _w.receiveAsk;
  static String get receiveKeep => _w.receiveKeep;
  static String get notNow => _w.notNow;
  static String get alreadyHave => _w.alreadyHave;
  static String get alreadyDifferent => _w.alreadyDifferent;
  static String get replaceMine => _w.replaceMine;
  static String get keepMine => _w.keepMine;
  static String get fileNewer => _w.fileNewer;
  static String get fileUnreadable => _w.fileUnreadable;
  static String get ok => _w.ok;

  // ---- the first run (onboarding/) ----
  static String get appName => _w.appName;
  static String get welcome1 => _w.welcome1;
  static String get welcome2 => _w.welcome2;
  static String get welcome3 => _w.welcome3;
  static String get welcomeFree => _w.welcomeFree;
  static String get continueLabel => _w.continueLabel;
  static String get permsTitle => _w.permsTitle;
  static String get permsLede => _w.permsLede;
  static String get microphone => _w.microphone;
  static String get microphoneWhy => _w.microphoneWhy;
  static String get speechRecognition => _w.speechRecognition;
  static String get speechWhy => _w.speechWhy;
  static String get location => _w.location;
  static String get locationWhy => _w.locationWhy;
  static String get faceIdWhy => _w.faceIdWhy;
  static String get permissionOff => _w.permissionOff;
  static String get locationOff => _w.locationOff;
  static String get allowed => _w.allowed;
  static String get askingNow => _w.askingNow;
  static String get tryTitle => _w.tryTitle;
  static String get tryBody => _w.tryBody;
  static String get tryIt => _w.tryIt;
  static String get practice => _w.practice;
  static String get practiceListening => _w.practiceListening;
  static String get practiceHint => _w.practiceHint;
  static String get phoneWrote => _w.phoneWrote;
  static String get practiceKept => _w.practiceKept;
  static String get practiceWriting => _w.practiceWriting;
  static String get practiceUnavailable => _w.practiceUnavailable;
  static String get practiceSilent => _w.practiceSilent;
  static String get practiceFailed => _w.practiceFailed;
  static String get sharedWithYou => _w.sharedWithYou;
  static String get faceIdKeepReason => _w.faceIdKeepReason;
  static String rowOn(String name) => _w.rowOn(name);
  static String rowAsking(String name) => _w.rowAsking(name);
}

/// Every fixed string by name, for tests that look for English left on a Spanish screen and for
/// docs/spanish-strings.md. (The functions are checked by their own tests.)
extension WordsCatalogue on Words {
  Map<String, String> get catalogue => {
        'forMe': forMe,
        'showAsList': showAsList,
        'showAsSky': showAsSky,
        'readBlessing': readBlessing,
        'earlier': earlier,
        'later': later,
        'newBlessing': newBlessing,
        'firstRun': firstRun,
        'notReviewedNote': notReviewedNote,
        'close': close,
        'begin': begin,
        'beginLabel': beginLabel,
        'nothingRecorded': nothingRecorded,
        'listening': listening,
        'discard': discard,
        'amen': amen,
        'holdToDiscard': holdToDiscard,
        'holdToFinish': holdToFinish,
        'discardLabel': discardLabel,
        'amenLabel': amenLabel,
        'discardTitle': discardTitle,
        'discardBody': discardBody,
        'keepListening': keepListening,
        'paused': paused,
        'openSettings': openSettings,
        'untitled': untitled,
        'wordsKept': wordsKept,
        'writingWords': writingWords,
        'recordingKeptBody': recordingKeptBody,
        'noWordsHeard': noWordsHeard,
        'recordingKept': recordingKept,
        'wordsNotWrittenYet': wordsNotWrittenYet,
        'wordsNotWritten': wordsNotWritten,
        'reviewNow': reviewNow,
        'saveForLater': saveForLater,
        'recoveredLater': recoveredLater,
        'back': back,
        'edit': edit,
        'asSpoken': asSpoken,
        'noWords': noWords,
        'ringNote': ringNote,
        'editTitle': editTitle,
        'titleField': titleField,
        'fromField': fromField,
        'save': save,
        'cancel': cancel,
        'done': done,
        'review': review,
        'reviewThis': reviewThis,
        'notReviewed': notReviewed,
        'backFromReview': backFromReview,
        'titlePlaceholder': titlePlaceholder,
        'titleLabel': titleLabel,
        'forField': forField,
        'fromLabel': fromLabel,
        'forLabel': forLabel,
        'namePlaceholder': namePlaceholder,
        'tags': tags,
        'addTag': addTag,
        'play': play,
        'pause': pause,
        'back10': back10,
        'wordsLabel': wordsLabel,
        'wordsNotWrittenHere': wordsNotWrittenHere,
        'noWordsHeardHere': noWordsHeardHere,
        'typeWords': typeWords,
        'finishTitle': finishTitle,
        'finishBody': finishBody,
        'finish': finish,
        'notYet': notYet,
        'deleteBlessing': deleteBlessing,
        'deleteTitle': deleteTitle,
        'deleteBody': deleteBody,
        'delete': delete,
        'keep': keep,
        'polishWords': polishWords,
        'polishWordsHint': polishWordsHint,
        'nothingToPolish': nothingToPolish,
        'spokenWords': spokenWords,
        'polishedForReading': polishedForReading,
        'originalWords': originalWords,
        'restoreAll': restoreAll,
        'usePolished': usePolished,
        'restoreOriginal': restoreOriginal,
        'next': next,
        'original': original,
        'polished': polished,
        'leftOut': leftOut,
        'previousChange': previousChange,
        'nextChange': nextChange,
        'sizeLight': sizeLight,
        'sizeModerate': sizeModerate,
        'sizeHeavy': sizeHeavy,
        'changeLight': changeLight,
        'changeModerate': changeModerate,
        'changeHeavy': changeHeavy,
        'kindFiller': kindFiller,
        'kindRepeat': kindRepeat,
        'kindReworded': kindReworded,
        'kindGrammar': kindGrammar,
        'kindPunctuation': kindPunctuation,
        'reviewChanges': reviewChanges,
        'locked': locked,
        'unlock': unlock,
        'unlockReason': unlockReason,
        'turnOffLockReason': turnOffLockReason,
        'more': more,
        'settings': settings,
        'backFromSettings': backFromSettings,
        'appLock': appLock,
        'noPasscode': noPasscode,
        'recordingLanguage': recordingLanguage,
        'recordingLanguageHint': recordingLanguageHint,
        'sameAsPhone': sameAsPhone,
        'whereGiven': whereGiven,
        'nearTemple': nearTemple,
        'whereHint': whereHint,
        'useMyLocation': useMyLocation,
        'about': about,
        'aboutBody': aboutBody,
        'share': share,
        'shareTitle': shareTitle,
        'asText': asText,
        'asTextHint': asTextHint,
        'asPdf': asPdf,
        'asPdfHint': asPdfHint,
        'shareNote': shareNote,
        'asFile': asFile,
        'asFileHint': asFileHint,
        'aBlessing': aBlessing,
        'receiveAsk': receiveAsk,
        'receiveKeep': receiveKeep,
        'notNow': notNow,
        'alreadyHave': alreadyHave,
        'alreadyDifferent': alreadyDifferent,
        'replaceMine': replaceMine,
        'keepMine': keepMine,
        'fileNewer': fileNewer,
        'fileUnreadable': fileUnreadable,
        'appName': appName,
        'welcome1': welcome1,
        'welcome2': welcome2,
        'welcome3': welcome3,
        'welcomeFree': welcomeFree,
        'continueLabel': continueLabel,
        'permsTitle': permsTitle,
        'permsLede': permsLede,
        'microphone': microphone,
        'microphoneWhy': microphoneWhy,
        'speechRecognition': speechRecognition,
        'speechWhy': speechWhy,
        'location': location,
        'locationWhy': locationWhy,
        'faceIdWhy': faceIdWhy,
        'permissionOff': permissionOff,
        'locationOff': locationOff,
        'allowed': allowed,
        'askingNow': askingNow,
        'tryTitle': tryTitle,
        'tryBody': tryBody,
        'tryIt': tryIt,
        'practice': practice,
        'practiceListening': practiceListening,
        'practiceHint': practiceHint,
        'phoneWrote': phoneWrote,
        'practiceKept': practiceKept,
        'practiceWriting': practiceWriting,
        'practiceUnavailable': practiceUnavailable,
        'practiceSilent': practiceSilent,
        'practiceFailed': practiceFailed,
        'sharedWithYou': sharedWithYou,
        'faceIdKeepReason': faceIdKeepReason,
      };
}

/// The English words; [_Spanish] gives every one of them in Spanish.
class Words {
  const Words();

  UiLanguage get language => UiLanguage.english;

  // ---- dates ----
  List<String> get months => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  List<String> get days => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// "Tuesday, March 3, 2026"
  String longDate(DateTime d) => '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';

  /// "Mar 3, 2026"
  String shortDate(DateTime d) => '${months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

  /// "9:40 in the morning", "7:40 in the evening", "11:30 at night"
  String timeOfDay(DateTime d) {
    final h = d.hour, h12 = h % 12 == 0 ? 12 : h % 12, mm = d.minute.toString().padLeft(2, '0');
    final part = h >= 3 && h < 12
        ? 'in the morning'
        : h >= 12 && h < 17
            ? 'in the afternoon'
            : h >= 17 && h < 21
                ? 'in the evening'
                : 'at night';
    return '$h12:$mm $part';
  }

  /// "Tuesday, March 3, 9:40 in the morning"
  String dayAndTime(DateTime d) => '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${timeOfDay(d)}';

  /// "Saturday, November 15"
  String dayMonthLong(DateTime d) => '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';

  /// "Oct 4", in the list.
  String dayMonth(DateTime d) => '${months[d.month - 1].substring(0, 3)} ${d.day}';

  /// "One", "Two" ... "Twelve", then digits.
  String count(int n) {
    const words = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve'];
    return n < words.length ? words[n] : '$n';
  }

  // ---- home ----
  String get forMe => 'For me';
  String get showAsList => 'Show as a list';
  String get showAsSky => 'Show as a sky';
  String get readBlessing => 'Read this blessing';
  String get earlier => 'Earlier blessing';
  String get later => 'Later blessing';
  String get newBlessing => 'New blessing';
  String from(String name) => 'From $name';

  /// The home screen before the first blessing.
  String get firstRun => 'When a blessing is recorded, its light appears here.';

  /// The badge under the count line while drafts wait: "1 to review", "3 to review".
  String toReview(int n) => '$n to review';
  String toReviewLabel(int n) => n == 1 ? 'One blessing to review. Opens it.' : '$n blessings to review. Opens the oldest.';

  /// Under a draft's "From" line in the list.
  String get notReviewedNote => 'Not reviewed';

  /// "Five blessings since June 2024".
  String countLine(int n, DateTime first) {
    if (n == 0) return 'No blessings yet';
    return '${count(n)} ${n == 1 ? 'blessing' : 'blessings'} since ${months[first.month - 1]} ${first.year}';
  }

  // ---- recording ----
  String get close => 'Close';
  String get begin => 'Begin';
  String get beginLabel => 'Begin. Nothing is recorded until you press';
  String get nothingRecorded => 'Nothing is recorded until you press.';
  String get listening => 'Listening';
  String get discard => 'Discard';
  String get amen => 'Amen';
  String get holdToDiscard => 'Hold to discard';
  String get holdToFinish => 'Hold to finish';
  String get discardLabel => 'Discard. Hold to discard this recording';
  String get amenLabel => 'Amen. Hold to finish';
  String get discardTitle => 'Discard this recording?';
  String get discardBody => 'Nothing from it will be kept. It keeps listening while you decide.';
  String get keepListening => 'Keep listening';

  /// Instead of "Listening" while the phone has taken the microphone (a call); it carries on after.
  String get paused => 'Paused';

  // ---- language ----
  /// Each language in its own name, as the menu shows it, whatever the app's language.
  String languageName(SpeechLanguage l) => switch (l) {
        SpeechLanguage.english => 'English',
        SpeechLanguage.spanish => 'Español',
      };
  String languageLabel(SpeechLanguage l) => 'Language of the blessing: ${languageName(l)}';

  // ---- permission ----
  /// One calm line on the ready screen when something needed was refused.
  String refused({required bool microphone, required bool speech}) => microphone && speech
      ? 'The microphone and speech recognition are turned off for Upon Thy Head.'
      : microphone
          ? 'The microphone is turned off for Upon Thy Head.'
          : 'Speech recognition is turned off for Upon Thy Head.';
  String get openSettings => 'Open Settings';

  /// The title a blessing carries until it is reviewed.
  String get untitled => 'Blessing';

  // ---- after amen ----
  String get wordsKept => 'The words are kept';
  String get writingWords => 'Writing the words…';
  String get recordingKeptBody => 'The recording stays on this phone until you have reviewed the words. Then it is erased.';
  String get noWordsHeard => 'No words were heard';
  String get recordingKept => 'The recording is kept';
  String get wordsNotWrittenYet => 'The words could not be written on this phone yet. The recording stays here until they can be.';
  String get wordsNotWritten => 'The words could not be written this time. The recording stays on this phone.';
  String get reviewNow => 'Review now';
  String get saveForLater => 'Save for later';

  // ---- a recording kept when the app closed ----
  String recoveredTitle(int n) => n == 1 ? 'A recording was kept' : '${count(n)} recordings were kept';

  /// [began]: when each recording began, local to where it was given.
  String recoveredBody(List<DateTime> began) => began.length == 1
      ? 'The app closed while a blessing was being recorded on ${dayMonthLong(began.first)}, ${timeOfDay(began.first)}. '
          'What had been recorded is saved.'
      : 'The app closed while ${count(began.length).toLowerCase()} blessings were being recorded. What had been recorded is saved.';
  String get recoveredLater => 'Later';

  // ---- reading ----
  String get back => 'Back to the sky';
  String get edit => 'Edit';
  String blessingFrom(String name) => 'A blessing from $name';
  String forName(String name) => 'For $name';
  String get asSpoken => 'The words as they were spoken.';
  String get noWords => 'No words have been kept for this blessing yet.';

  /// The closing line under a blessing whose light sits where the sky was overhead.
  String overheadNote(DateTime local, {required bool daylight}) =>
      'Its light keeps the place in the sky that was straight overhead at ${timeOfDay(local)}${daylight ? ', behind the daylight.' : '.'}';

  /// The closing line under a blessing whose light sits on the ring (see RingPlacement).
  String get ringNote => 'Its light keeps its place in time on the ring of sky overhead.';

  // ---- editing ----
  String get editTitle => 'Edit this blessing';
  String get titleField => 'Title';
  String get fromField => 'From';
  String get save => 'Save';
  String get cancel => 'Cancel';

  // ---- review ----
  String get done => 'Done';
  String get review => 'Review';
  String get reviewThis => 'Review this blessing';
  String get notReviewed => 'Not yet reviewed. The recording stays on this phone until you finish.';
  String get backFromReview => 'Back. Everything typed is kept';
  String get titlePlaceholder => 'Blessing';
  String get titleLabel => 'Title';
  String get forField => 'For';
  String get fromLabel => 'From: who gave the blessing';
  String get forLabel => 'For: who it was given to';
  String get namePlaceholder => 'Name';
  String get tags => 'Tags';
  String get addTag => 'Add a tag';
  String removeTag(String t) => 'Remove tag $t';
  String suggestTag(String t) => 'Add tag $t';
  String get play => 'Play the recording';
  String get pause => 'Pause';
  String get back10 => 'Back ten seconds';
  String elapsed(String at, String of) => '$at of $of';
  String get wordsLabel => 'The words';
  String get wordsNotWrittenHere => 'The words could not be written on this phone. Listen to the recording and type them here.';
  String get noWordsHeardHere => 'No words were heard. Listen to the recording and type them here.';
  String get typeWords => 'Type the words';
  String get finishTitle => 'Finished reviewing?';
  String get finishBody => 'The recording will be erased from this phone. The words stay.';
  String get finish => 'Finish';
  String get notYet => 'Not yet';

  // ---- deleting ----
  String get deleteBlessing => 'Delete this blessing';
  String get deleteTitle => 'Delete this blessing?';
  String get deleteBody => 'Its words will be removed from this phone. This cannot be undone.';
  String get delete => 'Delete';
  String get keep => 'Keep';

  // ---- polish ----
  String get polishWords => 'Polish the words';
  String get polishWordsHint => 'Leaves out filler sounds and stumbled-over words. Every change can be undone.';
  String get nothingToPolish => 'Nothing to polish.';
  String get spokenWords => 'The spoken words';
  String get polishedForReading => 'Polished for reading';
  String changes(int n) => n == 1 ? '1 change' : '$n changes';
  String keptOf(int k, int n) => '$k of $n kept';
  String get originalWords => 'Original words';

  /// The review page's row once the words are polished.
  /// With none kept the words read as spoken, so the row says so.
  String polishedRow(int kept, int n) => kept == n ? changes(n) : kept == 0 ? originalWords : keptOf(kept, n);
  String get restoreAll => 'Restore all';
  String get usePolished => 'Use polished';
  String get restoreOriginal => 'Restore original';
  String get next => 'Next';
  String get original => 'Original';
  String get polished => 'Polished';
  String get leftOut => 'Left out';
  String get previousChange => 'Previous change';
  String get nextChange => 'Next change';
  String stepOf(int i, int n) => '$i of $n';
  String get sizeLight => 'light';
  String get sizeModerate => 'moderate';
  String get sizeHeavy => 'heavy';
  String get changeLight => 'Light change';
  String get changeModerate => 'Moderate change';
  String get changeHeavy => 'Heavy change';
  String get kindFiller => 'Filler removed';
  String get kindRepeat => 'Repeated word removed';
  String get kindReworded => 'Reworded';
  String get kindGrammar => 'Grammar corrected';
  String get kindPunctuation => 'Punctuation';

  /// VoiceOver, for a marked change in the words.
  String changeLabel(String size, String kind, String was, String now, bool kept) =>
      '$size. $kind. Original: $was. Polished: ${now.isEmpty ? leftOut : now}. ${kept ? 'Polished words in use' : 'Original words restored'}.';
  String polishedFrom(int kept) =>
      'Polished from the spoken words, with $kept ${kept == 1 ? 'small change' : 'small changes'}. The original is kept beside it.';
  String get reviewChanges => 'Review changes';

  // ---- the app lock ----
  String get locked => 'Locked';
  String get unlock => 'Unlock';
  String get unlockReason => 'Unlock your blessings';
  String get turnOffLockReason => 'Turn off the app lock';
  String get more => 'Settings';

  // ---- settings ----
  String get settings => 'Settings';
  String get backFromSettings => 'Back to the sky';
  String get appLock => 'App lock';

  /// Named for what this phone has.
  String lockHint(LockMethod m) => 'Asks for ${switch (m) {
        LockMethod.faceId => 'Face ID',
        LockMethod.touchId => 'Touch ID',
        LockMethod.opticId => 'Optic ID',
        _ => 'your passcode',
      }} when you open the app. Recording never waits for it.';
  String get noPasscode => 'Set a passcode on this iPhone to lock your blessings.';
  String get recordingLanguage => 'Language for recording';
  String get recordingLanguageHint => 'The language new recordings start in. Choosing one on the Begin screen changes it here too.';
  String get sameAsPhone => 'Same as this iPhone';
  String get whereGiven => 'Where blessings are given';
  String get nearTemple => 'Near Salt Lake Temple';
  String near(double lat, double lon) =>
      'Near ${lat.abs().toStringAsFixed(1)}° ${lat < 0 ? 'S' : 'N'}, ${lon.abs().toStringAsFixed(1)}° ${lon < 0 ? 'W' : 'E'}';
  String get whereHint => 'Decides which ring of sky the lights sit on. Only a rough place is kept.';
  String get useMyLocation => 'Use my location';
  String get about => 'About';
  String get aboutBody => 'Your words stay on this iPhone. Nothing is sent anywhere.';
  String version(String v) => 'Version $v';

  // ---- sharing (share/share.dart) ----
  /// "March 3, 2026": the date in a shared file's name.
  String fullDate(DateTime d) => '${months[d.month - 1]} ${d.day}, ${d.year}';
  String get share => 'Share';
  String get shareTitle => 'Share this blessing';
  String get asText => 'As text';
  String get asTextHint => 'The words, to paste or send in a message.';
  String get asPdf => 'As a PDF';
  String get asPdfHint => 'A page to print or keep.';
  String get shareNote => 'Once it leaves this phone, it is no longer private to it.';

  /// The PDF's footer from its second page: "2 of 3".
  String pageOf(int n, int total) => '$n of $total';

  // ---- the blessing file (share/blessing_file.dart, share/receive.dart) ----
  String get asFile => 'As a blessing file';
  String get asFileHint => 'Opens in Upon Thy Head on another iPhone.';
  String get aBlessing => 'A blessing';
  String get receiveAsk => 'Keep it with your blessings?';
  String get receiveKeep => 'Keep';
  String get notNow => 'Not now';
  String get alreadyHave => 'You already have this blessing.';
  String get alreadyDifferent => 'You already have this blessing, and this copy is different.';
  String get replaceMine => 'Replace mine';
  String get keepMine => 'Keep mine';
  String get fileNewer => 'This blessing was made with a newer version of Upon Thy Head. Update the app to open it.';
  String get fileUnreadable => 'This file could not be read.';
  String get ok => 'OK';

  // ---- the first run (onboarding/) ----
  String get appName => 'Upon Thy Head';
  String get welcome1 => 'Record a blessing as it is given.';
  String get welcome2 => 'The words are written on this phone. Nothing leaves it unless you share it.';
  String get welcome3 => 'The words as they were spoken are always kept.';
  String get welcomeFree => 'Free. No account. No ads.';
  String get continueLabel => 'Continue';
  String get permsTitle => 'A few things first';
  String get permsLede => 'The phone will ask for each of these. Each has a reason.';
  String get microphone => 'Microphone';
  String get microphoneWhy => 'To hear the blessing as it is given.';
  String get speechRecognition => 'Speech recognition';
  String get speechWhy => 'To write the words down, on this phone.';
  String get location => 'Location';
  String get locationWhy => 'To find the sky above you. Allow Once is enough.';
  String get faceIdWhy => 'To keep your blessings locked.';
  String get permissionOff => 'Off. You can turn it on in Settings.';
  String get locationOff => 'Off. The sky above the Salt Lake Temple will be used.';
  String get allowed => 'Allowed';
  String get askingNow => 'The phone is asking now';
  String get tryTitle => 'Try a few words first?';
  String get tryBody => 'Say anything, then hold Amen. You will see what the phone wrote. Nothing is kept.';
  String get tryIt => 'Try it';
  String get practice => 'Practice';
  String get practiceListening => 'Listening, for practice';
  String get practiceHint => 'This is only practice. Nothing is kept.';
  String get phoneWrote => 'What the phone wrote';
  String get practiceKept => 'Nothing from the practice is kept.';
  String get practiceWriting => 'Writing the words…';
  String get practiceUnavailable => 'This phone cannot write down words in this language yet. A real recording is still kept, and its words are written when the phone can.';
  String get practiceSilent => 'Nothing was heard. Try again when you record a blessing.';
  String get practiceFailed => 'The words could not be written this time.';
  String get sharedWithYou => 'A blessing has been shared with you.';
  String get faceIdKeepReason => 'Keep your blessings locked';
  String rowOn(String name) => '$name: allowed';
  String rowAsking(String name) => 'The phone is asking for $name now';
}

/// Every word in Spanish: plain, warm Latin American Spanish as used in the United States,
/// addressing the person as "tú". docs/spanish-strings.md lists each beside its English for a
/// native speaker to check.
class _Spanish implements Words {
  const _Spanish();

  @override
  UiLanguage get language => UiLanguage.spanish;

  // ---- dates ----
  @override
  List<String> get months =>
      const ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  static const _shortMonths = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
  @override
  List<String> get days => const ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  /// "domingo, 15 de noviembre de 2026"
  @override
  String longDate(DateTime d) => '${days[d.weekday - 1]}, ${d.day} de ${months[d.month - 1]} de ${d.year}';

  /// "15 nov 2026"
  @override
  String shortDate(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';

  /// "9:40 de la mañana", "3:15 de la tarde", "10:23 de la noche", "2:10 de la madrugada"
  /// (midnight to six is "la madrugada" in Spanish; "2:10 de la noche" reads oddly)
  @override
  String timeOfDay(DateTime d) {
    final h = d.hour, h12 = h % 12 == 0 ? 12 : h % 12, mm = d.minute.toString().padLeft(2, '0');
    final part = h < 6
        ? 'de la madrugada'
        : h < 12
            ? 'de la mañana'
            : h < 19
                ? 'de la tarde'
                : 'de la noche';
    return '$h12:$mm $part';
  }

  /// "a las 9:40 de la mañana", "a la 1:15 de la tarde"
  String _atTime(DateTime d) => '${d.hour % 12 == 1 ? 'a la' : 'a las'} ${timeOfDay(d)}';

  /// "martes, 3 de marzo, 9:40 de la mañana"
  @override
  String dayAndTime(DateTime d) => '${dayMonthLong(d)}, ${timeOfDay(d)}';

  /// "sábado, 15 de noviembre"
  @override
  String dayMonthLong(DateTime d) => '${days[d.weekday - 1]}, ${d.day} de ${months[d.month - 1]}';

  /// "4 oct"
  @override
  String dayMonth(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]}';

  /// Feminine, for "bendición" and "grabación": "Una", "Dos" ... "Doce", then digits.
  @override
  String count(int n) {
    const words = ['Ninguna', 'Una', 'Dos', 'Tres', 'Cuatro', 'Cinco', 'Seis', 'Siete', 'Ocho', 'Nueve', 'Diez', 'Once', 'Doce'];
    return n < words.length ? words[n] : '$n';
  }

  // ---- home ----
  @override
  String get forMe => 'Para mí';
  @override
  String get showAsList => 'Ver como lista';
  @override
  String get showAsSky => 'Ver como cielo';
  @override
  String get readBlessing => 'Leer esta bendición';
  @override
  String get earlier => 'Bendición anterior';
  @override
  String get later => 'Bendición siguiente';
  @override
  String get newBlessing => 'Nueva bendición';
  @override
  String from(String name) => 'De $name';
  @override
  String get firstRun => 'Cuando se grabe una bendición, su luz aparecerá aquí.';
  @override
  String toReview(int n) => '$n por revisar';
  @override
  String toReviewLabel(int n) =>
      n == 1 ? 'Una bendición por revisar. Ábrela.' : '$n bendiciones por revisar. Abre la más antigua.';
  @override
  String get notReviewedNote => 'Sin revisar';

  /// "Cinco bendiciones desde junio de 2024", "Una bendición desde junio de 2024"
  @override
  String countLine(int n, DateTime first) {
    if (n == 0) return 'Todavía no hay bendiciones';
    return '${count(n)} ${n == 1 ? 'bendición' : 'bendiciones'} desde ${months[first.month - 1]} de ${first.year}';
  }

  // ---- recording ----
  @override
  String get close => 'Cerrar';
  @override
  String get begin => 'Comenzar';
  @override
  String get beginLabel => 'Comenzar. No se graba nada hasta que lo presiones';
  @override
  String get nothingRecorded => 'No se graba nada hasta que lo presiones.';
  @override
  String get listening => 'Escuchando';
  @override
  String get discard => 'Descartar';
  @override
  String get amen => 'Amén';
  @override
  String get holdToDiscard => 'Mantén presionado para descartar';
  @override
  String get holdToFinish => 'Mantén presionado para terminar';
  @override
  String get discardLabel => 'Descartar. Mantén presionado para descartar esta grabación';
  @override
  String get amenLabel => 'Amén. Mantén presionado para terminar';
  @override
  String get discardTitle => '¿Descartar esta grabación?';
  @override
  String get discardBody => 'No se guardará nada de ella. Sigue escuchando mientras decides.';
  @override
  String get keepListening => 'Seguir escuchando';
  @override
  String get paused => 'En pausa';

  // ---- language ----
  @override
  String languageName(SpeechLanguage l) => switch (l) {
        SpeechLanguage.english => 'English',
        SpeechLanguage.spanish => 'Español',
      };
  @override
  String languageLabel(SpeechLanguage l) => 'Idioma de la bendición: ${languageName(l)}';

  // ---- permission ----
  @override
  String refused({required bool microphone, required bool speech}) => microphone && speech
      ? 'El micrófono y el reconocimiento de voz están desactivados para Upon Thy Head.'
      : microphone
          ? 'El micrófono está desactivado para Upon Thy Head.'
          : 'El reconocimiento de voz está desactivado para Upon Thy Head.';

  /// The iPhone's own Settings app, by the name Latin American iOS gives it.
  @override
  String get openSettings => 'Abrir Configuración';
  @override
  String get untitled => 'Bendición';

  // ---- after amen ----
  @override
  String get wordsKept => 'Las palabras están guardadas';
  @override
  String get writingWords => 'Escribiendo las palabras…';
  @override
  String get recordingKeptBody => 'La grabación se queda en este teléfono hasta que hayas revisado las palabras. Después se borra.';
  @override
  String get noWordsHeard => 'No se oyeron palabras';
  @override
  String get recordingKept => 'La grabación está guardada';
  @override
  String get wordsNotWrittenYet =>
      'Todavía no se pudieron escribir las palabras en este teléfono. La grabación se queda aquí hasta que se pueda.';
  @override
  String get wordsNotWritten => 'Esta vez no se pudieron escribir las palabras. La grabación se queda en este teléfono.';
  @override
  String get reviewNow => 'Revisar ahora';
  @override
  String get saveForLater => 'Guardar para después';

  // ---- a recording kept when the app closed ----
  @override
  String recoveredTitle(int n) => n == 1 ? 'Se guardó una grabación' : 'Se guardaron ${count(n).toLowerCase()} grabaciones';

  /// "La app se cerró mientras se grababa una bendición el sábado 15 de noviembre, a las 9:40 de la noche. ..."
  @override
  String recoveredBody(List<DateTime> began) {
    final d = began.first;
    return began.length == 1
        ? 'La app se cerró mientras se grababa una bendición el ${days[d.weekday - 1]} ${d.day} de ${months[d.month - 1]}, '
            '${_atTime(d)}. Lo que se había grabado está guardado.'
        : 'La app se cerró mientras se grababan ${count(began.length).toLowerCase()} bendiciones. '
            'Lo que se había grabado está guardado.';
  }

  @override
  String get recoveredLater => 'Más tarde';

  // ---- reading ----
  @override
  String get back => 'Volver al cielo';
  @override
  String get edit => 'Editar';
  @override
  String blessingFrom(String name) => 'Una bendición de $name';
  @override
  String forName(String name) => 'Para $name';
  @override
  String get asSpoken => 'Las palabras tal como se dijeron.';
  @override
  String get noWords => 'Todavía no se han guardado palabras para esta bendición.';
  @override
  String overheadNote(DateTime local, {required bool daylight}) =>
      'Su luz guarda el lugar del cielo que estaba justo encima ${_atTime(local)}${daylight ? ', detrás de la luz del día.' : '.'}';
  @override
  String get ringNote => 'Su luz guarda su lugar en el tiempo, en el anillo del cielo que está en lo alto.';

  // ---- editing ----
  @override
  String get editTitle => 'Editar esta bendición';
  @override
  String get titleField => 'Título';
  @override
  String get fromField => 'De';
  @override
  String get save => 'Guardar';
  @override
  String get cancel => 'Cancelar';

  // ---- review ----
  @override
  String get done => 'Listo';
  @override
  String get review => 'Revisar';
  @override
  String get reviewThis => 'Revisar esta bendición';
  @override
  String get notReviewed => 'Todavía sin revisar. La grabación se queda en este teléfono hasta que termines.';
  @override
  String get backFromReview => 'Atrás. Todo lo que escribiste se guarda';
  @override
  String get titlePlaceholder => 'Bendición';
  @override
  String get titleLabel => 'Título';
  @override
  String get forField => 'Para';
  @override
  String get fromLabel => 'De: quién dio la bendición';
  @override
  String get forLabel => 'Para: a quién se le dio';
  @override
  String get namePlaceholder => 'Nombre';
  @override
  String get tags => 'Etiquetas';
  @override
  String get addTag => 'Agregar una etiqueta';
  @override
  String removeTag(String t) => 'Quitar la etiqueta $t';
  @override
  String suggestTag(String t) => 'Agregar la etiqueta $t';
  @override
  String get play => 'Reproducir la grabación';
  @override
  String get pause => 'Pausar';
  @override
  String get back10 => 'Retroceder diez segundos';
  @override
  String elapsed(String at, String of) => '$at de $of';
  @override
  String get wordsLabel => 'Las palabras';
  @override
  String get wordsNotWrittenHere =>
      'No se pudieron escribir las palabras en este teléfono. Escucha la grabación y escríbelas aquí.';
  @override
  String get noWordsHeardHere => 'No se oyeron palabras. Escucha la grabación y escríbelas aquí.';
  @override
  String get typeWords => 'Escribe las palabras';
  @override
  String get finishTitle => '¿Terminaste de revisar?';
  @override
  String get finishBody => 'La grabación se borrará de este teléfono. Las palabras se quedan.';
  @override
  String get finish => 'Terminar';
  @override
  String get notYet => 'Todavía no';

  // ---- deleting ----
  @override
  String get deleteBlessing => 'Eliminar esta bendición';
  @override
  String get deleteTitle => '¿Eliminar esta bendición?';
  @override
  String get deleteBody => 'Sus palabras se quitarán de este teléfono. Esto no se puede deshacer.';
  @override
  String get delete => 'Eliminar';
  @override
  String get keep => 'Conservar';

  // ---- polish ----
  @override
  String get polishWords => 'Pulir las palabras';
  @override
  String get polishWordsHint => 'Quita las muletillas y las palabras repetidas sin querer. Cada cambio se puede deshacer.';
  @override
  String get nothingToPolish => 'No hay nada que pulir.';
  @override
  String get spokenWords => 'Las palabras dichas';
  @override
  String get polishedForReading => 'Pulidas para leer';
  @override
  String changes(int n) => n == 1 ? '1 cambio' : '$n cambios';
  @override
  String keptOf(int k, int n) => k == 1 ? 'Se conserva 1 de $n' : 'Se conservan $k de $n';
  @override
  String get originalWords => 'Palabras originales';
  @override
  String polishedRow(int kept, int n) => kept == n ? changes(n) : kept == 0 ? originalWords : keptOf(kept, n);
  @override
  String get restoreAll => 'Restaurar todo';
  @override
  String get usePolished => 'Usar pulidas';
  @override
  String get restoreOriginal => 'Restaurar original';
  @override
  String get next => 'Siguiente';
  @override
  String get original => 'Original';
  @override
  String get polished => 'Pulido';
  @override
  String get leftOut => 'Omitido';
  @override
  String get previousChange => 'Cambio anterior';
  @override
  String get nextChange => 'Cambio siguiente';
  @override
  String stepOf(int i, int n) => '$i de $n';
  @override
  String get sizeLight => 'leve';
  @override
  String get sizeModerate => 'moderado';
  @override
  String get sizeHeavy => 'grande';
  @override
  String get changeLight => 'Cambio leve';
  @override
  String get changeModerate => 'Cambio moderado';
  @override
  String get changeHeavy => 'Cambio grande';
  @override
  String get kindFiller => 'Muletilla quitada';
  @override
  String get kindRepeat => 'Palabra repetida quitada';
  @override
  String get kindReworded => 'Reformulado';
  @override
  String get kindGrammar => 'Gramática corregida';
  @override
  String get kindPunctuation => 'Puntuación';
  @override
  String changeLabel(String size, String kind, String was, String now, bool kept) =>
      '$size. $kind. Original: $was. Pulido: ${now.isEmpty ? leftOut : now}. '
      '${kept ? 'Se usan las palabras pulidas' : 'Se restauraron las palabras originales'}.';
  @override
  String polishedFrom(int kept) =>
      'Pulidas a partir de las palabras dichas, con $kept ${kept == 1 ? 'pequeño cambio' : 'pequeños cambios'}. '
      'Las originales se guardan junto a ellas.';
  @override
  String get reviewChanges => 'Revisar los cambios';

  // ---- the app lock ----
  @override
  String get locked => 'Bloqueado';
  @override
  String get unlock => 'Desbloquear';
  @override
  String get unlockReason => 'Desbloquea tus bendiciones';
  @override
  String get turnOffLockReason => 'Desactivar el bloqueo de la app';
  @override
  String get more => 'Configuración';

  // ---- settings ----
  @override
  String get settings => 'Configuración';
  @override
  String get backFromSettings => 'Volver al cielo';
  @override
  String get appLock => 'Bloqueo de la app';
  @override
  String lockHint(LockMethod m) => 'Pide ${switch (m) {
        LockMethod.faceId => 'Face ID',
        LockMethod.touchId => 'Touch ID',
        LockMethod.opticId => 'Optic ID',
        _ => 'tu código',
      }} al abrir la app. Para grabar nunca hace falta.';
  @override
  String get noPasscode => 'Configura un código en este iPhone para bloquear tus bendiciones.';
  @override
  String get recordingLanguage => 'Idioma para grabar';
  @override
  String get recordingLanguageHint =>
      'El idioma en que empiezan las grabaciones nuevas. Si eliges uno en la pantalla Comenzar, también cambia aquí.';
  @override
  String get sameAsPhone => 'Igual que este iPhone';
  @override
  String get whereGiven => 'Dónde se dan las bendiciones';
  @override
  String get nearTemple => 'Cerca del Templo de Salt Lake';
  @override
  String near(double lat, double lon) =>
      'Cerca de ${lat.abs().toStringAsFixed(1)}° ${lat < 0 ? 'S' : 'N'}, ${lon.abs().toStringAsFixed(1)}° ${lon < 0 ? 'O' : 'E'}';
  @override
  String get whereHint => 'Decide en qué anillo del cielo quedan las luces. Solo se guarda un lugar aproximado.';
  @override
  String get useMyLocation => 'Usar mi ubicación';
  @override
  String get about => 'Acerca de';
  @override
  String get aboutBody => 'Tus palabras se quedan en este iPhone. No se envía nada a ningún lado.';
  @override
  String version(String v) => 'Versión $v';

  // ---- compartir ----
  /// "3 de marzo de 2026"
  @override
  String fullDate(DateTime d) => '${d.day} de ${months[d.month - 1]} de ${d.year}';
  @override
  String get share => 'Compartir';
  @override
  String get shareTitle => 'Compartir esta bendición';
  @override
  String get asText => 'Como texto';
  @override
  String get asTextHint => 'Las palabras, para pegar o enviar en un mensaje.';
  @override
  String get asPdf => 'Como PDF';
  @override
  String get asPdfHint => 'Una página para imprimir o guardar.';
  @override
  String get shareNote => 'Una vez que sale de este teléfono, ya no es privada.';
  @override
  String pageOf(int n, int total) => '$n de $total';

  // ---- el archivo de bendición ----
  @override
  String get asFile => 'Como archivo de bendición';
  @override
  String get asFileHint => 'Se abre en Upon Thy Head en otro iPhone.';
  @override
  String get aBlessing => 'Una bendición';
  @override
  String get receiveAsk => '¿Guardarla con tus bendiciones?';
  @override
  String get receiveKeep => 'Guardar';
  @override
  String get notNow => 'Ahora no';
  @override
  String get alreadyHave => 'Ya tienes esta bendición.';
  @override
  String get alreadyDifferent => 'Ya tienes esta bendición, y esta copia es diferente.';
  @override
  String get replaceMine => 'Reemplazar la mía';
  @override
  String get keepMine => 'Conservar la mía';
  @override
  String get fileNewer => 'Esta bendición se hizo con una versión más reciente de Upon Thy Head. Actualiza la app para abrirla.';
  @override
  String get fileUnreadable => 'No se pudo leer este archivo.';
  @override
  String get ok => 'OK';

  // ---- la primera vez ----
  @override
  String get appName => 'Upon Thy Head';
  @override
  String get welcome1 => 'Graba una bendición mientras se da.';
  @override
  String get welcome2 => 'Las palabras se escriben en este teléfono. Nada sale de él si tú no lo compartes.';
  @override
  String get welcome3 => 'Las palabras tal como se dijeron siempre se guardan.';
  @override
  String get welcomeFree => 'Gratis. Sin cuenta. Sin anuncios.';
  @override
  String get continueLabel => 'Continuar';
  @override
  String get permsTitle => 'Primero, unas cosas';
  @override
  String get permsLede => 'El teléfono te preguntará por cada una. Cada una tiene su razón.';
  @override
  String get microphone => 'Micrófono';
  @override
  String get microphoneWhy => 'Para oír la bendición mientras se da.';
  @override
  String get speechRecognition => 'Reconocimiento de voz';
  @override
  String get speechWhy => 'Para escribir las palabras, en este teléfono.';
  @override
  String get location => 'Ubicación';
  @override
  String get locationWhy => 'Para encontrar el cielo sobre ti. Con «Permitir una vez» basta.';
  @override
  String get faceIdWhy => 'Para mantener tus bendiciones bloqueadas.';
  @override
  String get permissionOff => 'Desactivado. Puedes activarlo en Configuración.';
  @override
  String get locationOff => 'Desactivada. Se usará el cielo sobre el Templo de Salt Lake.';
  @override
  String get allowed => 'Permitido';
  @override
  String get askingNow => 'El teléfono está preguntando';
  @override
  String get tryTitle => '¿Probar primero con unas palabras?';
  @override
  String get tryBody => 'Di cualquier cosa y luego mantén presionado Amén. Verás lo que escribió el teléfono. No se guarda nada.';
  @override
  String get tryIt => 'Probar';
  @override
  String get practice => 'Práctica';
  @override
  String get practiceListening => 'Escuchando, de práctica';
  @override
  String get practiceHint => 'Es solo una práctica. No se guarda nada.';
  @override
  String get phoneWrote => 'Lo que escribió el teléfono';
  @override
  String get practiceKept => 'No se guarda nada de la práctica.';
  @override
  String get practiceWriting => 'Escribiendo las palabras…';
  @override
  String get practiceUnavailable => 'Este teléfono todavía no puede escribir las palabras en este idioma. Una grabación de verdad sí se guarda, y sus palabras se escriben cuando el teléfono pueda.';
  @override
  String get practiceSilent => 'No se oyó nada. Inténtalo de nuevo cuando grabes una bendición.';
  @override
  String get practiceFailed => 'Esta vez no se pudieron escribir las palabras.';
  @override
  String get sharedWithYou => 'Alguien compartió una bendición contigo.';
  @override
  String get faceIdKeepReason => 'Mantener tus bendiciones bloqueadas';
  @override
  String rowOn(String name) => '$name: permitido';
  @override
  String rowAsking(String name) => 'El teléfono está preguntando por $name';
}
