// Locked copies for tool/android_share.py, made with Node's own AES-256-GCM exactly as
// website/PROTOCOL.md §3 says (not the app's code), for the refusals and for opening a copy the app
// sent. Prints one line of JSON.
//
//   node tool/android_share_seal.mjs open <copy file from the website's folder> <key>
//        → {"plain": "<the record's text>"}
//   node tool/android_share_seal.mjs seal <record text file> <version byte>
//        → {"locked": "<base64>", "key": "<43 characters>"}
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";

const [what, file, arg] = process.argv.slice(2);
const b64u = (b) => Buffer.from(b).toString("base64url");
if (what === "open") {
  const kept = JSON.parse(readFileSync(file, "utf8"));
  const locked = Buffer.from(kept.c, "base64");
  const d = createDecipheriv("aes-256-gcm", Buffer.from(arg, "base64url"), locked.subarray(1, 13));
  d.setAAD(locked.subarray(0, 1));
  d.setAuthTag(locked.subarray(locked.length - 16));
  const plain = Buffer.concat([d.update(locked.subarray(13, locked.length - 16)), d.final()]);
  console.log(JSON.stringify({ plain: plain.toString("utf8") }));
} else if (what === "seal") {
  const plain = readFileSync(file);
  const key = randomBytes(32), nonce = randomBytes(12), v = Buffer.from([Number(arg ?? 1)]);
  const c = createCipheriv("aes-256-gcm", key, nonce);
  c.setAAD(v);
  const body = Buffer.concat([c.update(plain), c.final(), c.getAuthTag()]);
  console.log(JSON.stringify({ locked: Buffer.concat([v, nonce, body]).toString("base64"), key: b64u(key) }));
} else {
  process.exit(2);
}
