# The blessing file, and a blessing in a link

How a finished blessing travels from one iPhone to another. The file is built and offered in the app;
the link is written and measured only, with no screen (2026-11-16).

## The `.blessing` file

- Offered first on the share sheet, "As a blessing file" ("Opens in Upon Thy Head on another iPhone."),
  above text and PDF. Named as the PDF is: `Comfort before surgery, March 3, 2026.blessing`.
- Type: `dev.summitstudio.uponThyHead.blessing`, exported and owned by the app (Info.plist
  `UTExportedTypeDeclarations`, `CFBundleDocumentTypes` with rank Owner). It conforms to `public.data`
  and `public.content` only, never to `public.json` or `public.text`, so Notes, Mail previews and text
  editors do not offer to open it as text. MIME type `application/vnd.uponthyhead.blessing`.
- Code: `app/lib/share/blessing_file.dart` (format, writing, strict reading), `app/lib/share/receive.dart`
  (what an arrival comes to, and its sheet), `BlessingInbox` in `app/ios/Runner/Share.swift` (how iOS
  hands it over).

### What is inside

UTF-8 JSON, indented, one object, keys in this order:

| key | type | what |
|---|---|---|
| `format` | string | always `"upon-thy-head/blessing"` |
| `version` | integer | `1`. A reader refuses a higher one as "made with a newer version" |
| `id` | string | the blessing's id, `[A-Za-z0-9_-]`, at most 64 |
| `title` | string | at most 300; missing or blank reads as the untitled blessing |
| `given` | string | the minute it was given, UTC: `"2026-03-03T16:40Z"` |
| `offset` | integer | the giver's clock offset in minutes (−420), within ±18 h |
| `from` | string | who gave it, at most 200, may be empty |
| `for` | string | who it was for, at most 200, may be empty |
| `tags` | string[] | at most 40, each at most 60 |
| `language` | string | the words' language (`"en"`, `"es"`, `"pt-BR"`), at most 20 |
| `words` | string | the spoken words, exactly as spoken, at most 200,000 characters |
| `changes` | object[] | the polish changes, in order: `at` (character offset in `words`), `was`, `now`, `kind` (`filler`, `repeat`, `restart`, `grammar`, `punctuation`), `source`, `kept` (bool). At most 5,000 |

Not carried: the audio, the place it was given, the first transcript, created/updated times, the
draft flag, the owner flag, or anything about the sender's phone.

The receiver reads the polished words (the spoken words with the kept changes applied), sees "Polished
from N changes", and can open the changes screen and restore any change to the spoken word.

### Reading strictly

- At most 512 KiB; the native side reads at most one byte over and refuses without parsing.
- Must be UTF-8, JSON, an object, `format` exact, `version` an integer ≥ 1.
- Every field typed and bounded as above; unknown fields are ignored (so a later version can add some).
- No control characters anywhere except line breaks and tabs in `words`, `was`, `now`; no broken
  surrogate pairs.
- `given` a real calendar minute between 1900 and two days from now.
- Each change must stand on the words (`words.substring(at, at + was.length) == was`), in order, not
  overlapping, of a known kind. One bad change refuses the file: a half-right file is not shown.
- Nothing in it is fetched, run, or turned into a link.

### Receiving

- iOS hands the app the file through the scene (`scene(_:willConnectTo:options:)` at a cold launch,
  `scene(_:openURLContexts:)` while running). A tap in Files, AirDrop, a Messages or Mail attachment
  and `simctl openurl file://…` all come in this way.
- The native side reads it (with the security scope and a file coordinator), deletes the copy iOS put
  in `Documents/Inbox`, and keeps the bytes in memory until Flutter asks. The original in Files is
  left where it is. No copy stays in the app's folders.
- Nothing is shown while locked: the sheet is built only after Face ID or the passcode.
- Nothing interrupts a recording: the file waits until the recording is over and the person is back
  on the sky, a reading page or Settings.
- New: the title, "A blessing from Dad" (or "A blessing"), the long date, "Keep it with your
  blessings?", Keep / Not now. Keep saves it finished and as the person's own, at the receiver's
  place, and opens its reading page.
- The same id and the same content: no question; it opens, saying "You already have this blessing."
- The same id, different content: "You already have this blessing, and this copy is different."
  Replace mine / Keep mine.
- A newer version: "This blessing was made with a newer version of Upon Thy Head. Update the app to
  open it." OK. Anything else that fails: "This file could not be read." OK.

## In a link (written and measured; not in the app)

`app/lib/share/link.dart`:

    https://uponthyhead.app/b#1<base64url( key ‖ ChaCha20-Poly1305( deflate( compact JSON ) ) ‖ tag )>

- `1` is the link format's version; a higher digit reads as "newer".
- The record is the file's, as compact JSON, compressed with raw DEFLATE at level 9 (what Apple's
  `COMPRESSION_ZLIB` reads), sealed with ChaCha20-Poly1305 (RFC 8439; what CryptoKit's `ChaChaPoly`
  opens) under a random 256-bit key used once (so the nonce is zero), and written base64url without
  padding. Letters, digits, `-` and `_` only.
