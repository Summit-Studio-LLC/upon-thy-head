// Proof that a request to make a link comes from the real app: Apple's App Attest on iPhone and
// iPad, Google's Play Integrity on Android. PROTOCOL.md §4 "Proof of the app" is the contract.
//
// The service keeps nothing about a device. A challenge is stateless (signed with the server's
// secret, five minutes' life). A verified proof is answered with a pass: a token the server signs,
// with an expiry of seven days and a pass id, stored nowhere. Nothing here logs anything.

import { X509Certificate, createHash, createHmac, createSign, randomBytes, timingSafeEqual } from "node:crypto";

export const PROOF = {
  challengeLifeMs: 5 * 60 * 1000,
  passLifeMs: 7 * 24 * 60 * 60 * 1000,
  /** Apple: <team id>.<bundle id>. */
  appleAppId: "7R77MUH4FF.dev.summitstudio.uponThyHead",
  androidPackage: "dev.summitstudio.uponthyhead",
  /** The largest proof request read: an attestation is about 5 KB, sent as base64 in JSON. */
  maxBody: 32768,
};

/**
 * Apple App Attestation Root CA, from https://www.apple.com/certificateauthority/ (fetched
 * 2026-11-18). SHA-256 fingerprint
 * 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32.
 * Valid to 2045.
 */
