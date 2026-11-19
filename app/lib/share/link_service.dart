import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'link_format.dart';
import 'proof.dart';

/// The link service (website/PROTOCOL.md §4): create, read and stop a locked copy. It only ever
/// sees the locked bytes, a link's id, and (to stop one) its stop token in the Authorization header.
/// The key is never handed to this file. Nothing here is logged: no address, no body, no token.
///
/// Every failure is one of a few plain outcomes the screens have words for; a raw error never
/// reaches the person. Anything the service would not say (no service there yet, a page that is not
/// ours, a cut connection) counts as "cannot be reached", which the screens treat as no internet:
/// so until the site is live the release app falls back to sending the file.
abstract class LinkService {
  Future<CreateResult> create(Uint8List locked);
  Future<ReadResult> read(String id);
  Future<StopResult> stop(String id, String stopToken);
}

/// Why the service did not do what was asked.
enum LinkTrouble {
  /// No connection at all, or nothing there that answers as the service does.
  offline,

  /// Too many from this network just now (429).
  slowDown,

  /// Everyone together has used the day's links (503 full).
  full,

  /// Over 64 KiB (413).
  tooBig,

  /// The service is there but cannot do it now (503 unavailable), or answered something the app
  /// should never have caused (415, 400, 401, 403, 404): offered the file.
  unavailable,
}

sealed class CreateResult {
  const CreateResult();
}

class Created extends CreateResult {
  const Created({required this.id, required this.expires, required this.stop});
  final String id;
  final DateTime expires;
  final String stop;
}

class CreateFailed extends CreateResult {
  const CreateFailed(this.trouble);
  final LinkTrouble trouble;
}

sealed class ReadResult {
  const ReadResult();
}

class ReadCopy extends ReadResult {
  const ReadCopy(this.locked);
  final Uint8List locked;
}

/// 410: stopped, expired, or never there (the service does not tell them apart).
class ReadGone extends ReadResult {
  const ReadGone();
}

class ReadFailed extends ReadResult {
  const ReadFailed(this.trouble);
  final LinkTrouble trouble;
}

enum StopResult {
  /// 204, or 410 (already gone): stopped.
  stopped,

  /// No connection, or no service: the link is left as it is.
  offline,

  /// The service is there but did not stop it (429, 503, or a token it does not know).
  failed,
}

final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

DateTime? _utc(Object? v) {
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(v)) return null;
  return DateTime.tryParse(v)?.toUtc();
}

final _pass = RegExp(r'^p1\.[A-Za-z0-9_-]{22}\.(\d{1,12})\.[A-Za-z0-9_-]{43}$');

/// The service over HTTPS (or plain HTTP to this Mac in tests), with dart:io's client: no cookies,
/// no device information, nothing but the request itself.
///
/// Making a link carries a pass, proof that the request comes from this app (PROTOCOL.md §4,
/// "Proof of the app"), when one can be had: the pass kept from before while it lasts, otherwise a
/// new one from [prover], given at most [proofTimeout]. With none, the link is asked for without
/// one, which the service accepts until it is told to require proof. [prover] is the native one for
/// the real (https) service and none for any other address unless given (tests).
class HttpLinkService implements LinkService {
  HttpLinkService({
    String base = linkService,
    this.timeout = const Duration(seconds: 20),
    AppProver? prover,
    this.proofTimeout = const Duration(seconds: 6),
  })  : _base = Uri.parse(base),
        prover = prover ?? (Uri.parse(base).scheme == 'https' ? const NativeAppProver() : null);

  final Uri _base;
  final Duration timeout;
  final AppProver? prover;
  final Duration proofTimeout;

  String? _keptPass;
  bool _passRead = false;

