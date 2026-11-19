import 'dart:typed_data';

import '../data/blessing.dart';
import '../data/sent_link.dart';
import '../data/store.dart';
import 'blessing_file.dart';
import 'link_crypto.dart';
import 'link_format.dart';
import 'link_service.dart';
import 'receive.dart';
import 'ring_file.dart';

/// Sending a blessing by link and opening one (website/PROTOCOL.md): the record locked on the
/// phone with a new key, only the locked copy sent, the key only ever in the link's fragment.
///
/// What is kept here: in the store, each link's id, its blessing, a copy of the title, when it was
/// sent, when it stops and whether it was stopped; in the Keychain, its stop token. Never the key.
class Links {
  Links({required this.store, required this.crypto, required this.secrets, required this.service, DateTime Function()? now})
      : _now = now ?? (() => DateTime.now().toUtc());

  final BlessingStore store;
  final LinkCrypto crypto;
  final SecretStore secrets;
  final LinkService service;
  final DateTime Function() _now;

  /// How long a stopped or expired link stays in "Your links" before it is cleared.
  static const keepEnded = Duration(days: 30);

  static String _secret(String id) => 'link.$id';

  /// Make a link for [b]: lock it, send the locked copy, keep the stop token.
  Future<MakeResult> make(Blessing b) async {
    final plain = BlessingRecord.of(b).toCompactBytes();
    // too big for a link whatever the service says: the file, with no request at all
    if (plain.length + 1 + linkNonceBytes + linkTagBytes > blessingLinkMaxBytes) return const NotMade(LinkTrouble.tooBig);
    final (:locked, :key) = await lockForLink(crypto, plain);
    final r = await service.create(locked);
    switch (r) {
      case CreateFailed(:final trouble):
        return NotMade(trouble);
      case Created(:final id, :final expires, :final stop):
        await secrets.put(_secret(id), stop);
        final link = SentLink(id: id, blessingId: b.id, title: b.title, sent: _now(), expires: expires);
        await store.addLink(link);
        return Made(url: linkOf(id, key), link: link);
    }
  }

  /// Make a link for a family member's whole ring ([ring], kept by [keptBy]): one locked copy of
  /// every blessing on it (ring_file.dart). "Your links" lists it as [title] ("Emma's ring"), under
  /// [ringLinkId] of the person, so it is stopped as any link is.
  Future<MakeResult> makeRing(String personId, List<Blessing> ring, {required String keptBy, required String title}) async {
    final bundle = RingBundle.of(ring, keptBy: keptBy);
    if (bundle.records.isEmpty) return const NotMade(LinkTrouble.unavailable);
    final plain = bundle.toCompactBytes();
    if (plain.length + 1 + linkNonceBytes + linkTagBytes > linkMaxBytes) return const NotMade(LinkTrouble.tooBig);
    final (:locked, :key) = await lockForLink(crypto, plain);
    final r = await service.create(locked);
    switch (r) {
      case CreateFailed(:final trouble):
        return NotMade(trouble);
      case Created(:final id, :final expires, :final stop):
        await secrets.put(_secret(id), stop);
        final link = SentLink(id: id, blessingId: ringLinkId(personId), title: title, sent: _now(), expires: expires);
        await store.addLink(link);
        return Made(url: linkOf(id, key), link: link);
    }
  }

  /// "Your links": every link, newest first, after clearing those that ended a while ago. A link that
  /// has ended no longer needs its stop token.
  Future<List<SentLink>> list() async {
    final now = _now();
    final out = <SentLink>[];
    for (final l in await store.links()) {
      final ended = l.endedAt(now);
      if (ended != null) {
        await secrets.delete(_secret(l.id));
        if (now.difference(ended) > keepEnded) {
          await store.removeLink(l.id);
          continue;
        }
      }
      out.add(l);
    }
    return out;
  }

  /// The links of blessing [id] that still work.
  Future<List<SentLink>> liveOf(String id) async {
    final now = _now();
    return [for (final l in await store.links()) if (l.blessingId == id && l.stateAt(now) == LinkState.live) l];
  }

  /// Stop [link] at the service, then here. Offline or failed leaves it as it is.
  Future<StopResult> stop(SentLink link) async {
    final token = await secrets.get(_secret(link.id));
    // no token (a Keychain that was cleared): nothing can stop it; it runs out on its date
    if (token == null) return StopResult.failed;
    final r = await service.stop(link.id, token);
    if (r == StopResult.stopped) {
      await store.setLinkStopped(link.id, _now());
      await secrets.delete(_secret(link.id));
    }
    return r;
  }

  /// Stop every live link of blessing [id] (before it is deleted). Stops as many as it can and
  /// answers with the worst outcome.
  Future<StopResult> stopAllOf(String id) async {
    var worst = StopResult.stopped;
    for (final l in await liveOf(id)) {
      final r = await stop(l);
      if (r == StopResult.offline) worst = StopResult.offline;
      if (r == StopResult.failed && worst == StopResult.stopped) worst = StopResult.failed;
    }
    return worst;
  }

  /// Open a link that was handed to the app ([parts] from [linkPartsOf]): fetch the locked copy,
  /// open it with the key, read the record, and set it beside the store as a file is.
  Future<Arrival> open(LinkParts parts) async {
    final key = keyOfFragment(parts.fragment);
    if (key == null) return const ArrivalNoKey();
    final r = await service.read(parts.id);
    switch (r) {
      case ReadGone():
        return const ArrivalStopped();
      case ReadFailed(:final trouble):
        return trouble == LinkTrouble.offline ? const ArrivalOnItsWay() : const ArrivalNotNow();
      case ReadCopy(:final locked):
        return openLocked(crypto, locked, key, store.get);
    }
  }
}

/// Open [locked] with [key] in the contract's order and set it beside the store ([find]).
Future<Arrival> openLocked(LinkCrypto crypto, Uint8List locked, Uint8List key, Future<Blessing?> Function(String) find) async {
  final frame = frameError(locked);
  if (frame == LinkError.newer) return const ArrivalNewer();
  if (frame != null) return ArrivalUnreadable('link: ${frame.name}');
  final plain = await crypto.open(locked, key);
  if (plain == null) return const ArrivalUnreadable('link: locked');
  final read = readShared(plain);
  if (read is SharedBad) return const ArrivalUnreadable('link: record');
  return arrivalOfShared(read, find);
}

/// The id "Your links" keeps a ring's link under, in place of a blessing's: never a blessing id
/// (those are hex), so nothing confuses the two.
String ringLinkId(String personId) => 'ring:$personId';

/// The contract's steps 2–5 (the key has been checked): the error, or the record.
Future<(LinkError?, BlessingRecord?)> openError(LinkCrypto crypto, Uint8List locked, Uint8List key) async {
  final frame = frameError(locked);
  if (frame != null) return (frame, null);
  final plain = await crypto.open(locked, key);
  if (plain == null) return (LinkError.locked, null);
  return switch (readBlessingFile(plain)) {
    BlessingReadOk(:final record) => (null, record),
    BlessingReadNewer() => (LinkError.newer, null),
    BlessingReadBad() => (LinkError.record, null),
  };
}

sealed class MakeResult {
  const MakeResult();
}

class Made extends MakeResult {
  const Made({required this.url, required this.link});

  /// The whole link, with the key. Shown on the sheet and handed to the share sheet; never kept.
  final String url;
  final SentLink link;
}

class NotMade extends MakeResult {
  const NotMade(this.trouble);
  final LinkTrouble trouble;
}
