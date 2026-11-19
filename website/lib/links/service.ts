// The service behind shared links: create, read, stop, sweep. PROTOCOL.md is the contract.
//
// It never sees a key, a title or a word: only locked bytes. It keeps no address, no device
// detail and no log line of its own. The route handlers in app/api are thin wrappers round this.

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { Alert } from "./alerts.ts";
import { PROOF, challengeIsGood, makeChallenge, makePass, passId, passIdFor, verifyAppAttest, verifyIntegrityVerdict } from "./proof.ts";
import type { Store } from "./store.ts";

export const LIMITS = {
  version: 1,
  /**
   * The largest locked copy kept: 512 KiB, so a family member's whole ring handed to their own
   * phone travels as one link (about 100 ordinary blessings, or 30 of the longest). It was 64 KiB
   * until 2026-11-18. See PROTOCOL.md §5.
   */
  maxBytes: 524288,
  /** Version byte, nonce, tag, and the two bytes of "{}". */
  minBytes: 1 + 12 + 16 + 2,
  lifeMs: 30 * 24 * 60 * 60 * 1000,
  /**
   * Everyone together, per UTC day. 12 MiB (6 MiB until 2026-11-18, when a ring could be one link):
   * thirty full days are 360 MiB, inside Neon's free 0.5 GB.
   */
  dayLinks: Number(process.env.LINKS_DAY_LINKS ?? 1000),
  dayBytes: Number(process.env.LINKS_DAY_BYTES ?? 12 * 1024 * 1024),
  /** One client (see clientOf in app/api/b/http.ts): [how many, in how many milliseconds]. */
  create: [10, 10 * 60 * 1000] as const,
  createDay: [40, 24 * 60 * 60 * 1000] as const,
  /**
   * One client's bytes in a day (added with the 512 KiB cap): a family handing over three or four
   * rings fits; one network cannot spend the whole day's allowance alone.
   */
  createBytesDay: [3 * 1024 * 1024, 24 * 60 * 60 * 1000] as const,
  read: [120, 60 * 1000] as const,
  stop: [30, 60 * 1000] as const,
  /**
   * Everyone together, whoever they are. The per-client counts above can be outrun by a sender
   * with more addresses than the limiter's table holds (it drops the longest-idle sender when
   * full, so that nobody is locked out). These ceilings do not depend on how many senders there
   * are, so they hold regardless. Set far above honest use: a blessing is opened a handful of
   * times, and creating is already capped per day by dayLinks.
   */
  readAll: [Number(process.env.LINKS_READS_PER_MINUTE ?? 3000), 60 * 1000] as const,
  createAll: [Number(process.env.LINKS_CREATES_PER_MINUTE ?? 120), 60 * 1000] as const,
  /** Proof of the app: a challenge, then a proof, about once a week per phone. */
  challenge: [20, 10 * 60 * 1000] as const,
  prove: [10, 10 * 60 * 1000] as const,
  proofAll: [300, 60 * 1000] as const,
  /** The day's use, as a share of the allowance, at which the owner is warned (once each a day). */
  warnAt: [50, 90] as const,
};

export const ID = /^[A-Za-z0-9_-]{22}$/;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;

export type Answer = { status: number; headers?: Record<string, string>; json?: unknown; bytes?: Uint8Array };

/**
 * Counts in memory only, so nothing about a client is ever written anywhere.
 *
 * Each kind of request ("create", "read", …) has its own table, so the day-long windows of one
 * kind cannot use up the room another needs. Every table has a hard bound. When one is full, the
 * sender who has gone longest without a request is dropped to make room: nobody is ever refused
 * because the table is full, and no request does more than a fixed, small amount of work (there is
 * no sweep). The cost is that under a flood from more than `maxClients` addresses a sender's count
 * can be forgotten early. What still holds then are the ceilings newcomers share, which no
 * number of addresses can raise (LIMITS.readAll and createAll per minute; see takeWithCeiling),
 * and the daily budget (LIMITS.dayLinks, LIMITS.dayBytes). This is a deliberate trade: a full table that
 * refused unknown senders would let a flood lock honest people out, which is worse here than a
 * flood being held only by the shared ceilings.
 */
