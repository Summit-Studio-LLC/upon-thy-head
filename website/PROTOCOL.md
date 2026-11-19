# Sharing a blessing by link: the contract

This is everything the app needs to make, stop and open a shared link, on iPhone and on Android.
The website's side is built to it (`lib/links/`, `app/api/b/`, `public/shared/format.js`).
`protocol-vectors.json` has fixed keys, records, locked bytes and links to check an implementation
against.

**In one sentence:** the phone locks the blessing with a key it makes itself, sends only the locked
copy to the server, and puts the key in the part of the link after `#`, which browsers never send
to a server; so the server holds bytes it cannot read.

Format version: **1**. Written 2026-11-16.

## 1. The link

    https://uponthyhead.app/b/<id>#<key>

| part | what | form |
|---|---|---|
| `<id>` | names the locked copy on the server; chosen by the server | 16 random bytes as base64url without padding: exactly 22 characters of `A–Z a–z 0–9 - _` |
| `<key>` | opens the locked copy; chosen by the phone; never sent to the server | 32 random bytes as base64url without padding: exactly 43 characters |

- The whole link is 92 characters.
- base64url is RFC 4648 §5, no `=` padding. The key must be written canonically (a standard encoder
  does this): its last character is one of `AEIMQUYcgkosw048`. Anything else after `#` is refused.
- There is nothing else in the fragment: no version, no parameters. The version is in the locked
  copy's first byte.
- The app builds the link itself from the `id` the server returns and the key it holds. The server
  never sees or returns the whole link.

## 2. The record

What is locked is the same record a `.blessing` file carries (`docs/blessing-file.md`,
`app/lib/share/blessing_file.dart`): the JSON object with `format`, `version`, `id`, `title`,
`given`, `offset`, `from`, `for`, `tags`, `language`, `words`, `changes`, and optionally `place`,
`precision` and `entered` (record version 2, 2026-11-18: a blessing entered from a written copy, or
one whose date is known only to the month or the year; the page shows "August 1998" or "1998" and
"Entered from a written copy, not recorded.").

- Written **compact** (no spaces or line breaks between tokens), UTF-8, no byte-order mark:
  `BlessingRecord.toCompactBytes()`.
- **Not compressed.** A 2,500-word blessing is about 14–17 KB as JSON, and nothing here is short of
  space. Leaving compression out means the page needs only Web Crypto (every browser since about
  2015) and not the newer decompression stream (Safari 16.4, March 2023), there is one step fewer
  to get identical on three platforms, and there is no decompression bomb to guard against.
