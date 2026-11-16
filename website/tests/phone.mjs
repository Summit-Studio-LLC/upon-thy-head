// Plays the phone's part of PROTOCOL.md with Node's own crypto (not the page's code): locks a
// record, sends the locked copy, and builds the link. Run it to make a link by hand:
//   node tests/phone.mjs http://localhost:3000
import { createCipheriv, randomBytes } from "node:crypto";
import fs from "node:fs";

export const sample = () => JSON.parse(fs.readFileSync(new URL("../protocol-vectors.json", import.meta.url), "utf8")).vectors[0].record;

export function lock(record, key = randomBytes(32), nonce = randomBytes(12)) {
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.of(1));
  const locked = Buffer.concat([Buffer.of(1), nonce, cipher.update(Buffer.from(JSON.stringify(record), "utf8")), cipher.final(), cipher.getAuthTag()]);
  return { key, locked };
}

/** Lock `record`, send it to the service at `origin`, and give back the link and what the phone keeps. */
export async function share(origin, record = sample()) {
  const { key, locked } = lock(record);
  const response = await fetch(`${origin}/api/b`, { method: "POST", headers: { "content-type": "application/octet-stream" }, body: locked });
  if (response.status !== 201) throw new Error(`create answered ${response.status} ${await response.text()}`);
  const { id, expires, stop } = await response.json();
  const keyText = key.toString("base64url");
  return { id, expires, stop, key: keyText, link: `${origin}/b/${id}#${keyText}`, bytes: locked.length };
}

export const stop = (origin, { id, stop: token }) => fetch(`${origin}/api/b/${id}`, { method: "DELETE", headers: { authorization: `Bearer ${token}` } });

if (import.meta.url === `file://${process.argv[1]}`) {
  const made = await share(process.argv[2] ?? "http://localhost:3000");
  console.log(`${made.link}\n\nstops ${made.expires}; ${made.bytes} bytes locked\nto stop it now:\n  curl -X DELETE -H "Authorization: Bearer ${made.stop}" ${process.argv[2] ?? "http://localhost:3000"}/api/b/${made.id}`);
}
