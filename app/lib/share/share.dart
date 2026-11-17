import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/blessing.dart';
import '../strings.dart';

/// What a finished blessing becomes when it leaves the app: plain text, or a PDF made natively
/// (ios/Runner/Share.swift). The words are the ones the reading page shows. Labels and dates are in
/// the phone's language ([Strings]); the blessing's own title, names and words are never changed.

/// The title as the reading page shows it.
String shareTitle(Blessing b, Words w) => Strings.isUntitled(b.title) || b.title.trim().isEmpty ? w.untitled : b.title.trim();

/// The words in paragraphs, as the reading page splits them.
List<String> shareParagraphs(Blessing b) =>
    b.words.split(RegExp(r'\n\s*\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// The text handed to the share sheet:
///
///     Comfort before surgery
///     Tuesday, March 3, 2026
///     A blessing from Dad
///     For Emma
///
///     The words…
///
/// The giver and the recipient only when known. Nothing else: no link, no app name.
String shareText(Blessing b, [Words? words]) {
  final w = words ?? Strings.wordsFor(Strings.language);
  final from = b.from.trim(), to = b.recipient.trim();
  final head = [
    shareTitle(b, w),
    w.longDate(b.local),
    if (from.isNotEmpty) w.blessingFrom(from),
    if (to.isNotEmpty) w.forName(to),
  ].join('\n');
  final paras = shareParagraphs(b);
  return paras.isEmpty ? head : '$head\n\n${paras.join('\n\n')}';
}

/// Characters a file name cannot hold (on iOS, macOS, Windows and in most apps that receive one).
final _unsafe = RegExp(r'[/\\:*?"<>|\u0000-\u001f\u007f]');

/// The longest title kept in a file name, in characters (the whole name stays well under 255 bytes).
const fileTitleMax = 100;

/// "Comfort before surgery, March 3, 2026.pdf": the title and the date, with what a file name
/// cannot hold taken out ("/" and ":" become spaces, so words stay apart).
String shareFileName(Blessing b, [Words? words]) {
  final w = words ?? Strings.wordsFor(Strings.language);
  var t = shareTitle(b, w).replaceAll(_unsafe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  // a name starting with a dot is hidden on a Mac
  t = t.replaceFirst(RegExp(r'^[.\s]+'), '').replaceFirst(RegExp(r'[.\s]+$'), '');
  final runes = t.runes.toList();
  if (runes.length > fileTitleMax) {
    var cut = String.fromCharCodes(runes.take(fileTitleMax));
    final space = cut.lastIndexOf(' ');
    if (space > fileTitleMax * .6) cut = cut.substring(0, space);
    t = '${cut.replaceFirst(RegExp(r'[\s,.;-]+$'), '')}…';
  }
  if (t.isEmpty) t = w.untitled;
  return '$t, ${w.fullDate(b.local)}.pdf';
}

/// What the native side lays out as the PDF.
Map<String, Object> sharePdf(Blessing b, [Words? words]) {
  final w = words ?? Strings.wordsFor(Strings.language);
  final from = b.from.trim(), to = b.recipient.trim();
  return {
    'fileName': shareFileName(b, w),
    'title': shareTitle(b, w),
    'date': w.longDate(b.local),
    'from': from.isEmpty ? '' : w.blessingFrom(from),
    'recipient': to.isEmpty ? '' : w.forName(to),
    'paragraphs': shareParagraphs(b),
    // the footer from page 2, "2 of 3", with the numbers filled in natively
    'pageOf': pageOfTemplate(w),
  };
}

/// [Words.pageOf] with "{n}" and "{total}" where the numbers go.
String pageOfTemplate(Words w) => w.pageOf(90901, 90902).replaceAll('90901', '{n}').replaceAll('90902', '{total}');

/// The system share sheet.
abstract class ShareApi {
  /// Open the share sheet with [text]; [subject] is offered to mail and similar. Completes when the
  /// sheet has closed.
  Future<void> text(String text, String subject);

  /// Make the PDF in a temporary folder and open the share sheet with it. Completes when the sheet
  /// has closed and the file is gone.
  Future<void> pdf(Map<String, Object> pdf);

  /// Write the `.blessing` file [bytes] as [fileName] in a temporary folder and open the share sheet
  /// with it. Completes when the sheet has closed and the file is gone: true when something was
  /// done with it (sent, saved, copied), false when the sheet was cancelled.
  Future<bool> file(String fileName, Uint8List bytes, String title);

  /// Open the share sheet with a blessing's link, as a URL (so Messages shows it as a link), titled
  /// [title]. Completes when the sheet has closed: true when it was sent somewhere.
  Future<bool> link(String url, String title);

  /// Ready for blessing files that arrive: answers those that came before (the app was launched by
  /// one) and calls [onIncoming] with each later one.
  Future<List<IncomingFile>> receiving(void Function(IncomingFile) onIncoming);

  /// Close the share sheet now if it is up (the app locked), and remove what was made for it.
  Future<void> dismiss();

  /// Remove anything left from an earlier share (at launch).
  Future<void> clean();
}

/// iOS: ios/Runner/Share.swift; Android: android/app/src/main/kotlin/…/ShareChannel.kt; on
/// `upon_thy_head/share`.
class NativeShareApi implements ShareApi {
  static const _channel = MethodChannel('upon_thy_head/share');

  @override
  Future<void> text(String text, String subject) => _channel.invokeMethod<void>('text', {'text': text, 'subject': subject});

  @override
  Future<void> pdf(Map<String, Object> pdf) => _channel.invokeMethod<void>('pdf', pdf);

  @override
  Future<bool> file(String fileName, Uint8List bytes, String title) async =>
      await _channel.invokeMethod<bool>('file', {'fileName': fileName, 'bytes': bytes, 'title': title}) ?? false;

  @override
  Future<bool> link(String url, String title) async => await _channel.invokeMethod<bool>('link', {'url': url, 'title': title}) ?? false;

  @override
  Future<List<IncomingFile>> receiving(void Function(IncomingFile) onIncoming) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') onIncoming(IncomingFile.from(call.arguments));
      return null;
    });
    final waiting = await _channel.invokeMethod<List<Object?>>('receiving') ?? const [];
    return [for (final w in waiting) IncomingFile.from(w)];
  }

  @override
  Future<void> dismiss() async {
    try {
      await _channel.invokeMethod<void>('dismiss');
    } catch (e) {
      debugPrint('share: $e');
    }
  }

  @override
  Future<void> clean() async {
    try {
      await _channel.invokeMethod<void>('clean');
    } catch (e) {
      debugPrint('share: $e');
    }
  }

  /// Android: the link onto the clipboard marked sensitive (ClipDescription.EXTRA_IS_SENSITIVE).
  static Future<void> copySensitive(String text) => _channel.invokeMethod<void>('copy', {'text': text});

  /// Tests: whether the system share sheet is up, and the paper this phone's region uses.
  static Future<bool> debugShowing() async => await _channel.invokeMethod<bool>('debugShowing') ?? false;
  static Future<String> debugPaper() async => await _channel.invokeMethod<String>('debugPaper') ?? '';

  /// Tests: what the last share sheet was handed (kind, name, type, …), and any `.blessing` file
  /// left anywhere in the app's folders.
  static Future<List<Map<String, Object?>>> debugItems() async =>
      [for (final m in await _channel.invokeMethod<List<Object?>>('debugItems') ?? const []) (m as Map).cast<String, Object?>()];
  static Future<List<String>> debugReceivedLeft() async => [...?await _channel.invokeListMethod<String>('debugReceivedLeft')];
}