export class Limiter {
  /** The most senders counted at once, per kind of request. Past this a table does not grow. */
  static readonly maxClients = 20000;
  private tables = new Map<string, Map<string, { count: number; ends: number }>>();

  /** Take one from `client`'s allowance for `what`. Returns 0 if allowed, or the seconds to wait. */
  take(what: string, client: string, [max, windowMs]: readonly [number, number], now: number, amount = 1): number {
    let table = this.tables.get(what);
    if (!table) this.tables.set(what, (table = new Map()));
    let w = table.get(client);
    // A Map keeps the order things were put in, so taking a sender out and putting them back
    // moves them to the end: the front is always whoever has gone longest without a request.
    if (w) table.delete(client);
    if (!w || w.ends <= now) {
      if (table.size >= Limiter.maxClients) table.delete(table.keys().next().value as string);
      w = { count: 0, ends: now + windowMs };
    }
    table.set(client, w);
    if (w.count + amount > max) return Math.max(1, Math.ceil((w.ends - now) / 1000));
    w.count += amount;
    return 0;
  }

  /** Whether `client` is being counted for `what` right now (has a window that has not ended). */
  knows(what: string, client: string, now: number): boolean {
    const w = this.tables.get(what)?.get(client);
    return w !== undefined && w.ends > now;
  }

  /**
   * Take one from `client`'s own allowance; and if the limiter was not already counting them,
   * one from the allowance all newcomers share. A sender who is already being counted is held
   * only by their own limit, so a flood of new addresses cannot use up what honest people in the
   * middle of something need. A flood is held by the shared allowance, because every address in
   * it is a newcomer, the first time and again each time it is dropped from a full table.
   */
  takeWithCeiling(what: string, client: string, own: readonly [number, number], shared: readonly [number, number], now: number): number {
    const newcomer = !this.knows(what, client, now);
    return this.take(what, client, own, now) || (newcomer ? this.take(`${what}-all`, EVERYONE, shared, now) : 0);
  }

  /** How many senders are being counted for `what` (for tests). */
  size(what: string): number {
    return this.tables.get(what)?.size ?? 0;
  }
}

/** The one name everyone is counted under for the ceilings that ignore who is asking. */
const EVERYONE = "*";

/** Proof of the app (lib/links/proof.ts). Absent, or with no secret, no proof is offered. */
export type Proof = {
  /** Signs challenges and passes (LINKS_PASS_SECRET). */
  secret: Uint8Array | null;
  /** Refuse to make a link without a pass (LINKS_REQUIRE_PROOF=1). */
  require: boolean;
  /** The App Attest root certificate (PEM): Apple's, or a test's own. */
  appleRoot: string;
  /** Accept App Attest's development environment (APP_ATTEST_ALLOW_DEVELOPMENT=1). */
  allowDevelopment: boolean;
  /** Play Integrity, when it is set up: the Cloud project number the app asks with, and Google's decoder. */
  play: { project: string; decode: (token: string, now: number) => Promise<unknown | null> } | null;
};

export type Deps = {
  store: Store | null;
  limiter: Limiter;
  now: () => number;
  random?: (n: number) => Uint8Array;
  proof?: Proof;
  /** Sends the owner a warning. Absent, none is sent. */
  alert?: Alert;
  /** Runs bookkeeping after the answer has gone (Next's after()). Errors are swallowed. */
  defer?: (task: () => Promise<unknown>) => void;
};

const b64url = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const hashOf = (token: string) => createHash("sha256").update(Buffer.from(token, "base64url")).digest("base64url");
const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const refuse = (status: number, error: string, headers?: Record<string, string>): Answer => ({ status, headers, json: { error } });
const slow = (seconds: number) => refuse(429, "slow_down", { "Retry-After": String(seconds) });
const unavailable = () => refuse(503, "unavailable", { "Retry-After": "3600" });
const dayOf = (ms: number) => new Date(ms).toISOString().slice(0, 10);

