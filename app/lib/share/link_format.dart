import 'dart:convert';
import 'dart:typed_data';

/// A blessing sent by link: the link's form and the locked copy's frame, exactly as
/// `website/PROTOCOL.md` (format version 1) says. No cryptography here: locking and opening are the
/// platform's own (share/link_crypto.dart); this file only builds and checks what goes around them.
///
///     https://uponthyhead.app/b/<id>#<key>
///
///     locked copy: 0x01 ‖ nonce (12) ‖ ciphertext ‖ tag (16), AES-256-GCM, additional data 0x01

/// The service, and the site the link names. One constant; tests and this Mac's local server set it
/// at build time with `--dart-define=LINK_SERVICE=http://localhost:4319`.
const linkService = String.fromEnvironment('LINK_SERVICE', defaultValue: 'https://uponthyhead.app');

/// The locked copy's first byte, and the additional data it is locked with.
const linkVersion = 1;
const linkKeyBytes = 32;
const linkNonceBytes = 12;
const linkTagBytes = 16;

/// The smallest locked copy: the version, the nonce, the tag and the two bytes of `{}`.
const linkMinBytes = 1 + linkNonceBytes + linkTagBytes + 2;

/// The largest locked copy the service takes. A 2,500-word blessing is about 17 KB, an ordinary
/// one 3 to 6 KB; a family member's whole ring handed over (share/ring_file.dart) is one locked
/// copy, so the cap is 512 KiB (2026-11-18; it was 64 KiB): about 100 ordinary blessings, or 30 of
/// the longest. An app from before reads at most 64 KiB and calls a larger copy unreadable.
const linkMaxBytes = 524288;

/// The largest locked copy of one blessing: 64 KiB, as before rings, so every single-blessing link
/// still opens in an app made before rings (which reads no more than this).
const blessingLinkMaxBytes = 65536;

/// How long a link lasts (the service decides; this is only for words shown before it answers).
const linkDays = 30;

/// Why a link does not open, in the contract's order (the names are protocol-vectors.json's).
enum LinkError {
  /// What follows `#` is not a 43-character canonical base64url key.
  key,

  /// Too short, too long, or a zero first byte.
  damaged,

  /// A later format: the first byte, or the record's version.
  newer,

  /// It does not authenticate: the wrong key, or any byte changed or missing.
  locked,

  /// It opens, but what is inside is not a blessing this app can read.
  record,
}

final _id = RegExp(r'^[A-Za-z0-9_-]{22}$');
final _key = RegExp(r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$');

/// A link's id, as the server chooses it: 22 base64url characters.
bool isLinkId(String s) => _id.hasMatch(s);

/// The key in a link's fragment, or null when it is not exactly a canonical key.
Uint8List? keyOfFragment(String fragment) {
  if (!_key.hasMatch(fragment)) return null;
  final bytes = base64Url.decode('$fragment=');
  return bytes.length == linkKeyBytes ? bytes : null;
}

/// The key as the fragment carries it: base64url without padding.
String fragmentOfKey(List<int> key) {
  assert(key.length == linkKeyBytes);
  return base64Url.encode(key).replaceAll('=', '');
}

/// The link, as the app builds it from the server's id and the key it holds.
String linkOf(String id, List<int> key, {String site = linkService}) => '$site/b/$id#${fragmentOfKey(key)}';

/// A link that was opened: its id, and what was after `#` (not yet checked; see [keyOfFragment]).
typedef LinkParts = ({String id, String fragment});

/// The id and fragment of [url] when it is a blessing link: `https://uponthyhead.app/b/<id>#<key>`,
/// the same on the site the build points at, or (in debug builds only, for the simulator, which
/// cannot hand an app a universal link) `uponthyhead-test://b/<id>#<key>`. Null for anything else.
/// The link's host never decides where the copy is fetched from: that is always [linkService].
LinkParts? linkPartsOf(String url, {bool debug = false}) {
  final Uri u;
  try {
    u = Uri.parse(url);
  } on FormatException {
    return null;
  }
  final String path;
  if (u.scheme == 'https' && (u.host == 'uponthyhead.app' || u.host == 'www.uponthyhead.app')) {
    path = u.path;
  } else if (_sameSite(u, Uri.parse(linkService))) {
    path = u.path;
  } else if (debug && u.scheme == 'uponthyhead-test') {
    path = '/${u.host}${u.path}';
  } else {
    return null;
  }
  final m = RegExp(r'^/b/([^/]+)/?$').firstMatch(path);
  if (m == null) return null;
  final id = m[1]!;
  if (!isLinkId(id)) return null;
  // Uri keeps the fragment as written; a key never needs decoding (base64url is all safe characters)
  final hash = url.indexOf('#');
  return (id: id, fragment: hash < 0 ? '' : url.substring(hash + 1));
}

bool _sameSite(Uri a, Uri b) => a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// What is wrong with a locked copy's frame before any cryptography: too short or long, or its
/// first byte zero (damaged), or above this version (newer). Null when it is worth opening.
LinkError? frameError(List<int> locked) {
  if (locked.length < linkMinBytes || locked.length > linkMaxBytes || locked[0] == 0) return LinkError.damaged;
  if (locked[0] > linkVersion) return LinkError.newer;
  return null;
}
