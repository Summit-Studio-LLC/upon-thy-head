// Writes protocol-vectors.json: fixed keys, nonces and records with the locked bytes and links
// they must give. It uses Node's own AES-GCM (node:crypto), not the page's code, so the tests
// check one implementation against another. Usage: node scripts/make-vectors.mjs
import { createCipheriv, createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const b64 = (b) => Buffer.from(b).toString("base64");
const b64url = (b) => Buffer.from(b).toString("base64url");
const bytes = (from, n) => Uint8Array.from({ length: n }, (_, i) => (from + i * 7) & 255);

function seal(plain, key, nonce) {
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.of(1));
  return Buffer.concat([Buffer.of(1), nonce, cipher.update(plain), cipher.final(), cipher.getAuthTag()]);
}

function change(words, was, now, kind, kept, from = 0) {
  const at = words.indexOf(was, from);
  if (at < 0) throw new Error(`"${was}" is not in the words`);
  return { at, was, now, kind, source: "rules", kept };
}

const comfortWords =
  "Emma, I lay my hands upon your head, um, to give you a blessing of of comfort.\n\n" +
  "Your Heavenly Father knows you. He knows the worry you have carried these weeks, and, uh, He wants you to know that you have not carried it alone.";
const comfort = {
  format: "upon-thy-head/blessing",
  version: 1,
  id: "b_2026-03-03_comfort",
  title: "Comfort before surgery",
  given: "2026-03-03T16:40Z",
  offset: -420,
  from: "Dad",
  for: "Emma",
  tags: ["comfort"],
  language: "en",
  words: comfortWords,
  changes: [
    change(comfortWords, " um,", "", "filler", true),
    change(comfortWords, "of of", "of", "repeat", true),
    change(comfortWords, ", uh,", "", "filler", false), // restored: the spoken words stand here
  ],
  place: { lat: 40.8, lon: -111.9 },
};

const spanish = {
  format: "upon-thy-head/blessing",
  version: 1,
  id: "b_2026-10-04_consuelo",
  title: "Bendición de consuelo",
  given: "2026-10-05T01:15Z", // still October 4 where it was given
  offset: -360,
  from: "",
  for: "Sofía",
  tags: [],
  language: "es",
  words: "Sofía, pongo mis manos sobre tu cabeza para darte una bendición de consuelo.\n\nTu Padre Celestial te conoce. Él sabe lo que has cargado estas semanas, y no lo has cargado sola. 🌟",
  changes: [],
};

const polished = (r) => {
  let out = "", at = 0;
  for (const c of r.changes) if (c.kept) (out += r.words.slice(at, c.at) + c.now), (at = c.at + c.was.length);
  return out + r.words.slice(at);
};

function vector(name, record, key, nonce, id) {
  const plain = Buffer.from(JSON.stringify(record), "utf8");
  const locked = seal(plain, key, nonce);
  return {
    name,
    key: { hex: Buffer.from(key).toString("hex"), base64url: b64url(key) },
    nonce: { hex: Buffer.from(nonce).toString("hex") },
    record,
    plaintext: { utf8: plain.toString("utf8"), base64: b64(plain), bytes: plain.length },
    locked: { base64: b64(locked), bytes: locked.length, sha256: createHash("sha256").update(locked).digest("hex") },
    id,
    link: `https://uponthyhead.app/b/${id}#${b64url(key)}`,
    shown: { title: record.title, polished: polished(record), keptChanges: record.changes.filter((c) => c.kept).length },
  };
}

const v1 = vector("comfort", comfort, bytes(1, 32), bytes(200, 12), b64url(bytes(9, 16)));
const v2 = vector("spanish, accents and an emoji", spanish, bytes(77, 32), bytes(3, 12), b64url(bytes(130, 16)));

const locked = Buffer.from(v1.locked.base64, "base64");
const altered = (fn) => {
  const copy = Buffer.from(locked);
  fn(copy);
  return b64(copy);
};
const refusals = [
  { name: "wrong key", locked: v1.locked.base64, key: b64url(bytes(2, 32)), error: "locked" },
  { name: "last byte of the tag changed", locked: altered((b) => (b[b.length - 1] ^= 1)), key: v1.key.base64url, error: "locked" },
  { name: "one byte of the words changed", locked: altered((b) => (b[40] ^= 1)), key: v1.key.base64url, error: "locked" },
  { name: "one byte of the nonce changed", locked: altered((b) => (b[5] ^= 1)), key: v1.key.base64url, error: "locked" },
  { name: "leading byte 2 (a later format)", locked: altered((b) => (b[0] = 2)), key: v1.key.base64url, error: "newer" },
  { name: "leading byte 0", locked: altered((b) => (b[0] = 0)), key: v1.key.base64url, error: "damaged" },
  { name: "cut short (30 bytes)", locked: b64(locked.subarray(0, 30)), key: v1.key.base64url, error: "damaged" },
  { name: "cut short (tag incomplete)", locked: b64(locked.subarray(0, locked.length - 3)), key: v1.key.base64url, error: "locked" },
];
const fragments = [
  { fragment: "", error: "key" },
  { fragment: v1.key.base64url.slice(0, 42), error: "key" },
  { fragment: `${v1.key.base64url}A`, error: "key" },
  { fragment: v1.key.base64url.replace(/.$/, "B"), error: "key", why: "the last character's spare bits are not zero" },
  { fragment: v1.key.base64url.replace(/^./, "+"), error: "key", why: "not the web-safe alphabet" },
  { fragment: `${v1.key.base64url}=`, error: "key", why: "padding" },
];

// Records that open (the key and the bytes are right) but must still be refused.
const badRecord = (name, edit, error = "record") => {
  const record = structuredClone(comfort);
  edit(record);
  const plain = Buffer.from(JSON.stringify(record), "utf8");
  return { name, key: v1.key.base64url, locked: b64(seal(plain, bytes(1, 32), bytes(200, 12))), error };
};
const records = [
  badRecord("record version 3", (r) => (r.version = 3), "newer"),
  badRecord("another format", (r) => (r.format = "something/else")),
  badRecord("a change that does not stand on the words", (r) => (r.changes[0].at += 1)),
  badRecord("changes that overlap", (r) => (r.changes[1].at = r.changes[0].at)),
  badRecord("a control character in the title", (r) => (r.title = "Comfort\u0007")),
  badRecord("February 30", (r) => (r.given = "2026-02-30T10:00Z")),
  badRecord("no words", (r) => delete r.words),
];

const out = {
  about: "Test vectors for website/PROTOCOL.md. Made by scripts/make-vectors.mjs with Node's own AES-256-GCM. Sealing each `plaintext` under its `key` and `nonce` must give exactly `locked`; opening `locked` with `key` must give `plaintext`.",
  format: { version: 1, cipher: "AES-256-GCM", nonceBytes: 12, tagBytes: 16, additionalData: "the single byte 0x01", maxBytes: 524288 },
  vectors: [v1, v2],
  refusals,
  fragments,
  records,
};
const file = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../protocol-vectors.json");
fs.writeFileSync(file, `${JSON.stringify(out, null, 2)}\n`);
console.log(v1.link, v1.link.length, "characters;", v1.locked.bytes, "and", v2.locked.bytes, "bytes locked");
