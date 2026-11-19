// The shared-blessing format, as PROTOCOL.md describes it. This one file is what the receiver's
// page runs in the browser and what the tests check against protocol-vectors.json. It uses only
// what a browser has built in (Web Crypto); there is no cryptography library.

export const VERSION = 1; // the leading byte of a locked copy
export const NONCE_BYTES = 12;
export const TAG_BYTES = 16;
export const KEY_BYTES = 32;
export const MIN_BYTES = 1 + NONCE_BYTES + TAG_BYTES + 2; // the smallest record is "{}"
// the largest locked copy the service keeps: 512 KiB since 2026-11-18 (64 KiB before), so a family
// member's whole ring can travel as one link (PROTOCOL.md §5)
export const MAX_BYTES = 524288;
export const ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;
const KEY_PATTERN = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/; // 43 characters, the spare bits zero

export const RECORD_FORMAT = "upon-thy-head/blessing";
// 2 (2026-11-18): a blessing entered from a written copy ("entered": true), and one known only to its
// month or year ("precision"). The app still writes 1 for a blessing recorded on a known day.
export const RECORD_VERSION = 2;
// 3 (2026-11-18): a family member's whole ring handed to their own phone, {"kind":"ring","keptBy",
// "blessings":[record, …]}. A single blessing is never written as 3, so every reader from before
// says "made with a newer version" of a ring.
export const RING_VERSION = 3;
export const RING_MAX = 2000;
export const LIMITS = { id: 64, title: 300, name: 200, tags: 40, tag: 60, language: 20, words: 200000, changes: 5000, changeText: 2000, source: 40 };
// docs/blessing-file.md lists "restart"; app/lib/polish/change.dart has "reworded". Both are read.
const KINDS = ["filler", "repeat", "reworded", "restart", "grammar", "punctuation"];

/** Why a link could not be opened. `code` is one of: key, damaged, locked, newer, record. */
export class LinkError extends Error {
  constructor(code, why = code) {
    super(why);
    this.code = code;
  }
}

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/** base64url without padding (RFC 4648 §5). */
export function toBase64Url(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    out += ALPHABET[n >> 18] + ALPHABET[(n >> 12) & 63];
    if (i + 1 < bytes.length) out += ALPHABET[(n >> 6) & 63];
    if (i + 2 < bytes.length) out += ALPHABET[n & 63];
  }
  return out;
}

export function fromBase64Url(text) {
  if (!/^[A-Za-z0-9_-]*$/.test(text) || text.length % 4 === 1) throw new LinkError("damaged", "not base64url");
  const out = new Uint8Array(Math.floor((text.length * 3) / 4));
  let bits = 0, held = 0, at = 0;
  for (const ch of text) {
    held = (held << 6) | ALPHABET.indexOf(ch);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[at++] = (held >> bits) & 255;
    }
  }
  return out;
}

/** The key from the part of the address after "#" (with or without the "#"). */
export function keyFromFragment(fragment) {
  const text = fragment.startsWith("#") ? fragment.slice(1) : fragment;
  if (!KEY_PATTERN.test(text)) throw new LinkError("key", text ? "the key is not 43 base64url characters" : "no key");
  return fromBase64Url(text);
}

/** The whole link for an id and a key. */
export const linkFor = (origin, id, key) => `${origin}/b/${id}#${toBase64Url(key)}`;

async function aesKey(key, use) {
  if (key.length !== KEY_BYTES) throw new LinkError("key", "the key is not 32 bytes");
  return crypto.subtle.importKey("raw", key, "AES-GCM", false, [use]);
}

/** Lock `plain` (the record's compact JSON bytes) under `key` with `nonce`. The phone's part. */
export async function seal(plain, key, nonce) {
  if (nonce.length !== NONCE_BYTES) throw new LinkError("damaged", "the nonce is not 12 bytes");
  const sealed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: Uint8Array.of(VERSION), tagLength: TAG_BYTES * 8 },
    await aesKey(key, "encrypt"),
    plain,
  );
  const out = new Uint8Array(1 + NONCE_BYTES + sealed.byteLength);
  out[0] = VERSION;
  out.set(nonce, 1);
  out.set(new Uint8Array(sealed), 1 + NONCE_BYTES);
  return out;
}

