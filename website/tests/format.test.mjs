// The format, checked against protocol-vectors.json (made with Node's own AES-GCM) using the very
// code the receiver's page runs.
import assert from "node:assert/strict";
import fs from "node:fs";
import { test } from "node:test";
import { LinkError, MAX_BYTES, fromBase64Url, keptChanges, keyFromFragment, linkFor, open, paragraphs, polished, readRecord, seal, toBase64Url } from "../public/shared/format.js";
import { LIMITS } from "../lib/links/service.ts";

const V = JSON.parse(fs.readFileSync(new URL("../protocol-vectors.json", import.meta.url), "utf8"));
const raw = (base64) => new Uint8Array(Buffer.from(base64, "base64"));
const hex = (h) => new Uint8Array(Buffer.from(h, "hex"));
const code = async (fn) => {
  try {
    await fn();
  } catch (e) {
    assert.ok(e instanceof LinkError, `threw ${e}`);
    return e.code;
  }
  return "opened";
};

for (const v of V.vectors) {
  test(`vector "${v.name}": sealing gives exactly the locked bytes`, async () => {
    const locked = await seal(raw(v.plaintext.base64), hex(v.key.hex), hex(v.nonce.hex));
    assert.equal(Buffer.from(locked).toString("base64"), v.locked.base64);
  });
  test(`vector "${v.name}": the link opens to the record and shows the right words`, async () => {
    const url = new URL(v.link);
    assert.equal(v.link, linkFor("https://uponthyhead.app", v.id, hex(v.key.hex)));
    assert.ok(v.link.length <= 100, `${v.link.length} characters`);
    const plain = await open(raw(v.locked.base64), keyFromFragment(url.hash));
    assert.equal(new TextDecoder().decode(plain), v.plaintext.utf8);
    const record = readRecord(plain);
    assert.equal(record.title, v.shown.title);
    assert.equal(polished(record), v.shown.polished);
    assert.equal(keptChanges(record), v.shown.keptChanges);
    assert.equal(paragraphs(polished(record)).length, 2);
  });
}

test("the restored change leaves the spoken words; the kept ones apply", () => {
  const shown = V.vectors[0].shown.polished;
  assert.ok(shown.startsWith("Emma, I lay my hands upon your head, to give you a blessing of comfort."));
  assert.ok(shown.includes("and, uh, He wants"));
});

for (const r of V.refusals) {
  test(`refuses: ${r.name}`, async () => {
    assert.equal(await code(() => open(raw(r.locked), fromBase64Url(r.key))), r.error);
  });
}
for (const f of V.fragments) {
  test(`refuses the fragment "${f.fragment.slice(0, 12)}…" (${f.why ?? f.fragment.length + " characters"})`, async () => {
    assert.equal(await code(() => keyFromFragment(`#${f.fragment}`)), f.error);
  });
}
for (const r of V.records) {
  test(`opens but refuses the record: ${r.name}`, async () => {
    assert.equal(await code(async () => readRecord(await open(raw(r.locked), fromBase64Url(r.key)))), r.error);
  });
}

test("refuses a locked copy over the size cap, before trying the key", async () => {
  assert.equal(await code(() => open(new Uint8Array(MAX_BYTES + 1).fill(1), new Uint8Array(32))), "damaged");
});

test("the page and the service agree on the limits", () => {
  assert.equal(MAX_BYTES, LIMITS.maxBytes);
  assert.equal(V.format.maxBytes, LIMITS.maxBytes);
});

test("base64url round trip at every length", () => {
  for (let n = 0; n < 70; n++) {
    const b = Uint8Array.from({ length: n }, (_, i) => (i * 37 + n) & 255);
    assert.equal(toBase64Url(b), Buffer.from(b).toString("base64url"));
    assert.deepEqual(fromBase64Url(toBase64Url(b)), b);
  }
});

test("a 2,500-word blessing with accents and an emoji fits well under the cap", async () => {
  const sentence = "Bendigo tu corazón con paz, y que la fe te acompañe día y noche 🌟. ";
  const words = Array.from({ length: 180 }, (_, i) => sentence + (i % 6 === 5 ? "\n\n" : "")).join("");
  assert.ok(words.split(/\s+/).length >= 2500);
  const record = { ...V.vectors[1].record, words };
  const locked = await seal(new TextEncoder().encode(JSON.stringify(record)), hex(V.vectors[1].key.hex), hex(V.vectors[1].nonce.hex));
  assert.ok(locked.length < MAX_BYTES / 3, `${locked.length} bytes`);
  assert.equal(polished(readRecord(await open(locked, hex(V.vectors[1].key.hex)))), words);
});