/// A blessing file as iOS handed it over: its bytes, or why there are none.
class IncomingFile {
  const IncomingFile({this.bytes, this.tooLarge = false, this.link});
  final Uint8List? bytes;
  final bool tooLarge;

  /// A blessing link (`https://uponthyhead.app/b/<id>#<key>`) that opened the app, instead of a
  /// file. It holds the key: never logged.
  final String? link;

  factory IncomingFile.from(Object? m) {
    final map = m is Map ? m : const {};
    final b = map['bytes'], l = map['link'];
    return IncomingFile(bytes: b is Uint8List ? b : null, tooLarge: map['tooLarge'] == true, link: l is String ? l : null);
  }
}

/// No share sheet (tests on the host).
class NoShareApi implements ShareApi {
  final List<String> calls = [];
  @override
  Future<void> text(String text, String subject) async => calls.add('text');
  @override
  Future<void> pdf(Map<String, Object> pdf) async => calls.add('pdf');
  @override
  Future<bool> file(String fileName, Uint8List bytes, String title) async {
    calls.add('file');
    return completes;
  }

  @override
  Future<bool> link(String url, String title) async {
    calls.add('link');
    links.add(url);
    return completes;
  }

  /// What the system sheet answers (sent, or cancelled), and the links it was handed.
  bool completes = true;
  final List<String> links = [];
  @override
  Future<List<IncomingFile>> receiving(void Function(IncomingFile) onIncoming) async {
    deliver = onIncoming;
    return const [];
  }

  /// Tests on the host: hand the app a file as iOS would.
  void Function(IncomingFile)? deliver;
  @override
  Future<void> dismiss() async => calls.add('dismiss');
  @override
  Future<void> clean() async => calls.add('clean');
}
