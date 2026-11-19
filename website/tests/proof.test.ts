// Proof of the app: challenges and passes, App Attest against a test attestation made here with a
// test root of our own, Play Integrity's verdict checks, the require-proof switch, the per-pass
// limit, the day's counts, and the warnings.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, createPublicKey, generateKeyPairSync, createVerify } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { resendAlert } from "../lib/links/alerts.ts";
import {
  APPLE_APP_ATTEST_ROOT,
  PROOF,
  PlayDecoder,
  challengeIsGood,
  makeChallenge,
  makePass,
  passId,
  requestHashOf,
  verifyAppAttest,
  verifyIntegrityVerdict,
} from "../lib/links/proof.ts";
import { type Answer, type Deps, type Proof, LIMITS, Limiter, challenge, create, prove, status } from "../lib/links/service.ts";
import { MemoryStore } from "../lib/links/store.ts";

const SECRET = new Uint8Array(Buffer.from("a test secret that is long enough to sign"));
const sha = (...p: (Uint8Array | string)[]) => {
  const h = createHash("sha256");
  p.forEach((x) => h.update(x));
  return h.digest();
};
/** A minute from now: a certificate made during the test is dated to the whole second it was made. */
const soon = () => Date.now() + 60000;
const error = (a: Answer) => (a.json as { error?: string } | undefined)?.error;
const locked = (n = 400) => Uint8Array.from({ length: n }, (_, i) => (i === 0 ? 1 : (i * 31) & 255));

// --- a tiny CBOR writer, for the test attestation -------------------------------------------
function cborOf(v: unknown): Buffer {
  const head = (major: number, n: number) =>
    n < 24 ? Buffer.from([(major << 5) | n]) : n < 256 ? Buffer.from([(major << 5) | 24, n]) : n < 65536 ? Buffer.from([(major << 5) | 25, n >> 8, n & 255]) : Buffer.from([(major << 5) | 26, n >>> 24, (n >> 16) & 255, (n >> 8) & 255, n & 255]);
  if (typeof v === "string") return Buffer.concat([head(3, Buffer.byteLength(v)), Buffer.from(v)]);
  if (v instanceof Uint8Array) return Buffer.concat([head(2, v.length), v]);
  if (Array.isArray(v)) return Buffer.concat([head(4, v.length), ...v.map(cborOf)]);
  const entries = Object.entries(v as object);
  return Buffer.concat([head(5, entries.length), ...entries.flatMap(([k, x]) => [cborOf(k), cborOf(x)])]);
}

// --- certificates made with openssl: a test root, an intermediate, and a leaf per attestation ---
let dir = "";
const ssl = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
const derOf = (pemFile: string) => new Uint8Array(ssl("x509", "-in", pemFile, "-outform", "DER"));
let rootPem = "", otherRootPem = "", middleDer = new Uint8Array();