/** Run `task` after answering, never letting it fail or slow the answer. */
function later(deps: Deps, task: () => Promise<unknown>) {
  const safe = () => task().catch(() => {});
  if (deps.defer) deps.defer(safe);
  else void safe();
}

/** Warn the owner, once a threshold a day, when this request carried the day's use across it. */
async function warnIfCrossed(deps: Deps, day: string, spent: { links: number; bytes: number }, added: { links: number; bytes: number }) {
  if (!deps.store) return;
  for (const [what, total, step, allowance] of [
    ["links", spent.links, added.links, LIMITS.dayLinks],
    ["bytes", spent.bytes, added.bytes, LIMITS.dayBytes],
  ] as const) {
    for (const percent of LIMITS.warnAt) {
      const line = (allowance * percent) / 100;
      if (!(total - step < line && total >= line)) continue;
      // the count makes it once a day even if two servers see the crossing
      if ((await deps.store.count(day, `warned:${what}:${percent}`)) !== 1 || !deps.alert) continue;
      await deps.alert(
        `Upon Thy Head: ${percent}% of today's link ${what} used`,
        [
          `Today (${day}, UTC) the link service has passed ${percent}% of its daily allowance of ${what}.`,
          ``,
          `Links: ${spent.links} of ${LIMITS.dayLinks}`,
          `Bytes: ${spent.bytes} of ${LIMITS.dayBytes}`,
          ``,
          `At 100% no more links can be made until midnight UTC. GET /api/status for the day's counts.`,
        ].join("\n"),
      );
    }
  }
}

/** POST /api/b */
export async function create(deps: Deps, input: { contentType: string | null; body: Uint8Array | "too_big"; client: string; pass?: string | null }): Promise<Answer> {
  const now = deps.now();
  if ((input.contentType ?? "").split(";")[0].trim().toLowerCase() !== "application/octet-stream") return refuse(415, "type");
  if (input.body === "too_big" || input.body.length > LIMITS.maxBytes) return refuse(413, "too_big");
  if (input.body.length < LIMITS.minBytes) return refuse(400, "too_small");
  if (input.body[0] !== LIMITS.version) return refuse(400, "version");
  const wait =
    deps.limiter.takeWithCeiling("create", input.client, LIMITS.create, LIMITS.createAll, now) ||
    deps.limiter.take("create-day", input.client, LIMITS.createDay, now) ||
    deps.limiter.take("create-bytes-day", input.client, LIMITS.createBytesDay, now, input.body.length);
  if (wait) return slow(wait);
  if (!deps.store) return unavailable();
  const store = deps.store;
  const day = dayOf(now);

  // Proof of the app: a pass the server signed, or (unless proof is required) none.
  let pass: string | null = null;
  if (input.pass) {
    pass = deps.proof?.secret ? passId(deps.proof.secret, input.pass, now) : null;
    if (!pass) {
      later(deps, () => store.count(day, "pass:refused"));
      return refuse(401, "pass");
    }
    const passWait = deps.limiter.take("create-pass", pass, LIMITS.create, now) || deps.limiter.take("create-pass-day", pass, LIMITS.createDay, now);
    if (passWait) return slow(passWait);
  } else if (deps.proof?.require) {
    later(deps, () => store.count(day, "links:refused_no_proof"));
    return refuse(403, "proof");
  }

  const spent = await store.spend(day, 1, input.body.length);
  later(deps, () => warnIfCrossed(deps, day, spent, { links: 1, bytes: input.body.length }));
  if (spent.links > LIMITS.dayLinks || spent.bytes > LIMITS.dayBytes) {
    const midnight = Date.UTC(+day.slice(0, 4), +day.slice(5, 7) - 1, +day.slice(8, 10) + 1);
    return refuse(503, "full", { "Retry-After": String(Math.ceil((midnight - now) / 1000)) });
  }

  const random = deps.random ?? ((n: number) => new Uint8Array(randomBytes(n)));
  const stop = b64url(random(32));
  const expires = Math.floor((now + LIMITS.lifeMs) / 1000) * 1000;
  for (let attempt = 0; attempt < 3; attempt++) {
    const id = b64url(random(16));
    if (await store.put(id, { bytes: input.body, expires, stopHash: hashOf(stop) })) {
      later(deps, () => store.count(day, pass ? "links:proven" : "links:unproven"));
      return { status: 201, json: { id, expires: iso(expires), stop } };
    }
  }
  return unavailable();
}

