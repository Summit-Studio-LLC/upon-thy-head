// The format, checked against protocol-vectors.json (made with Node's own AES-GCM) using the very
// code the receiver's page runs.
import assert from "node:assert/strict";
import fs from "node:fs";
import { test } from "node:test";
import { LinkError, MAX_BYTES, fromBase64Url, keptChanges, keyFromFragment, linkFor, open, paragraphs, polished, readRecord, readShared, seal, toBase64Url } from "../public/shared/format.js";
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

// 2026-11-18: a blessing entered from a written copy, known only to its year or month (record version 2)
const v2Record = (fields) => {
  const r = JSON.parse(V.vectors[0].plaintext.utf8);
  return new TextEncoder().encode(JSON.stringify({ ...r, version: 2, changes: [], ...fields }));
};

test("record version 2: an entered blessing known only to its year is read with both", () => {
  const r = readRecord(v2Record({ precision: "year", entered: true, given: "1998-07-02T18:00Z", offset: -360 }));
  assert.equal(r.precision, "year");
  assert.equal(r.entered, true);
});

test("record version 1 and 2 without the new fields: a full date, as spoken", () => {
  const old = readRecord(new TextEncoder().encode(V.vectors[0].plaintext.utf8));
  assert.equal(old.precision, "day");
  assert.equal(old.entered, false);
  assert.equal(readRecord(v2Record({ precision: "month" })).precision, "month");
});

test("refuses a precision or entered that is not one of the known ones", async () => {
  assert.equal(await code(() => readRecord(v2Record({ precision: "week" }))), "record");
  assert.equal(await code(() => readRecord(v2Record({ entered: "yes" }))), "record");
});

test("entered words: each line break ends a paragraph; a recording's only a blank line", () => {
  assert.deepEqual(paragraphs("One.\nTwo.\n\nThree.", true), ["One.", "Two.", "Three."]);
  assert.deepEqual(paragraphs("One.\nTwo.\n\nThree."), ["One.\nTwo.", "Three."]);
});

// 2026-11-18: a family member's whole ring handed to their own phone (record version 3, kind "ring")
const ringOf = (fields = {}, blessings) => {
  const r = JSON.parse(V.vectors[0].plaintext.utf8);
  const list = blessings ?? [
    { ...r, id: "b2", given: "2014-08-03T18:00Z", title: "Second" },
    { ...r, id: "b1", version: 2, given: "2008-08-10T18:00Z", precision: "month", entered: true, changes: [], title: "First" },
    { ...r, id: "b1", given: "2008-08-10T18:00Z", title: "First again" },
  ];
  return new TextEncoder().encode(JSON.stringify({ format: "upon-thy-head/blessing", version: 3, kind: "ring", keptBy: "Dad", blessings: list, ...fields }));
};

test("a ring opens to every blessing, oldest first, each once, with who kept them", async () => {
  const key = hex(V.vectors[0].key.hex), nonce = hex(V.vectors[0].nonce.hex);
  const shared = readShared(await open(await seal(ringOf(), key, nonce), key));
  assert.equal(shared.kind, "ring");
  assert.equal(shared.keptBy, "Dad");
  assert.deepEqual(shared.records.map((r) => r.title), ["First", "Second"]);
  assert.equal(shared.records[0].precision, "month");
  assert.equal(shared.records[0].entered, true);
});

test("a single blessing still reads as before through readShared; a ring is 'newer' to readRecord", async () => {
  const one = readShared(new TextEncoder().encode(V.vectors[0].plaintext.utf8));
  assert.equal(one.kind, "blessing");
  assert.equal(one.record.id, readRecord(new TextEncoder().encode(V.vectors[0].plaintext.utf8)).id);
  // what a page from before rings does with one: made with a newer version
  assert.equal(await code(() => readRecord(ringOf())), "newer");
});

test("a ring refuses what is not one: a later version, no blessings, a bad blessing, a bad keptBy", async () => {
  assert.equal(await code(() => readShared(ringOf({ version: 4 }))), "newer");
  assert.equal(await code(() => readShared(ringOf({ blessings: [] }))), "record");
  assert.equal(await code(() => readShared(ringOf({}, [{ format: "upon-thy-head/blessing", version: 1 }]))), "record");
  assert.equal(await code(() => readShared(ringOf({ keptBy: "a\u0000b" }))), "record");
});

test("a ring of 60 ordinary blessings fits the 512 KiB cap with room to spare", async () => {
  const r = JSON.parse(V.vectors[0].plaintext.utf8);
  const words = "Bendigo tu corazón con paz, y que la fe te acompañe día y noche. ".repeat(80); // about 900 words
  const list = Array.from({ length: 60 }, (_, i) => ({ ...r, id: `b${i}`, words, changes: [] }));
  const plain = ringOf({}, list);
  assert.ok(plain.length + 29 < MAX_BYTES / 1.5, `${plain.length} bytes`);
  assert.equal(MAX_BYTES, 524288);
});