- Decoding is as strict as the file, and also refuses a fragment over 256 K characters and anything
  that would unpack past 512 KiB.
- `app/tool/link_check.swift` opens a link with CryptoKit and Apple's Compression only. All 14 links
  measured below opened with it.

### What the encryption does and does not do

The part after `#` is never sent to a server by a browser. So a web server, its logs, a proxy, or a
filter that records addresses sees the address and nothing of the blessing. That is all it does.
Anything that holds the whole link holds the key with it: the Messages thread, a mail archive, a chat
app's link preview service, a screenshot of a QR code, browser history, iCloud backups. Each of those
can read the blessing. It is not end-to-end encryption between two people. The tag does make a link
that was cut short or changed fail cleanly, instead of showing half a blessing.

### How long the link is

Measured by `app/test/link_lengths_test.dart` (characters, the whole link). The prose rows are the
King James and Reina-Valera 1909 Gospel of John, as a stand-in for real blessings.

| text | words | file bytes | link characters |
|---|---:|---:|---:|
| sample "Comfort before surgery", 5 changes | 106 | 1,542 | 858 |
| the same without its changes | 106 | | 685 |
| blessing-style, English | 199 | | 1,002 |
| blessing-style, Spanish | 185 | | 1,063 |
| prose, English | 100 | | 671 |
| | 300 | | 1,214 |
| | 600 | | 2,017 |
| | 1,500 | | 4,321 |
| | 2,500 | 13,496 | 6,650 |
| prose, Spanish | 100 | | 713 |
| | 300 | | 1,314 |
| | 600 | | 2,237 |
| | 1,500 | | 4,854 |
| | 2,500 | 13,988 | 7,297 |

Roughly 400 characters of fixed cost (the address, the key, the tag, the record's other fields),
then about 2.5 characters a word in English and 2.8 in Spanish.

### What a link meets

- **App Clip Code** (the round code): cannot carry it. Apple allows a fragment, from a small
  character set that base64url fits, but the URL is compressed into the code and must be short; Apple
  advises short URLs and no UUIDs, and developers report about 35 usable characters.
  [Apple: Encoding a URL in an App Clip Code](https://developer.apple.com/documentation/appclip/encoding-a-url-in-an-app-clip-code);
  [Apple Developer Forums 669391, "Compressed URL too large"](https://developer.apple.com/forums/thread/669391).
- **App Clip card in Messages**: needs a live website at the domain with the Smart App Banner meta
  tag and an og:image, and a default App Clip experience. The recipient must be on iOS 14 or later and
  have the sender in Contacts; over SMS they first tap to load the preview. The Smart App Banner's
  `app-argument` does not reach an App Clip.
  [Apple: Supporting invocations from your website and the Messages app](https://developer.apple.com/documentation/appclip/supporting-invocations-from-your-website-and-the-messages-app).
  Whether the App Clip's `webpageURL` keeps the `#` part is not documented: it needs a device test.
- **QR code**: version 40 holds 2,953 bytes at error correction L and 2,331 at M. That is about 1,000
  words at L and 800 at M, and a version 40 code is too dense to scan from a phone screen at a normal
  distance. [Thonky QR capacity table](https://www.thonky.com/qr-code-tutorial/character-capacities);
  [Keyence QR code capacity](https://www.keyence.com/ss/products/auto_id/codereader/basic_2d/qr.jsp).
- **Mail**: RFC 5322 limits a line to 998 characters (78 recommended). Mail apps wrap or encode long
  lines, and a long unbroken link is often cut or broken by a client or a filter. Past about 150 words
  with changes, the link is over 998 characters.
  [RFC 5322 §2.1.1](https://www.rfc-editor.org/rfc/rfc5322#section-2.1.1).
- **Messages and WhatsApp**: carry the length (WhatsApp's message limit is reported as 65,536
  characters; no limit found for iMessage). Over SMS, the 1,600-character figure often quoted could
  not be confirmed.
- **Safari**: no documented limit for an address; reports range from about 8,000 to about 80,000
  characters. The server never sees the fragment, so server limits do not apply.

### Verdict

A link can carry a short blessing, and nothing about it is unsafe in itself. It is not the way to send
blessings in general:

- It never fits an App Clip Code, and a QR code only up to about 800–1,000 words, at a density that
  scans badly.
- Mail is the place a blessing is most likely to be sent, and there a link breaks past about 150 words.
- The App Clip card that would make it open nicely needs a live website, and a Contacts relationship.
- A link anyone can read once they have it, so privacy is the same as the file's, not better.

The honest alternatives:

1. **The blessing file** (built). Works in Messages, Mail, AirDrop and Files at any length, opens
   straight into the app, and carries the changes. It needs the app on the other phone.
2. **A link to a server that holds only ciphertext**, the key staying in the `#`: short links (about
   70 characters) that fit any App Clip invocation, QR code and mail. The server holds unreadable
   bytes and can expire them. It means running a server.
3. **A link only for short blessings**, with the file offered past a length.
4. **The PDF or text** for someone without the app (built).