/** Open a locked copy with its key. Gives the record's JSON bytes, or throws a LinkError. */
export async function open(locked, key) {
  if (locked.length < MIN_BYTES || locked.length > MAX_BYTES) throw new LinkError("damaged", "the locked copy is the wrong size");
  if (locked[0] === 0) throw new LinkError("damaged", "no version");
  if (locked[0] > VERSION) throw new LinkError("newer", `locked copy version ${locked[0]}`);
  const cryptoKey = await aesKey(key, "decrypt");
  try {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: locked.subarray(1, 1 + NONCE_BYTES), additionalData: locked.subarray(0, 1), tagLength: TAG_BYTES * 8 },
      cryptoKey,
      locked.subarray(1 + NONCE_BYTES),
    );
    return new Uint8Array(plain);
  } catch {
    throw new LinkError("locked", "the key does not open this copy, or the copy was changed");
  }
}

// ---------- the record ----------

const bad = (why) => new LinkError("record", why);

function clean(s, lines = false) {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 || (c >= 0x7f && c < 0xa0)) {
      if (lines && (c === 0x0a || c === 0x0d || c === 0x09)) continue;
      return false;
    }
    if (c >= 0xd800 && c <= 0xdbff) {
      const d = s.charCodeAt(i + 1);
      if (!(d >= 0xdc00 && d <= 0xdfff)) return false;
      i++;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

function text(j, key, max, { required = false, lines = false } = {}) {
  const v = j[key];
  if (v === undefined || v === null) {
    if (required) throw bad(`no ${key}`);
    return "";
  }
  if (typeof v !== "string") throw bad(key);
  if (v.length > max) throw bad(`${key} too long`);
  if (!clean(v, lines)) throw bad(`${key} has characters that cannot be shown`);
  return v;
}

function given(v, now, precision = "day", offset = 0) {
  const m = typeof v === "string" && /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})Z$/.exec(v);
  if (!m) throw bad("given");
  const [y, mo, d, h, mi] = m.slice(1).map(Number);
  const t = new Date(Date.UTC(y, mo - 1, d, h, mi));
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== mo - 1 || t.getUTCDate() !== d || t.getUTCHours() !== h || t.getUTCMinutes() !== mi) throw bad("given");
  if (y < 1900) throw bad("given out of range");
  const limit = new Date(now.getTime() + 2 * 86400000);
  if (precision === "day") {
    if (t.getTime() > limit.getTime()) throw bad("given out of range");
  } else {
    const local = new Date(t.getTime() + offset * 60000);
    if (
      local.getUTCFullYear() > limit.getUTCFullYear() ||
      (precision === "month" && local.getUTCFullYear() === limit.getUTCFullYear() && local.getUTCMonth() > limit.getUTCMonth())
    ) {
      throw bad("given out of range");
    }
  }
  return t;
}

/**
 * Read the record from its JSON bytes, as strictly as the app reads a .blessing file
 * (app/lib/share/blessing_file.dart). Gives the fields the page shows, or throws a LinkError
 * ("newer" for a later record version, "record" for anything else).
 */
export function readRecord(bytes, now = new Date()) {
  return recordOf(parse(bytes), now);
}

function parse(bytes) {
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    throw bad("not UTF-8 JSON");
  }
}

/**
 * Read what a link opened to: one blessing, `{kind: "blessing", record}`, or a family member's whole
 * ring, `{kind: "ring", keptBy, records}` with the records oldest first and each id once. Throws a
 * LinkError as readRecord does.
 */
export function readShared(bytes, now = new Date()) {
  const j = parse(bytes);
  if (typeof j === "object" && j !== null && !Array.isArray(j) && j.format === RECORD_FORMAT && j.kind === "ring") {
    if (!Number.isInteger(j.version) || j.version < RING_VERSION) throw bad("ring version");
    if (j.version > RING_VERSION) throw new LinkError("newer", `ring version ${j.version}`);
    const keptBy = j.keptBy == null ? "" : j.keptBy;
    if (typeof keptBy !== "string" || keptBy.length > LIMITS.name || !clean(keptBy)) throw bad("keptBy");
    if (!Array.isArray(j.blessings) || j.blessings.length === 0 || j.blessings.length > RING_MAX) throw bad("blessings");
    const seen = new Set();
    const records = [];
    for (const b of j.blessings) {
      const r = recordOf(b, now);
      if (!seen.has(r.id)) {
        seen.add(r.id);
        records.push(r);
      }
    }
    records.sort((a, b) => a.given - b.given);
    return { kind: "ring", keptBy: keptBy.trim(), records };
  }
  return { kind: "blessing", record: recordOf(j, now) };
}