before(() => {
  dir = mkdtempSync(path.join(os.tmpdir(), "attest-"));
  for (const name of ["root", "other"]) {
    ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${name}.key`);
    ssl("req", "-x509", "-new", "-key", `${name}.key`, "-subj", `/CN=Test ${name}`, "-days", "30",
      "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign", "-out", `${name}.pem`);
  }
  rootPem = readFileSync(path.join(dir, "root.pem"), "utf8");
  otherRootPem = readFileSync(path.join(dir, "other.pem"), "utf8");
  ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "middle.key");
  ssl("req", "-new", "-key", "middle.key", "-subj", "/CN=Test intermediate", "-out", "middle.csr");
  writeFileSync(path.join(dir, "middle.ext"), "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n");
  ssl("x509", "-req", "-in", "middle.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-days", "30", "-extfile", "middle.ext", "-out", "middle.pem");
  middleDer = derOf("middle.pem");
});
after(() => rmSync(dir, { recursive: true, force: true }));

let leaves = 0;
/** An attestation as the phone would send it, for `challenge`, with each part changeable. */
function attest(challengeText: string, o: { appId?: string; counter?: number; aaguid?: Buffer; credentialId?: Buffer; nonceFor?: string } = {}) {
  const n = ++leaves;
  ssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `leaf${n}.key`);
  const jwk = createPublicKey(readFileSync(path.join(dir, `leaf${n}.key`))).export({ format: "jwk" }) as { x: string; y: string };
  const keyId = sha(Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]));
  const counter = Buffer.alloc(4);
  counter.writeUInt32BE(o.counter ?? 0);
  const credentialId = o.credentialId ?? keyId;
  const idLength = Buffer.alloc(2);
  idLength.writeUInt16BE(credentialId.length);
  const authData = Buffer.concat([
    sha(o.appId ?? PROOF.appleAppId), Buffer.from([0x40]), counter,
    o.aaguid ?? Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)]), idLength, credentialId,
    Buffer.from([0xa0]), // stands for the COSE key, which is not checked
  ]);
  const nonce = sha(authData, sha(o.nonceFor ?? challengeText));
  ssl("req", "-new", "-key", `leaf${n}.key`, "-subj", `/CN=leaf ${n}`, "-out", `leaf${n}.csr`);
  writeFileSync(path.join(dir, `leaf${n}.ext`), `1.2.840.113635.100.8.2=DER:3024A1220420${nonce.toString("hex")}\n`);
  ssl("x509", "-req", "-in", `leaf${n}.csr`, "-CA", "middle.pem", "-CAkey", "middle.key", "-CAcreateserial", "-days", "30", "-extfile", `leaf${n}.ext`, "-out", `leaf${n}.pem`);
  const attestation = cborOf({ fmt: "apple-appattest", attStmt: { x5c: [derOf(`leaf${n}.pem`), middleDer], receipt: new Uint8Array(8) }, authData });
  return { attestation: new Uint8Array(attestation), keyId: keyId.toString("base64") };
}

function world(o: Partial<Proof> = {}) {
  const clock = { now: soon() };
  const store = new MemoryStore();
  const mails: { subject: string; text: string }[] = [];
  const tasks: Promise<unknown>[] = [];
  const proof: Proof = { secret: SECRET, require: false, appleRoot: rootPem, allowDevelopment: false, play: null, ...o };
  const deps: Deps = {
    store, limiter: new Limiter(), now: () => clock.now, proof,
    alert: async (subject, text) => void mails.push({ subject, text }),
    defer: (t) => void tasks.push(t()),
  };
  const settle = async () => {
    while (tasks.length) await tasks.shift();
  };
  const json = (body: object) => ({ contentType: "application/json", body: new Uint8Array(Buffer.from(JSON.stringify(body))), client: "a" });
  const fresh = async () => (await challenge(deps, { client: "a" })).json as { challenge: string; android?: { project: string } };
  const passFor = async () => {
    const c = (await fresh()).challenge;
    const a = attest(c);
    const answer = await prove(deps, json({ platform: "ios", challenge: c, keyId: a.keyId, attestation: Buffer.from(a.attestation).toString("base64") }));
    return answer;
  };
  const make = (pass: string | null = null, client = "a", body = locked()) => create(deps, { contentType: "application/octet-stream", body, client, pass });
  return { clock, store, mails, deps, settle, json, fresh, passFor, make, today: () => new Date(clock.now).toISOString().slice(0, 10) };
}

test("a challenge is good for five minutes, and only as made by this server", () => {
  const now = soon();
  const { challenge: c } = makeChallenge(SECRET, now);
  assert.match(c, /^c1\.\d+\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{22}$/);
  assert.ok(challengeIsGood(SECRET, c, now));
  assert.ok(challengeIsGood(SECRET, c, now + 4 * 60 * 1000));
  assert.ok(!challengeIsGood(SECRET, c, now + 5 * 60 * 1000 + 1000), "expired");
  assert.ok(!challengeIsGood(new Uint8Array(Buffer.from("another secret, also long enough!!")), c, now), "another server's");
  const parts = c.split(".");
  assert.ok(!challengeIsGood(SECRET, [parts[0], String(Number(parts[1]) + 3600), parts[2], parts[3]].join("."), now), "life stretched");
  assert.ok(!challengeIsGood(SECRET, "nonsense", now));
});

test("a pass is good for seven days, then not; a changed pass never", () => {
  const now = soon();
  const { pass, expires } = makePass(SECRET, "AAAAAAAAAAAAAAAAAAAAAA", now);
  assert.equal(passId(SECRET, pass, now), "AAAAAAAAAAAAAAAAAAAAAA");
  assert.equal(expires, Math.floor((now + 7 * 86400000) / 1000) * 1000);
  assert.equal(passId(SECRET, pass, expires - 1000), "AAAAAAAAAAAAAAAAAAAAAA");
  assert.equal(passId(SECRET, pass, expires), null, "expired");
  assert.equal(passId(SECRET, pass.replace("p1.A", "p1.B"), now), null, "another id");
  assert.equal(passId(SECRET, pass.slice(0, -1) + (pass.endsWith("A") ? "B" : "A"), now), null, "changed signature");
});

test("App Attest: a good attestation verifies against the root", () => {
  const now = soon();
  const c = makeChallenge(SECRET, now).challenge;
  const a = attest(c);
  const v = verifyAppAttest({ ...a, challenge: c, now, root: rootPem, allowDevelopment: false });
  assert.equal(v.ok ? "ok" : v.reason, "ok");
});

test("App Attest: each check refuses what it should", () => {
  const now = soon();
  const c = makeChallenge(SECRET, now).challenge;
  const check = (a: { attestation: Uint8Array; keyId: string }, o: { root?: string; allowDevelopment?: boolean; challenge?: string; now?: number } = {}) => {
    const v = verifyAppAttest({ ...a, challenge: o.challenge ?? c, now: o.now ?? now, root: o.root ?? rootPem, allowDevelopment: o.allowDevelopment ?? false });
    return v.ok ? "ok" : v.reason;
  };
  const good = attest(c);
  assert.equal(check(good, { root: otherRootPem }), "chain", "another root");
  assert.equal(check(good, { now: now + 40 * 86400000 }), "chain", "out of date");
  assert.equal(check(good, { challenge: makeChallenge(SECRET, now).challenge }), "nonce", "another challenge");
  assert.equal(check(attest(c, { nonceFor: "something else" })), "nonce", "nonce over something else");
  assert.equal(check({ ...good, keyId: Buffer.alloc(32, 7).toString("base64") }), "key", "another key id");
  assert.equal(check(attest(c, { credentialId: Buffer.alloc(32, 9) })), "key", "credential id not the key");
  assert.equal(check(attest(c, { appId: "7R77MUH4FF.some.other.app" })), "app", "another app");
  assert.equal(check(attest(c, { counter: 1 })), "counter", "counter not zero");
  const development = attest(c, { aaguid: Buffer.from("appattestdevelop") });
  assert.equal(check(development), "environment", "development refused by default");
  assert.equal(check(development, { allowDevelopment: true }), "ok", "development when allowed");
  assert.equal(check(attest(c, { aaguid: Buffer.alloc(16) })), "environment", "unknown environment");
  assert.equal(check({ attestation: new Uint8Array([1, 2, 3]), keyId: good.keyId }), "format");
  assert.equal(check(good, { root: APPLE_APP_ATTEST_ROOT }), "chain", "Apple's real root did not sign a test certificate");
});

test("Play Integrity: the verdict must be this app, recognised by Play, on a device with integrity, for this challenge", () => {
  const now = soon();
  const c = makeChallenge(SECRET, now).challenge;
  const good = () => ({
    requestDetails: { requestPackageName: PROOF.androidPackage, requestHash: requestHashOf(c), timestampMillis: String(now) },
    appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED", packageName: PROOF.androidPackage },
    deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
  });
  const check = (p: unknown, ch = c) => {
    const v = verifyIntegrityVerdict(p, ch, now);
    return v.ok ? "ok" : v.reason;
  };
  assert.equal(check(good()), "ok");
  assert.equal(check(good(), makeChallenge(SECRET, now).challenge), "request", "another challenge");
  assert.equal(check({ ...good(), requestDetails: { ...good().requestDetails, requestPackageName: "com.other" } }), "request");
  assert.equal(check({ ...good(), requestDetails: { ...good().requestDetails, timestampMillis: String(now - 3600000) } }), "request", "old token");
  assert.equal(check({ ...good(), appIntegrity: { ...good().appIntegrity, appRecognitionVerdict: "UNRECOGNIZED_VERSION" } }), "app");
  assert.equal(check({ ...good(), appIntegrity: { ...good().appIntegrity, packageName: "com.other" } }), "app");
  assert.equal(check({ ...good(), deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY"] } }), "device");
  assert.equal(check({ ...good(), deviceIntegrity: {} }), "device");
  assert.equal(check(null), "request");
});

test("Play Integrity: the decoder signs in with the service account and asks Google to decode", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const account = JSON.stringify({ client_email: "proof@example.iam.gserviceaccount.com", private_key: privateKey.export({ type: "pkcs8", format: "pem" }) });
  const calls: { url: string; body: string; auth: string }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url: String(url), body: String(init.body), auth: new Headers(init.headers).get("authorization") ?? "" });
    if (String(url).includes("oauth2")) return Response.json({ access_token: "ACCESS", expires_in: 3600 });
    return Response.json({ tokenPayloadExternal: { decoded: true } });
  }) as typeof fetch;
  const decoder = PlayDecoder.from(Buffer.from(account).toString("base64"), fetcher)!;
  assert.ok(decoder, "a base64 key is read");
  assert.deepEqual(await decoder.decode("TOKEN", Date.now()), { decoded: true });
  assert.deepEqual(await decoder.decode("TOKEN2", Date.now()), { decoded: true });
  assert.equal(calls.filter((c) => c.url.includes("oauth2")).length, 1, "the access token is kept until it expires");
  const jwt = new URLSearchParams(calls[0].body).get("assertion")!.split(".");
  assert.ok(createVerify("RSA-SHA256").update(`${jwt[0]}.${jwt[1]}`).verify(publicKey, Buffer.from(jwt[2], "base64url")), "the JWT is signed by the key");
  assert.equal(JSON.parse(Buffer.from(jwt[1], "base64url").toString()).scope, "https://www.googleapis.com/auth/playintegrity");
  assert.equal(calls[1].url, "https://playintegrity.googleapis.com/v1/dev.summitstudio.uponthyhead:decodeIntegrityToken");
  assert.equal(calls[1].auth, "Bearer ACCESS");
  assert.deepEqual(JSON.parse(calls[1].body), { integrity_token: "TOKEN" });
  assert.equal(PlayDecoder.from(undefined), null);
  assert.equal(PlayDecoder.from("not a key"), null);
});

test("the proof endpoint: a good attestation gets a pass; a bad one is counted as failed", async () => {
  const w = world();
  const ok = await w.passFor();
  assert.equal(ok.status, 200);
  const { pass, expires } = ok.json as { pass: string; expires: string };
  assert.match(pass, /^p1\./);
  assert.equal(Date.parse(expires), Math.floor((w.clock.now + 7 * 86400000) / 1000) * 1000);

  const c = (await w.fresh()).challenge;
  const a = attest(c, { counter: 3 });
  const bad = await prove(w.deps, w.json({ platform: "ios", challenge: c, keyId: a.keyId, attestation: Buffer.from(a.attestation).toString("base64") }));
  assert.deepEqual([bad.status, error(bad)], [400, "proof"]);
  const stale = await prove(w.deps, w.json({ platform: "ios", challenge: "c1.1.AAAAAAAAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAA", keyId: a.keyId, attestation: "AA==" }));
  assert.equal(error(stale), "proof");
  assert.equal(error(await prove(w.deps, w.json({ platform: "windows", challenge: c }))), "format");
  assert.equal(error(await prove(w.deps, { ...w.json({}), contentType: "text/plain" })), "type");
  await w.settle();
  const counts = await w.store.counts(w.today());
  assert.deepEqual(counts, { "proof:ios:ok": 1, "proof:ios:failed": 2, "proof:ios:failed:counter": 1, "proof:ios:failed:challenge": 1 });
});

test("the same attestation sent twice gives the same pass id, not a new allowance", async () => {
  const w = world();
  const c = (await w.fresh()).challenge;
  const a = attest(c);
  const body = w.json({ platform: "ios", challenge: c, keyId: a.keyId, attestation: Buffer.from(a.attestation).toString("base64") });
  const one = ((await prove(w.deps, body)).json as { pass: string }).pass;
  const two = ((await prove(w.deps, body)).json as { pass: string }).pass;
  assert.equal(passId(SECRET, one, w.clock.now), passId(SECRET, two, w.clock.now));
});

test("Android: with Play Integrity not set up, no project is offered and proofs are refused cleanly", async () => {
  const w = world();
  const c = await w.fresh();
  assert.equal(c.android, undefined);
  const r = await prove(w.deps, w.json({ platform: "android", challenge: c.challenge, token: "TOKEN" }));
  assert.deepEqual([r.status, error(r)], [503, "not_set_up"]);
  await w.settle();
  assert.deepEqual(await w.store.counts(w.today()), { "proof:android:not_set_up": 1 });
});

test("Android: set up, a good verdict gets a pass and a bad one is refused", async () => {
  let verdict: unknown = null;
  const w = world({ play: { project: "123456789012", decode: async () => verdict } });
  const c = await w.fresh();
  assert.deepEqual(c.android, { project: "123456789012" });
  verdict = {
    requestDetails: { requestPackageName: PROOF.androidPackage, requestHash: requestHashOf(c.challenge), timestampMillis: String(w.clock.now) },
    appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED", packageName: PROOF.androidPackage },
    deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY", "MEETS_BASIC_INTEGRITY"] },
  };
  assert.equal((await prove(w.deps, w.json({ platform: "android", challenge: c.challenge, token: "T" }))).status, 200);
  verdict = { ...(verdict as object), deviceIntegrity: { deviceRecognitionVerdict: [] } };
  assert.equal(error(await prove(w.deps, w.json({ platform: "android", challenge: c.challenge, token: "T" }))), "proof");
  verdict = null;
  assert.equal(error(await prove(w.deps, w.json({ platform: "android", challenge: c.challenge, token: "T" }))), "proof");
  await w.settle();
  assert.deepEqual(await w.store.counts(w.today()), { "proof:android:ok": 1, "proof:android:failed": 2, "proof:android:failed:device": 1, "proof:android:failed:decode": 1 });
});

test("with no secret set, no proof is offered and a link is made as before", async () => {
  const w = world({ secret: null });
  assert.equal(error(await challenge(w.deps, { client: "a" })), "unavailable");
  assert.equal((await w.make()).status, 201);
});

test("making a link: a good pass, no pass, a bad pass, and the require-proof switch", async () => {
  const w = world();
  const pass = ((await w.passFor()).json as { pass: string }).pass;
  assert.equal((await w.make(pass)).status, 201, "with a pass");
  assert.equal((await w.make()).status, 201, "without, while proof is not required");
  const bad = await w.make(pass.slice(0, -2) + "xx");
  assert.deepEqual([bad.status, error(bad)], [401, "pass"], "a pass the server did not sign: get a new one");
  w.clock.now += 7 * 86400000;
  assert.equal(error(await w.make(pass, "b")), "pass", "an expired pass");

  const strict = world({ require: true });
  const refused = await strict.make();
  assert.deepEqual([refused.status, error(refused)], [403, "proof"]);
  const strictPass = ((await strict.passFor()).json as { pass: string }).pass;
  assert.equal((await strict.make(strictPass)).status, 201);

  await w.settle();
  await strict.settle();
  const counts = await w.store.counts(new Date(w.clock.now - 7 * 86400000).toISOString().slice(0, 10));
  assert.equal(counts["links:proven"], 1);
  assert.equal(counts["links:unproven"], 1);
  assert.equal(counts["pass:refused"], 1);
  const strictCounts = await strict.store.counts(strict.today());
  assert.equal(strictCounts["links:refused_no_proof"], 1);
  assert.equal(strictCounts["links:proven"], 1);
});

test("a pass is limited like an address: 10 in 10 minutes, whatever the network", async () => {
  const w = world();
  const pass = ((await w.passFor()).json as { pass: string }).pass;
  for (let i = 0; i < 10; i++) assert.equal((await w.make(pass, `net${i}`)).status, 201, `link ${i + 1}`);
  const eleventh = await w.make(pass, "net10");
  assert.deepEqual([eleventh.status, error(eleventh)], [429, "slow_down"]);
  assert.equal((await w.make(null, "net10")).status, 201, "the network itself is not held by the pass's limit");
});

test("the owner is warned once at 50% and once at 90% of the day's links, and a failing warning breaks nothing", async () => {
  const was = LIMITS.dayLinks;
  LIMITS.dayLinks = 10;
  try {
    const w = world();
    for (let i = 0; i < 10; i++) assert.equal((await w.make(null, `net${i}`)).status, 201);
    await w.settle();
    assert.deepEqual(w.mails.map((m) => m.subject), ["Upon Thy Head: 50% of today's link links used", "Upon Thy Head: 90% of today's link links used"]);
    assert.match(w.mails[1].text, /Links: 9 of 10/);
    assert.doesNotMatch(w.mails.map((m) => m.text).join(), /net\d/, "counts only");
    assert.equal(error(await w.make(null, "net11")), "full");
    await w.settle();
    assert.equal(w.mails.length, 2, "not again past 100%");

    const broken = world();
    broken.deps.alert = async () => {
      throw new Error("mail is down");
    };
    for (let i = 0; i < 6; i++) assert.equal((await broken.make(null, `net${i}`)).status, 201);
    await broken.settle();
    const quiet = world();
    quiet.deps.alert = undefined;
    for (let i = 0; i < 6; i++) assert.equal((await quiet.make(null, `net${i}`)).status, 201);
    await quiet.settle();
  } finally {
    LIMITS.dayLinks = was;
  }
});

test("bytes are warned on too, each threshold once", async () => {
  const was = LIMITS.dayBytes;
  LIMITS.dayBytes = 4000;
  try {
    const w = world();
    for (let i = 0; i < 9; i++) await w.make(null, `net${i}`, locked(400)); // 3,600 bytes: 90%
    await w.settle();
    assert.deepEqual(w.mails.map((m) => m.subject), ["Upon Thy Head: 50% of today's link bytes used", "Upon Thy Head: 90% of today's link bytes used"]);
  } finally {
    LIMITS.dayBytes = was;
  }
});

test("Resend: sends counts to the owner when set up, and nothing when not", async () => {
  assert.equal(resendAlert({}), undefined);
  assert.equal(resendAlert({ RESEND_API_KEY: "k", ALERT_TO: "a@example.com" }), undefined);
  const sent: { url: string; init: RequestInit }[] = [];
  const alert = resendAlert({ RESEND_API_KEY: "k", ALERT_TO: "a@example.com, b@example.com", ALERT_FROM: "Links <links@example.com>" }, (async (url: string, init: RequestInit) => {
    sent.push({ url, init });
    return new Response("{}", { status: 200 });
  }) as typeof fetch)!;
  await alert("subject", "text");
  assert.equal(sent[0].url, "https://api.resend.com/emails");
  assert.deepEqual(JSON.parse(String(sent[0].init.body)), { from: "Links <links@example.com>", to: ["a@example.com", "b@example.com"], subject: "subject", text: "text" });
});

test("status: today's and yesterday's totals and counts, nothing about who", async () => {
  const w = world();
  const pass = ((await w.passFor()).json as { pass: string }).pass;
  await w.make(pass);
  await w.make();
  await w.settle();
  const s = (await status(w.deps)).json as { today: { links: number; counts: Record<string, number>; used: { links: number } }; yesterday: { links: number }; proof: { offered: boolean } };
  assert.equal(s.today.links, 2);
  assert.equal(s.yesterday.links, 0);
  assert.deepEqual(s.today.counts, { "proof:ios:ok": 1, "links:proven": 1, "links:unproven": 1 });
  assert.equal(s.today.used.links, Math.round((2 / LIMITS.dayLinks) * 1000) / 10);
  assert.equal(s.proof.offered, true);
});

test("the proof endpoints are rate-limited", async () => {
  const w = world();
  for (let i = 0; i < 20; i++) assert.equal((await challenge(w.deps, { client: "x" })).status, 200);
  assert.equal(error(await challenge(w.deps, { client: "x" })), "slow_down");
  for (let i = 0; i < 10; i++) await prove(w.deps, { ...w.json({}), client: "x" });
  assert.equal(error(await prove(w.deps, { ...w.json({}), client: "x" })), "slow_down");
});