/** GET /api/b/<id> */
export async function read(deps: Deps, input: { id: string; client: string }): Promise<Answer> {
  const now = deps.now();
  if (!ID.test(input.id)) return refuse(404, "not_found");
  const wait = deps.limiter.takeWithCeiling("read", input.client, LIMITS.read, LIMITS.readAll, now);
  if (wait) return slow(wait);
  if (!deps.store) return unavailable();
  const copy = await deps.store.get(input.id);
  if (!copy) return refuse(410, "gone");
  if (copy.expires <= now) {
    await deps.store.remove(input.id);
    return refuse(410, "gone");
  }
  return { status: 200, bytes: copy.bytes, headers: { "Content-Type": "application/octet-stream", "Blessing-Expires": iso(copy.expires) } };
}

/** DELETE /api/b/<id>, with "Authorization: Bearer <stop token>" */
export async function stop(deps: Deps, input: { id: string; authorization: string | null; client: string }): Promise<Answer> {
  const now = deps.now();
  if (!ID.test(input.id)) return refuse(404, "not_found");
  // The token's shape is checked before anything is counted, so a request with no usable token
  // costs nothing. Stopping has no ceiling for everyone together: it can only erase a copy, it
  // needs that copy's own 256-bit token, and a sender must always be able to stop their link.
  const token = /^Bearer ([^\s]+)$/.exec(input.authorization ?? "")?.[1];
  if (!token || !TOKEN.test(token)) return refuse(401, "no_token", { "WWW-Authenticate": "Bearer" });
  const wait = deps.limiter.take("stop", input.client, LIMITS.stop, now);
  if (wait) return slow(wait);
  if (!deps.store) return unavailable();
  const copy = await deps.store.get(input.id);
  if (!copy || copy.expires <= now) {
    if (copy) await deps.store.remove(input.id);
    return refuse(410, "gone");
  }
  const a = Buffer.from(hashOf(token)), b = Buffer.from(copy.stopHash);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return refuse(403, "wrong_token");
  await deps.store.remove(input.id);
  return { status: 204 };
}

/**
 * POST /api/proof/challenge: a challenge to prove against. With Play Integrity set up, also the
 * Cloud project number the app asks Google with; without it the Android app sends no proof.
 */
export async function challenge(deps: Deps, input: { client: string }): Promise<Answer> {
  const now = deps.now();
  const wait = deps.limiter.takeWithCeiling("challenge", input.client, LIMITS.challenge, LIMITS.proofAll, now);
  if (wait) return slow(wait);
  if (!deps.proof?.secret) return unavailable();
  const c = makeChallenge(deps.proof.secret, now, deps.random);
  return { status: 200, json: { challenge: c.challenge, expires: iso(c.expires), ...(deps.proof.play ? { android: { project: deps.proof.play.project } } : {}) } };
}

/**
 * POST /api/proof, JSON: {"platform":"ios","challenge","keyId","attestation"} (attestation in
 * base64) or {"platform":"android","challenge","token"}. A proof that verifies gets a pass.
 */
