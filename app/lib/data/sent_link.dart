/// A link made on this phone (share/links.dart), as "Your links" lists it. Its key is never kept
/// anywhere (it lives only in the link that was sent); its stop token is in the Keychain.
class SentLink {
  const SentLink({required this.id, required this.blessingId, required this.title, required this.sent, required this.expires, this.stopped});

  final String id;

  /// The blessing it was made from; that blessing may since have been deleted.
  final String blessingId;

  /// The blessing's title when the link was made.
  final String title;
  final DateTime sent, expires;

  /// When it was stopped; null while it has not been.
  final DateTime? stopped;

  LinkState stateAt(DateTime now) => stopped != null
      ? LinkState.stopped
      : !now.isBefore(expires)
          ? LinkState.expired
          : LinkState.live;

  /// When it stopped working, by being stopped or by running out; null while live.
  DateTime? endedAt(DateTime now) => switch (stateAt(now)) {
        LinkState.live => null,
        LinkState.stopped => stopped,
        LinkState.expired => expires,
      };
}

enum LinkState { live, stopped, expired }