  /// When [pass] stops being good, from the expiry written in it; null if it is not a pass.
  static DateTime? passExpiry(String pass) {
    final m = _pass.firstMatch(pass);
    if (m == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!) * 1000, isUtc: true);
  }

  /// The kept pass while it has more than an hour left, otherwise a new one (or null).
  Future<String?> _usablePass() async {
    final p = prover;
    if (p == null) return null;
    if (!_passRead) {
      _keptPass = await p.keptPass();
      _passRead = true;
    }
    final kept = _keptPass, ends = kept == null ? null : passExpiry(kept);
    if (kept != null && ends != null && ends.isAfter(DateTime.now().toUtc().add(const Duration(hours: 1)))) return kept;
    return _newPass();
  }

  /// Prove the app afresh: a challenge, the native proof, and the service's pass. Null when any step
  /// cannot be done within [proofTimeout].
  Future<String?> _newPass() async {
    final p = prover;
    if (p == null) return null;
    _keptPass = null;
    String? fresh;
    try {
      fresh = await _prove(p).timeout(proofTimeout, onTimeout: () => null);
    } catch (_) {
      fresh = null;
    }
    _keptPass = fresh;
    _passRead = true;
    await p.keepPass(fresh);
    return fresh;
  }

  Future<String?> _prove(AppProver p) async {
    final c = await _send('POST', _at('/api/proof/challenge'));
    if (c == null || c.status != 200 || !_isJson(c.headers)) return null;
    final j = jsonDecode(utf8.decode(c.body));
    if (j is! Map || j['challenge'] is! String) return null;
    final challenge = j['challenge'] as String;
    final android = j['android'];
    final project = android is Map && android['project'] is String ? android['project'] as String : null;
    final fields = await p.prove(challenge, androidProject: project);
    if (fields == null) return null;
    final body = Uint8List.fromList(utf8.encode(jsonEncode({...fields, 'challenge': challenge})));
    final r = await _send('POST', _at('/api/proof'), body: body, headers: {'Content-Type': 'application/json'});
    if (r == null || r.status != 200 || !_isJson(r.headers)) return null;
    final a = jsonDecode(utf8.decode(r.body));
    final pass = a is Map ? a['pass'] : null;
    return pass is String && _pass.hasMatch(pass) ? pass : null;
  }

  Uri _at(String path) => _base.replace(path: path);

  /// Plain HTTP only in a debug build (the website on this Mac in tests). A release or profile build
  /// given an http address never sends to it: it answers as with no internet. Dart's own HTTP client
  /// does not follow Android's network security config, so this is the rule for the app's requests;
  /// the manifest refuses plain HTTP for the rest of the app in release builds.
  bool get _allowed => _base.scheme == 'https' || (kDebugMode && _base.scheme == 'http');

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'UponThyHead'
    ..autoUncompress = true;

  Future<({int status, Uint8List body, HttpHeaders headers})?> _send(String method, Uri url,
      {Uint8List? body, Map<String, String> headers = const {}}) async {
    if (!_allowed) return null;
    final client = _client();
    try {
      return await () async {
        final req = await client.openUrl(method, url);
        req.followRedirects = false;
        headers.forEach(req.headers.set);
        if (body != null) {
          req.contentLength = body.length;
          req.add(body);
        }
        final res = await req.close();
        final out = BytesBuilder(copy: false);
        await for (final chunk in res) {
          out.add(chunk);
          if (out.length > linkMaxBytes + 4096) break; // nothing from the service is this large
        }
        return (status: res.statusCode, body: out.takeBytes(), headers: res.headers);
      }()
          .timeout(timeout);
    } on SocketException {
      return null;
    } on HandshakeException {
      return null;
    } on HttpException {
      return null;
    } on TimeoutException {
      return null;
    } on OSError {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The error code in a JSON error body, or '' when the body is not the service's.
  static String _error(Uint8List body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      return j is Map && j['error'] is String ? j['error'] as String : '';
    } catch (_) {
      return '';
    }
  }

  static bool _isJson(HttpHeaders h) => h.contentType?.mimeType == 'application/json';

  /// A refusal the service would give, or offline when the answer is not the service's at all.
  static LinkTrouble _trouble(int status, Uint8List body, HttpHeaders h) {
    final e = _isJson(h) ? _error(body) : '';
    if (e.isEmpty) return LinkTrouble.offline;
    return switch ((status, e)) {
      (429, _) => LinkTrouble.slowDown,
      (503, 'full') => LinkTrouble.full,
      (413, _) => LinkTrouble.tooBig,
      _ => LinkTrouble.unavailable,
    };
  }

  @override
  Future<CreateResult> create(Uint8List locked) async {
    if (locked.length > linkMaxBytes) return const CreateFailed(LinkTrouble.tooBig);
    Future<({int status, Uint8List body, HttpHeaders headers})?> post(String? pass) => _send('POST', _at('/api/b'),
        body: locked, headers: {'Content-Type': 'application/octet-stream', 'Blessing-Pass': ?pass});
    final pass = await _usablePass();
    var r = await post(pass);
    // a pass the service no longer takes (its secret changed, or it ran out): prove once more, and
    // ask again with the new pass, or with none if none could be had
    if (r != null && pass != null && r.status == 401 && _isJson(r.headers) && _error(r.body) == 'pass') {
      r = await post(await _newPass());
    }
    if (r == null) return const CreateFailed(LinkTrouble.offline);
    if (r.status == 201 && _isJson(r.headers)) {
      try {
        final j = jsonDecode(utf8.decode(r.body));
        if (j is Map) {
          final id = j['id'], stop = j['stop'], expires = _utc(j['expires']);
          if (id is String && isLinkId(id) && stop is String && _token.hasMatch(stop) && expires != null) {
            return Created(id: id, expires: expires, stop: stop);
          }
        }
      } catch (_) {}
      return const CreateFailed(LinkTrouble.offline);
    }
    return CreateFailed(_trouble(r.status, r.body, r.headers));
  }

  @override
  Future<ReadResult> read(String id) async {
    if (!isLinkId(id)) return const ReadGone();
    final r = await _send('GET', _at('/api/b/$id'));
    if (r == null) return const ReadFailed(LinkTrouble.offline);
    if (r.status == 200 && r.headers.contentType?.mimeType == 'application/octet-stream') return ReadCopy(r.body);
    if (r.status == 410 && _isJson(r.headers)) return const ReadGone();
    return ReadFailed(_trouble(r.status, r.body, r.headers));
  }

  @override
  Future<StopResult> stop(String id, String stopToken) async {
    final r = await _send('DELETE', _at('/api/b/$id'), headers: {'Authorization': 'Bearer $stopToken'});
    if (r == null) return StopResult.offline;
    if (r.status == 204) return StopResult.stopped;
    if (r.status == 410 && _isJson(r.headers)) return StopResult.stopped;
    return _trouble(r.status, r.body, r.headers) == LinkTrouble.offline ? StopResult.offline : StopResult.failed;
  }
}