function recordOf(j, now) {
  if (typeof j !== "object" || j === null || Array.isArray(j)) throw bad("not an object");
  if (j.format !== RECORD_FORMAT) throw bad("not a blessing");
  if (!Number.isInteger(j.version) || j.version < 1) throw bad("no version");
  if (j.version > RECORD_VERSION) throw new LinkError("newer", `record version ${j.version}`);

  const id = text(j, "id", LIMITS.id, { required: true });
  if (!/^[A-Za-z0-9_-]+$/.test(id)) throw bad("id");
  const title = text(j, "title", LIMITS.title).trim();
  const precision = j.precision == null ? "day" : j.precision;
  if (!["day", "month", "year"].includes(precision)) throw bad("precision");
  if (!Number.isInteger(j.offset) || j.offset < -1080 || j.offset > 1080) throw bad("offset");
  const when = given(j.given, now, precision, j.offset);
  const from = text(j, "from", LIMITS.name).trim();
  const recipient = text(j, "for", LIMITS.name).trim();
  const language = text(j, "language", LIMITS.language);
  if (language && !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$/.test(language)) throw bad("language");
  const words = text(j, "words", LIMITS.words, { required: true, lines: true });
  if (j.tags != null) {
    if (!Array.isArray(j.tags) || j.tags.length > LIMITS.tags) throw bad("tags");
    for (const t of j.tags) if (typeof t !== "string" || t.length > LIMITS.tag || !clean(t)) throw bad("tag");
  }
  if (j.place != null) {
    const p = j.place;
    if (typeof p !== "object" || Array.isArray(p) || !Number.isFinite(p.lat) || !Number.isFinite(p.lon) || Math.abs(p.lat) > 90 || Math.abs(p.lon) > 180) throw bad("place");
  }
  const changes = [];
  if (j.changes != null) {
    if (!Array.isArray(j.changes) || j.changes.length > LIMITS.changes) throw bad("changes");
    let end = 0;
    for (const c of j.changes) {
      if (typeof c !== "object" || c === null || Array.isArray(c)) throw bad("change");
      const was = text(c, "was", LIMITS.changeText, { required: true, lines: true });
      const now0 = text(c, "now", LIMITS.changeText, { lines: true });
      const kind = text(c, "kind", 20, { required: true });
      text(c, "source", LIMITS.source);
      if (!Number.isInteger(c.at) || c.at < 0 || !was || !KINDS.includes(kind) || typeof c.kept !== "boolean") throw bad("change");
      if (c.at + was.length > words.length || words.substring(c.at, c.at + was.length) !== was) throw bad("change not in the words");
      if (c.at < end) throw bad("changes overlap");
      end = c.at + was.length;
      changes.push({ at: c.at, was, now: now0, kept: c.kept });
    }
  }
  if (j.entered != null && typeof j.entered !== "boolean") throw bad("entered");
  const entered = j.entered === true;
  return { id, title, given: when, offset: j.offset, from, for: recipient, language, words, changes, precision, entered };
}

/** The words as the app's reading page shows them: the spoken words with the kept changes applied. */
export function polished(record) {
  let out = "", at = 0;
  for (const c of record.changes) {
    if (!c.kept) continue;
    out += record.words.substring(at, c.at) + c.now;
    at = c.at + c.was.length;
  }
  return out + record.words.substring(at);
}

export const keptChanges = (record) => record.changes.filter((c) => c.kept).length;

/**
 * Paragraphs, split where the app's reading page splits them: at a blank line; and, for words entered
 * from a written copy (kept exactly as typed or pasted), at every line break.
 */
export const paragraphs = (words, entered = false) => words.split(entered ? /\n/ : /\n\s*\n/).map((s) => s.trim()).filter(Boolean);