- A reader checks the record as strictly as the app checks a file: see "Reading strictly" in
  `docs/blessing-file.md`. A record `version` above 2 is "made with a newer version" (the
  site reads 1 and 2; the link's own format byte stays `0x01`).
- **A whole ring** (2026-11-18: a parent handing a family member's ring to their own phone) is one
  record of `version` **3** with `"kind": "ring"`:
  `{"format":"upon-thy-head/blessing","version":3,"kind":"ring","keptBy":"Dad","blessings":[…]}`.
  `keptBy` is the name the parent typed (≤ 200 characters, no control characters; may be empty);
  `blessings` is a list of up to 2,000 single records (version 1 or 2, each read as strictly as
  alone), oldest first; one id twice is kept once. An app or page made before rings reads version 3
  as "made with a newer version". Like every record, it is only ever inside the locked copy: the
  service and the link carry no name, count or date.
- The words shown are the spoken words with each change whose `kept` is true applied in order
  (`applyChanges` in `app/lib/polish/change.dart`).

Change `kind` may be `reworded` (as `app/lib/polish/change.dart` writes) or `restart`, alongside
`filler`, `repeat`, `grammar`, `punctuation`; a reader accepts all six.

## 3. The locked copy

    byte 0        the format version: 0x01
    bytes 1–12    the nonce: 12 random bytes
    bytes 13–…    the ciphertext, the same length as the record's bytes
    last 16 bytes the authentication tag

- Cipher: **AES-256-GCM**. Key: 32 random bytes, made new for every link and used once. Nonce: 12
  random bytes, made new for every link. Tag: 16 bytes (128 bits).
- Additional authenticated data: **the one byte `0x01`** (the same byte as byte 0). So the version
  byte cannot be changed without the copy failing to open.
- Plaintext: the record's compact JSON bytes (§2).
- Size: at least 31 bytes (1 + 12 + 16 + the two bytes of `{}`); **at most 524,288 bytes** (512 KiB, §5). The app keeps a single blessing's copy to 65,536 bytes, as before rings, so every single-blessing link still opens in an older app.
- Randomness must come from the system's secure generator (`SecRandomCopyBytes` / `SystemRandom`,
  `java.security.SecureRandom`).

How each platform makes it:

| | lock | open |
|---|---|---|
| iOS (CryptoKit) | `AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: Data([1]))`, then `Data([1]) + nonce + box.ciphertext + box.tag` | `AES.GCM.open(AES.GCM.SealedBox(nonce:ciphertext:tag:), using:, authenticating: Data([1]))` |
| Android (javax.crypto) | `Cipher.getInstance("AES/GCM/NoPadding")`, `init(ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))`, `updateAAD(byteArrayOf(1))`, `doFinal(plain)` gives ciphertext‖tag; prepend `0x01` and the nonce | the same with `DECRYPT_MODE` on bytes 13 to the end |
| Browser (Web Crypto) | `crypto.subtle.encrypt({name: "AES-GCM", iv: nonce, additionalData: Uint8Array.of(1), tagLength: 128}, key, plain)` | `crypto.subtle.decrypt` with the same parameters |

AES-256-GCM was the expected choice and I found no reason for another: all three platforms have it
built in, and a new random key for every link removes the usual worry about a repeated nonce. The
earlier experiment's hand-written ChaCha20-Poly1305 (`app/lib/share/chacha.dart`) is not used.

Opening, in this order (the error names are the ones in `protocol-vectors.json`):

1. The fragment is not exactly a 43-character canonical base64url key: `key`.
2. Fewer than 31 or more than 524,288 bytes, or byte 0 is `0x00`: `damaged`.
3. Byte 0 is greater than `0x01`: `newer`.
4. AES-GCM does not authenticate (wrong key, any byte changed, cut short): `locked`.
5. The plaintext is not a valid blessing or ring record: `record`, or `newer` if its `version` is
   higher than this reader knows (above 2 for a single blessing, above 3 for a `"kind": "ring"`
   record).

## 4. The service

Base: `https://uponthyhead.app`. Every answer carries `Cache-Control: no-store`,
`Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, `X-Robots-Tag: noindex`,
`Cross-Origin-Resource-Policy: same-origin`, no cookies and no CORS headers. An error's body is
JSON, `{"error":"<code>"}`. Send no cookies, no account, and no information about the device.

### Create: `POST /api/b`

Request: header `Content-Type: application/octet-stream`; body: the locked copy (§3), raw bytes.
Optionally header `Blessing-Pass: <pass>`, proof that the request comes from the app (see "Proof of
the app" below).

`201 Created`, `Content-Type: application/json`:

    {"id":"CRAXHiUsMzpBSE9WXWRrcg","expires":"2026-12-16T18:03:22Z","stop":"<43 characters>"}

- `id`: 22 characters (§1).
- `expires`: when the link stops, UTC, to the second, always ending in `Z`: 30 days (2,592,000
  seconds) after the server received it. Show this date to the sender and on "Your links".
- `stop`: the stop token: 32 random bytes as 43 base64url characters. It is returned **only here**.
  The phone keeps it (in the Keychain / Keystore, with the id and the expiry); the server keeps
  only its SHA-256.

| status | error | when | what the app does |
|---|---|---|---|
| 415 | `type` | `Content-Type` is not `application/octet-stream` | a bug in the app |
| 413 | `too_big` | over 524,288 bytes | offer the blessing file instead |
| 400 | `too_small` | under 31 bytes | a bug in the app |
| 400 | `version` | byte 0 is not `0x01` | a bug, or the site is older than the app: offer the file |
| 429 | `slow_down` | too many from this network; `Retry-After: <seconds>` | say to try again shortly; offer the file |
| 503 | `full` | the day's budget for everyone is spent; `Retry-After` runs to midnight UTC | offer the file |
| 503 | `unavailable` | storage is not reachable | offer the file |
| 401 | `pass` | the pass is not one the server signed, or it has expired | prove again once and ask again (with no pass if none could be had) |
| 403 | `proof` | no pass, while the service requires proof (`LINKS_REQUIRE_PROOF=1`) | "could not make a link"; offer the file |

No connection at all is the drawn "No internet, so a link cannot be made now" with "Send as a file".

### Read: `GET /api/b/<id>`

`200 OK`, `Content-Type: application/octet-stream`, header `Blessing-Expires: 2026-12-16T18:03:22Z`;
body: the locked copy, byte for byte as it was sent.

| status | error | when |
|---|---|---|
| 410 | `gone` | no copy under this id: it expired, was stopped, or never existed (the three are not told apart) |
| 404 | `not_found` | the id is not 22 base64url characters |
| 429 | `slow_down` | too many reads from this network; `Retry-After` |
| 503 | `unavailable` | storage is not reachable |

The app, opening a link it was handed (`…/b/<id>#<key>`): GET the locked copy, open it (§3), read
the record, and show its "Keep it with your blessings?" sheet. On 410 show "This link has stopped
working."

### Stop: `DELETE /api/b/<id>`

Request: header `Authorization: Bearer <stop token>`.

| status | error | when |
|---|---|---|
| 204 | | the copy is erased, now. No body |
| 410 | `gone` | there was no copy (already stopped or expired). Treat as stopped |
| 403 | `wrong_token` | the token is not this link's |
| 401 | `no_token` | no token, or not 43 base64url characters |
| 404 | `not_found` | the id is not 22 base64url characters |
| 429 | `slow_down` | `Retry-After` |
| 503 | `unavailable` | try again later; the link is still live |

### Proof of the app (added 2026-11-18)

Making a link can carry proof that the request comes from this app: Apple's App Attest on iPhone and
iPad, Google's Play Integrity (standard request) on Android. The server keeps nothing about a device
for it. It hands out a stateless challenge, checks the proof once, and answers with a **pass**: a
token it signs, good for seven days, kept nowhere by the server. The phone keeps the pass (Keychain
on iOS, the app's private preferences on Android) and sends it with each link. When it expires, or
the server refuses it, the phone proves itself again with a fresh key. Opening and stopping a link
never need a pass. Until `LINKS_REQUIRE_PROOF=1` is set, a link without a pass is still made.

**`POST /api/proof/challenge`** (no body) → `200`:

    {"challenge":"c1.<expiry>.<random>.<mac>","expires":"2026-11-18T18:08:22Z","android":{"project":"123456789012"}}

- The challenge is good for five minutes. It is signed with the server's secret
  (`LINKS_PASS_SECRET`); nothing is stored.
- `android` is there only when Play Integrity is set up: the Cloud project number the app asks
  Google with. Without it the Android app sends no proof.
- `503 unavailable` when no secret is set: the app carries on with no pass.

**`POST /api/proof`**, `Content-Type: application/json`, at most 32 KiB:

    {"platform":"ios","challenge":"…","keyId":"<base64, as DCAppAttestService gave it>","attestation":"<base64>"}
    {"platform":"android","challenge":"…","token":"<the Play Integrity token>"}

→ `200` `{"pass":"p1.<pass id>.<expiry>.<mac>","expires":"2026-11-25T18:03:22Z"}`.

- iOS: `clientDataHash` is SHA-256 of the challenge's UTF-8 bytes. The server checks the certificate
  chain to Apple's App Attest root, the nonce (SHA-256 of authenticator data ‖ clientDataHash) in
  the leaf certificate, that the key id is SHA-256 of the leaf's public key and equals the
  credential id, the app id hash for `7R77MUH4FF.dev.summitstudio.uponThyHead`, a zero counter, and
  the production environment (development only with `APP_ATTEST_ALLOW_DEVELOPMENT=1`). The key is
  used for this one proof and never again.
- Android: `requestHash` is SHA-256 of the challenge, base64url without padding. Google decodes the
  token (`decodeIntegrityToken`, with the service account); the server requires the package
  `dev.summitstudio.uponthyhead`, the same requestHash, a timestamp within the challenge's life,
  `PLAY_RECOGNIZED`, and `MEETS_DEVICE_INTEGRITY`.
- The pass id is derived from what was proven (the one-time key, or the challenge a token was bound
  to), so the same proof sent twice gives the same pass id, not a second allowance.

| status | error | when |
|---|---|---|
| 400 | `proof` | the proof did not verify (counted, by platform and reason) |
| 400 | `format` | the body is not one of the two shapes |
| 415 | `type` | not `application/json` |
| 413 | `too_big` | over 32 KiB |
| 429 | `slow_down` | `Retry-After` |
| 503 | `not_set_up` | an Android proof while Play Integrity is not set up |
| 503 | `unavailable` | no secret set, storage not reachable, or Google not reachable |

A valid pass is limited like a network: 10 links in 10 minutes, 40 a day and 3 MiB a day per pass
id, on top of the network's own limits. Challenges: 20 per network in 10 minutes; proofs: 10; both
under a shared ceiling of 300 a minute.

**`GET /api/status`**, with `Authorization: Bearer <STATUS_SECRET>` (or `<CRON_SECRET>` when
`STATUS_SECRET` is unset), for the owner: today's and
yesterday's links and bytes, the allowance and the share of it used, and the day's counts:
`links:proven`, `links:unproven`, `links:refused_no_proof`, `pass:refused`, `proof:ios:ok`,
`proof:ios:failed`, `proof:ios:failed:<reason>` (`challenge`, `format`, `chain`, `nonce`, `key`,
`app`, `counter`, `environment`), the same for `android` (`request`, `app`, `device`, `decode`),
`proof:android:not_set_up`, and `warned:<links|bytes>:<50|90>`. Counts say how many, never who.

**Warnings:** when the day's links or bytes pass 50% and again 90% of the allowance, the owner gets
one email per threshold per day through Resend (`RESEND_API_KEY`, `ALERT_TO`, `ALERT_FROM`), with
counts only. It is sent after the link's answer has gone, and a failure to send changes nothing.

### What the server keeps, and for how long

For each link, exactly three things: the locked bytes, the expiry, and the SHA-256 of the stop
token. Nothing else: no address, no device, no account, no time of reading, no count of reads.
The copy is erased when it is stopped, when it is asked for after its expiry, and by the clean-up
(`/api/sweep`) that runs once a day (Upstash Redis also erases a key at the moment of expiry; Neon
Postgres does not erase rows by itself, so an expired copy nobody asks for waits there—never
served—until that daily clean-up).

Per UTC day it also keeps two totals for everyone together (how many links, how many bytes), to
enforce the day's budget, and the named counts listed under `GET /api/status`. They carry no
identity and are dropped after three days. Nothing is kept for a proof or a pass.

To count requests per network, the address a request came from is mixed with a secret made new each
time the server starts, and only that mix is held, in memory, for the length of a rate-limit window
(at most a day). It is never written to storage or to a log by this code. Vercel, as the host,
keeps its own request logs (address, path, time) for a period set by the plan; those contain a
link's id but never its key.

## 5. Limits, and why

- **524,288 bytes (512 KiB) for a locked copy** (65,536 until 2026-11-18). A 2,500-word blessing
  with its changes is about 17 KB; an ordinary blessing about 2–4 KB, so a whole ring of 100–150
  blessings fits. The app still keeps one blessing to 65,536 bytes (so older apps open it); only a
  ring uses more. An app made before rings refuses a copy over 65,536 bytes as `damaged`.
  It is small enough that the service is useless as file hosting: no photo, video or program of
  any size fits. A record over the cap is sent as a file instead.
- **30 days**, then erased.
- **One network:** 10 links in 10 minutes and 40 in a day; 120 reads a minute; 30 stops a minute.
- **One client, per UTC day:** 3 MiB of copies made (about six of the largest rings).
- **Everyone together, per UTC day:** 1,000 links and 12 MiB (6 MiB until 2026-11-18). Thirty such days fit inside the free
  size of the store, so the worst case costs nothing and fills nothing.

### An open "store my bytes" endpoint will be abused. What is done now

- The cap, the 30 days, the per-network limits and the daily budget above bound what anyone can
  take: at most about 360 MiB at any time, all of it gone in 30 days.
- A copy is only ever served back as `application/octet-stream` with `nosniff`, a
  `Content-Security-Policy: default-src 'none'; sandbox`, and `Cross-Origin-Resource-Policy:
  same-origin`, with no CORS. A browser will not run it, show it, or let another site embed or
  fetch it. It can only be downloaded as opaque bytes by something that already knows the id.
- The first byte must be `0x01`. This is no proof of anything; it only refuses the laziest misuse.
- The per-network counter lives in memory on each server instance, so on Vercel, where there can be
  several instances, it is a floor and not a wall. **Before launch, add a rate-limit rule in
  Vercel Firewall for `POST /api/b`** (it counts across all instances, at the edge). The daily
  budget is in the store and does hold across instances.

### Proof that a request comes from the real app (built 2026-11-18: see "Proof of the app" in §4)

What was written before it was built, kept for the reasoning. As built, the server keeps no
per-device key: it checks one proof and hands back a signed pass instead.


Apple's App Attest and Google's Play Integrity let the app attach, to each create request, a
statement signed by Apple or Google that it comes from an unmodified copy of this app on a real
device. The server would check it and refuse everything else. That closes the endpoint to scripts
and to anyone without the app, which the limits above only slow down, and it lets the limits be
counted per app installation instead of per network (fairer on shared Wi-Fi). It adds a call to
Apple or Google when a link is made, a per-device key the server must remember (a small new thing
kept), and it identifies an installation to this server, though not a person. It does nothing for
reading, which must stay open to any browser. It is worth adding when the app is in the stores;
the create request would gain one header and nothing else in this contract would change.

## 6. Opening the link in the app

- iOS: `https://uponthyhead.app/.well-known/apple-app-site-association` claims `/b/*` for
  `7R77MUH4FF.dev.summitstudio.uponThyHead`. The app needs the Associated Domains entitlement
  `applinks:uponthyhead.app`, and reads the link from `NSUserActivity.webpageURL`
  (`scene(_:continue:)`, and `connectionOptions.userActivities` at a cold launch).
  **To check on a device: that `webpageURL` still has the `#<key>`.** It is expected to, but it has
  not been tested here, and the whole feature rests on it.
- Android: `/.well-known/assetlinks.json` is served, empty, until the package name and signing
  certificate exist; `app/.well-known/assetlinks.json/route.ts` says exactly what goes in.
- Someone without the app gets the page at `/b/<id>`, which does §3 in the browser.

## 7. What this does and does not protect

Anyone who has the whole link can read the blessing until it stops: it can be forwarded, and it
sits in the message thread, in backups of it, and in browser history. This is not end-to-end
encryption between two people.

Someone who took over the server, or the storage, **could**:

- see how many links exist, each one's id, size (so roughly how long the blessing is) and expiry
  (so when it was made), and, through the host's request logs, the addresses that made and opened
  them;
- erase copies, refuse to serve them, or keep them past their 30 days;
- **change the page's script so that it sends the key somewhere when a link is opened in a browser
  from then on.** This is the real limit of unlocking in a web page: the page that does the
  unlocking is served by the same server. From that moment they could read every blessing opened in
  a browser.

They **could not**:

- read any blessing from what is stored, at any time, including everything stored before they got
  in: the keys are not there and never were;
- read a blessing opened only in the app, which does the unlocking with its own code;
- change a blessing or pass off another in its place: any changed copy fails to open;
- stop a link they do not hold the stop token for by using the service as designed (though with
  control of storage they could simply erase it).

## 8. Test vectors

`protocol-vectors.json`, made by `scripts/make-vectors.mjs` with Node's own AES-256-GCM (not the
page's code):

- `vectors`: for each, `key`, `nonce`, the `record`, its `plaintext` (as text and base64), the
  `locked` bytes (base64, length, SHA-256), an `id`, the whole `link`, and what must be `shown`
  (the title, the polished words, how many changes are kept). **Locking `plaintext` under `key`
  and `nonce` must give exactly `locked`. Opening `locked` with `key` must give `plaintext`.**
- `refusals`: locked copies with the error each must give (wrong key, a changed byte in the tag,
  the words and the nonce, a later or zero version byte, cut short).
- `fragments`: things after `#` that are not a key.
- `records`: copies that open but whose record must be refused.

The first vector's third change has `kept: false`: the spoken words ("and, uh, He wants") must
stand there, while the first two changes apply.