export const APPLE_APP_ATTEST_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----
`;

const b64url = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const sha256 = (...parts: (Uint8Array | string)[]) => {
  const h = createHash("sha256");
  for (const p of parts) h.update(p);
  return new Uint8Array(h.digest());
};
const same = (a: Uint8Array | string, b: Uint8Array | string) => {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};
const mac = (secret: Uint8Array, text: string) => createHmac("sha256", secret).update(text).digest();

// ---------------------------------------------------------------------------------------------
// Challenges and passes: signed, short-lived, kept nowhere.

const CHALLENGE = /^c1\.(\d{1,12})\.([A-Za-z0-9_-]{22})\.([A-Za-z0-9_-]{22})$/;
const PASS = /^p1\.([A-Za-z0-9_-]{22})\.(\d{1,12})\.([A-Za-z0-9_-]{43})$/;

/** A new challenge: "c1.<expiry, seconds>.<16 random bytes>.<mac>". */
export function makeChallenge(secret: Uint8Array, now: number, random: (n: number) => Uint8Array = (n) => new Uint8Array(randomBytes(n))) {
  const expires = Math.floor((now + PROOF.challengeLifeMs) / 1000);
  const nonce = b64url(random(16));
  const tag = b64url(mac(secret, `challenge|${expires}|${nonce}`).subarray(0, 16));
  return { challenge: `c1.${expires}.${nonce}.${tag}`, expires: expires * 1000 };
}

/** Whether a challenge is one this server made and is still within its life. */
export function challengeIsGood(secret: Uint8Array, challenge: string, now: number): boolean {
  const m = CHALLENGE.exec(challenge);
  if (!m) return false;
  const wanted = b64url(mac(secret, `challenge|${m[1]}|${m[2]}`).subarray(0, 16));
  return same(wanted, m[3]) && Number(m[1]) * 1000 > now;
}

/** A pass for `id`: "p1.<id>.<expiry, seconds>.<mac>". */
export function makePass(secret: Uint8Array, id: string, now: number) {
  const expires = Math.floor((now + PROOF.passLifeMs) / 1000);
  return { pass: `p1.${id}.${expires}.${b64url(mac(secret, `pass|${id}|${expires}`))}`, expires: expires * 1000 };
}

/** The pass id, if `pass` is one this server signed and it has not expired; otherwise null. */
export function passId(secret: Uint8Array, pass: string, now: number): string | null {
  const m = PASS.exec(pass);
  if (!m) return null;
  if (!same(b64url(mac(secret, `pass|${m[1]}|${m[2]}`)), m[3])) return null;
  return Number(m[2]) * 1000 > now ? m[1] : null;
}

/**
 * The pass id for a verified proof. It is derived from what was proven (the one-time App Attest
 * key, or the challenge a Play Integrity token was bound to) so that sending the same proof again
 * gives the same pass, not a fresh allowance. Outside this server it looks random, and it is kept
 * nowhere.
 */
export const passIdFor = (secret: Uint8Array, what: string) => b64url(mac(secret, `pass-id|${what}`).subarray(0, 16));

// ---------------------------------------------------------------------------------------------
// CBOR, as much as an App Attest attestation object needs.

type Cbor = number | bigint | boolean | null | string | Uint8Array | Cbor[] | Map<Cbor, Cbor>;

export function cbor(bytes: Uint8Array): Cbor {
  let at = 0;
  const need = (n: number) => {
    if (at + n > bytes.length) throw new Error("cbor: cut short");
  };
  const length = (info: number): number => {
    if (info < 24) return info;
    const n = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
    if (!n) throw new Error("cbor: length");
    need(n);
    let v = 0;
    for (let i = 0; i < n; i++) v = v * 256 + bytes[at++];
    if (!Number.isSafeInteger(v)) throw new Error("cbor: too long");
    return v;
  };
  const item = (depth: number): Cbor => {
    if (depth > 16) throw new Error("cbor: too deep");
    need(1);
    const head = bytes[at++], major = head >> 5, info = head & 31;
    switch (major) {
      case 0: return length(info);
      case 1: return -1 - length(info);
      case 2: case 3: {
        const n = length(info);
        need(n);
        const out = bytes.subarray(at, at + n);
        at += n;
        return major === 2 ? out : Buffer.from(out).toString("utf8");
      }
      case 4: {
        const n = length(info);
        const out: Cbor[] = [];
        for (let i = 0; i < n; i++) out.push(item(depth + 1));
        return out;
      }
      case 5: {
        const n = length(info);
        const out = new Map<Cbor, Cbor>();
        for (let i = 0; i < n; i++) out.set(item(depth + 1), item(depth + 1));
        return out;
      }
      case 6: length(info); return item(depth + 1);
      default:
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        throw new Error("cbor: simple");
    }
  };
  const out = item(0);
  if (at !== bytes.length) throw new Error("cbor: trailing bytes");
  return out;
}

// ---------------------------------------------------------------------------------------------
// DER, as much as finding one extension in a certificate needs.

type Der = { tag: number; body: Uint8Array; end: number };
function der(bytes: Uint8Array, at: number): Der {
  if (at + 2 > bytes.length) throw new Error("der: cut short");
  const tag = bytes[at];
  let len = bytes[at + 1], start = at + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4 || start + n > bytes.length) throw new Error("der: length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + bytes[start + i];
    start += n;
  }
  if (start + len > bytes.length) throw new Error("der: cut short");
  return { tag, body: bytes.subarray(start, start + len), end: start + len };
}
const children = (body: Uint8Array) => {
  const out: Der[] = [];
  for (let at = 0; at < body.length; ) {
    const d = der(body, at);
    out.push(d);
    at = d.end;
  }
  return out;
};

/** The value (inside its OCTET STRING) of the extension `oid` (DER bytes), or null. */
export function extensionOf(certificate: Uint8Array, oid: Uint8Array): Uint8Array | null {
  const tbs = children(der(certificate, 0).body)[0];
  const extensions = children(tbs.body).find((c) => c.tag === 0xa3);
  if (!extensions) return null;
  for (const ext of children(children(extensions.body)[0]?.body ?? new Uint8Array())) {
    const parts = children(ext.body);
    if (parts[0]?.tag === 0x06 && same(parts[0].body, oid)) return parts[parts.length - 1].body;
  }
  return null;
}

/** 1.2.840.113635.100.8.2: Apple's App Attest nonce. */
const NONCE_OID = Uint8Array.from([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]);
const AAGUID_PRODUCTION = Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)]);
const AAGUID_DEVELOPMENT = Buffer.from("appattestdevelop");

export type Verdict = { ok: true; what: string } | { ok: false; reason: string };

/**
 * Apple's checks for an App Attest attestation (developer.apple.com, "Validating apps that connect
 * to your server"), in order. `keyId` is the base64 key id the app's DCAppAttestService gave it.
 */
export function verifyAppAttest(input: {
  attestation: Uint8Array;
  keyId: string;
  challenge: string;
  now: number;
  root: string;
  allowDevelopment: boolean;
  appId?: string;
}): Verdict {
  const fail = (reason: string): Verdict => ({ ok: false, reason });
  let object: Cbor;
  try {
    object = cbor(input.attestation);
  } catch {
    return fail("format");
  }
  if (!(object instanceof Map) || object.get("fmt") !== "apple-appattest") return fail("format");
  const statement = object.get("attStmt"), authData = object.get("authData");
  if (!(statement instanceof Map) || !(authData instanceof Uint8Array)) return fail("format");
  const x5c = statement.get("x5c");
  if (!Array.isArray(x5c) || x5c.length < 2 || !x5c.every((c) => c instanceof Uint8Array)) return fail("format");

  // 1. The certificates lead to Apple's App Attest root, and each is in date.
  let leaf: X509Certificate, middle: X509Certificate, root: X509Certificate;
  try {
    leaf = new X509Certificate(x5c[0] as Uint8Array);
    middle = new X509Certificate(x5c[1] as Uint8Array);
    root = new X509Certificate(input.root);
  } catch {
    return fail("chain");
  }
  const inDate = (c: X509Certificate) => Date.parse(c.validFrom) <= input.now && input.now <= Date.parse(c.validTo);
  if (
    !middle.ca ||
    !leaf.checkIssued(middle) || !leaf.verify(middle.publicKey) ||
    !middle.checkIssued(root) || !middle.verify(root.publicKey) ||
    ![leaf, middle, root].every(inDate)
  ) return fail("chain");

  // 2–4. The nonce in the leaf certificate is SHA-256(authData ‖ SHA-256(challenge)).
  const nonce = sha256(authData, sha256(input.challenge));
  let inCert: Uint8Array | null = null;
  try {
    const ext = extensionOf(new Uint8Array(leaf.raw), NONCE_OID);
    // SEQUENCE { [1] { OCTET STRING nonce } }
    if (ext) inCert = der(der(der(ext, 0).body, 0).body, 0).body;
  } catch {}
  if (!inCert || !same(inCert, nonce)) return fail("nonce");

  // 5. The key id is the SHA-256 of the leaf's public key (the uncompressed point).
  const jwk = leaf.publicKey.export({ format: "jwk" }) as { crv?: string; x?: string; y?: string };
  if (jwk.crv !== "P-256" || !jwk.x || !jwk.y) return fail("key");
  const keyId = sha256(Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]));
  const given = Buffer.from(input.keyId, "base64");
  if (!same(keyId, given)) return fail("key");

  // authData: rpIdHash(32) flags(1) counter(4) aaguid(16) credentialIdLength(2) credentialId …
  if (authData.length < 55) return fail("format");
  // 6. The app id hash is this app's.
  if (!same(authData.subarray(0, 32), sha256(input.appId ?? PROOF.appleAppId))) return fail("app");
  // 7. The counter is zero.
  if (Buffer.from(authData.subarray(33, 37)).readUInt32BE(0) !== 0) return fail("counter");
  // 8. Production, or development only when allowed.
  const aaguid = Buffer.from(authData.subarray(37, 53));
  const environment = aaguid.equals(AAGUID_PRODUCTION) ? "production" : aaguid.equals(AAGUID_DEVELOPMENT) ? "development" : null;
  if (!environment || (environment === "development" && !input.allowDevelopment)) return fail("environment");
  // 9. The credential id is the key id.
  const idLength = Buffer.from(authData.subarray(53, 55)).readUInt16BE(0);
  if (authData.length < 55 + idLength || !same(authData.subarray(55, 55 + idLength), keyId)) return fail("key");

  return { ok: true, what: `ios|${b64url(keyId)}` };
}

// ---------------------------------------------------------------------------------------------
// Play Integrity (standard request). The token is decoded by Google, with a service account.

/** What the app puts in its standard request's requestHash: SHA-256 of the challenge, base64url. */
export const requestHashOf = (challenge: string) => b64url(sha256(challenge));

type IntegrityPayload = {
  requestDetails?: { requestPackageName?: string; requestHash?: string; timestampMillis?: string | number };
  appIntegrity?: { appRecognitionVerdict?: string; packageName?: string };
  deviceIntegrity?: { deviceRecognitionVerdict?: string[] };
};

/** The checks on a decoded Play Integrity verdict. */
export function verifyIntegrityVerdict(payload: unknown, challenge: string, now: number): Verdict {
  const p = (payload ?? {}) as IntegrityPayload;
  const fail = (reason: string): Verdict => ({ ok: false, reason });
  const r = p.requestDetails, a = p.appIntegrity, d = p.deviceIntegrity;
  if (!r || r.requestPackageName !== PROOF.androidPackage || r.requestHash !== requestHashOf(challenge)) return fail("request");
  const at = Number(r.timestampMillis);
  if (!Number.isFinite(at) || at < now - PROOF.challengeLifeMs - 60000 || at > now + 60000) return fail("request");
  if (!a || a.packageName !== PROOF.androidPackage || a.appRecognitionVerdict !== "PLAY_RECOGNIZED") return fail("app");
  if (!Array.isArray(d?.deviceRecognitionVerdict) || !d.deviceRecognitionVerdict.includes("MEETS_DEVICE_INTEGRITY")) return fail("device");
  return { ok: true, what: `android|${challenge}` };
}

/** A Google service account key, as the JSON file Google Cloud gives. */
type ServiceAccount = { client_email: string; private_key: string; token_uri?: string };

/**
 * Asks Google to decode a Play Integrity token: an OAuth token from the service account (a signed
 * JWT, cached in memory until shortly before it expires), then decodeIntegrityToken.
 */
export class PlayDecoder {
  private account: ServiceAccount;
  private fetcher: typeof fetch;
  private access: { token: string; until: number } | null = null;

  constructor(account: ServiceAccount, fetcher: typeof fetch = fetch) {
    this.account = account;
    this.fetcher = fetcher;
  }

  /** From PLAY_INTEGRITY_SERVICE_ACCOUNT (the JSON key, as is or base64), or null. */
  static from(json: string | undefined, fetcher: typeof fetch = fetch): PlayDecoder | null {
    if (!json) return null;
    for (const text of [json, Buffer.from(json, "base64").toString("utf8")]) {
      try {
        const a = JSON.parse(text) as ServiceAccount;
        if (typeof a.client_email === "string" && typeof a.private_key === "string") return new PlayDecoder(a, fetcher);
      } catch {}
    }
    return null;
  }

  private async accessToken(now: number): Promise<string> {
    if (this.access && this.access.until > now) return this.access.token;
    const iat = Math.floor(now / 1000);
    const aud = this.account.token_uri ?? "https://oauth2.googleapis.com/token";
    const part = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
    const unsigned = `${part({ alg: "RS256", typ: "JWT" })}.${part({ iss: this.account.client_email, scope: "https://www.googleapis.com/auth/playintegrity", aud, iat, exp: iat + 3600 })}`;
    const signature = createSign("RSA-SHA256").update(unsigned).sign(this.account.private_key).toString("base64url");
    const response = await this.fetcher(aud, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${signature}` }).toString(),
      signal: AbortSignal.timeout(8000),
    });
    const j = (await response.json().catch(() => ({}))) as { access_token?: string; expires_in?: number };
    if (!response.ok || !j.access_token) throw new Error("google refused the service account");
    this.access = { token: j.access_token, until: now + Math.max(60, (j.expires_in ?? 3600) - 300) * 1000 };
    return j.access_token;
  }

  /** The decoded verdict (tokenPayloadExternal), or null if Google would not decode it. */
  async decode(token: string, now: number): Promise<unknown | null> {
    const access = await this.accessToken(now);
    const response = await this.fetcher(`https://playintegrity.googleapis.com/v1/${PROOF.androidPackage}:decodeIntegrityToken`, {
      method: "POST",
      headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
      body: JSON.stringify({ integrity_token: token }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return null;
    const j = (await response.json().catch(() => null)) as { tokenPayloadExternal?: unknown } | null;
    return j?.tokenPayloadExternal ?? null;
  }
}