export async function prove(deps: Deps, input: { contentType: string | null; body: Uint8Array | "too_big"; client: string }): Promise<Answer> {
  const now = deps.now();
  if ((input.contentType ?? "").split(";")[0].trim().toLowerCase() !== "application/json") return refuse(415, "type");
  if (input.body === "too_big" || input.body.length > PROOF.maxBody) return refuse(413, "too_big");
  const wait = deps.limiter.takeWithCeiling("prove", input.client, LIMITS.prove, LIMITS.proofAll, now);
  if (wait) return slow(wait);
  const proof = deps.proof;
  if (!proof?.secret || !deps.store) return unavailable();
  const store = deps.store, day = dayOf(now);

  let j: Record<string, unknown>;
  try {
    j = JSON.parse(Buffer.from(input.body).toString("utf8"));
    if (!j || typeof j !== "object") throw new Error();
  } catch {
    return refuse(400, "format");
  }
  const platform = j.platform === "ios" || j.platform === "android" ? j.platform : null;
  if (!platform || typeof j.challenge !== "string") return refuse(400, "format");
  const failed = (reason: string) => {
    later(deps, async () => {
      await store.count(day, `proof:${platform}:failed`);
      await store.count(day, `proof:${platform}:failed:${reason}`);
    });
    return refuse(400, "proof");
  };
  if (!challengeIsGood(proof.secret, j.challenge, now)) return failed("challenge");

  let verdict;
  if (platform === "ios") {
    if (typeof j.keyId !== "string" || typeof j.attestation !== "string" || j.keyId.length > 100) return refuse(400, "format");
    verdict = verifyAppAttest({
      attestation: new Uint8Array(Buffer.from(j.attestation, "base64")),
      keyId: j.keyId,
      challenge: j.challenge,
      now,
      root: proof.appleRoot,
      allowDevelopment: proof.allowDevelopment,
    });
  } else {
    if (typeof j.token !== "string" || j.token.length > 16384) return refuse(400, "format");
    if (!proof.play) {
      later(deps, () => store.count(day, "proof:android:not_set_up"));
      return refuse(503, "not_set_up");
    }
    let payload: unknown = null;
    try {
      payload = await proof.play.decode(j.token, now);
    } catch {
      return unavailable();
    }
    verdict = payload ? verifyIntegrityVerdict(payload, j.challenge, now) : ({ ok: false, reason: "decode" } as const);
  }
  if (!verdict.ok) return failed(verdict.reason);
  later(deps, () => store.count(day, `proof:${platform}:ok`));
  const p = makePass(proof.secret, passIdFor(proof.secret, verdict.what), now);
  return { status: 200, json: { pass: p.pass, expires: iso(p.expires) } };
}

/** GET /api/status, for the owner: today's and yesterday's totals and counts. Nothing about who. */
export async function status(deps: Deps): Promise<Answer> {
  if (!deps.store) return unavailable();
  const now = deps.now();
  const one = async (day: string) => {
    const [spent, counts] = await Promise.all([deps.store!.spend(day, 0, 0), deps.store!.counts(day)]);
    return {
      day,
      links: spent.links,
      bytes: spent.bytes,
      allowance: { links: LIMITS.dayLinks, bytes: LIMITS.dayBytes },
      used: { links: Math.round((spent.links / LIMITS.dayLinks) * 1000) / 10, bytes: Math.round((spent.bytes / LIMITS.dayBytes) * 1000) / 10 },
      counts,
    };
  };
  return {
    status: 200,
    json: {
      today: await one(dayOf(now)),
      yesterday: await one(dayOf(now - 86400000)),
      proof: { offered: !!deps.proof?.secret, required: !!deps.proof?.require, android: !!deps.proof?.play, development: !!deps.proof?.allowDevelopment },
      warnings: !!deps.alert,
    },
  };
}

/** The scheduled clean-up: erase every copy past its time. */
export async function sweep(deps: Deps): Promise<Answer> {
  if (!deps.store) return unavailable();
  return { status: 200, json: { erased: await deps.store.sweep(deps.now()) } };
}
