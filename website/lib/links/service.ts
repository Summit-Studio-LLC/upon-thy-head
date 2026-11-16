// The service behind shared links: create, read, stop, sweep. PROTOCOL.md is the contract.
//
// It never sees a key, a title or a word: only locked bytes. It keeps no address, no device
// detail and no log line of its own. The route handlers in app/api are thin wrappers round this.

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { Store } from "./store.ts";

export const LIMITS = {
  version: 1,
  /** The largest locked copy kept. See PROTOCOL.md for why 64 KiB. */
  maxBytes: 65536,
  /** Version byte, nonce, tag, and the two bytes of "{}". */
  minBytes: 1 + 12 + 16 + 2,
  lifeMs: 30 * 24 * 60 * 60 * 1000,
  /** Everyone together, per UTC day. Sized so 30 days of full days fit a free 256 MB store. */
  dayLinks: Number(process.env.LINKS_DAY_LINKS ?? 1000),
  dayBytes: Number(process.env.LINKS_DAY_BYTES ?? 6 * 1024 * 1024),
  /** One client (see clientOf in app/api/b/http.ts): [how many, in how many milliseconds]. */
  create: [10, 10 * 60 * 1000] as const,
  createDay: [40, 24 * 60 * 60 * 1000] as const,
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
  take(what: string, client: string, [max, windowMs]: readonly [number, number], now: number): number {
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
    if (w.count >= max) return Math.max(1, Math.ceil((w.ends - now) / 1000));
    w.count++;
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

export type Deps = { store: Store | null; limiter: Limiter; now: () => number; random?: (n: number) => Uint8Array };

const b64url = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const hashOf = (token: string) => createHash("sha256").update(Buffer.from(token, "base64url")).digest("base64url");
const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const refuse = (status: number, error: string, headers?: Record<string, string>): Answer => ({ status, headers, json: { error } });
const slow = (seconds: number) => refuse(429, "slow_down", { "Retry-After": String(seconds) });
const unavailable = () => refuse(503, "unavailable", { "Retry-After": "3600" });

/** POST /api/b */
export async function create(deps: Deps, input: { contentType: string | null; body: Uint8Array | "too_big"; client: string }): Promise<Answer> {
  const now = deps.now();
  if ((input.contentType ?? "").split(";")[0].trim().toLowerCase() !== "application/octet-stream") return refuse(415, "type");
  if (input.body === "too_big" || input.body.length > LIMITS.maxBytes) return refuse(413, "too_big");
  if (input.body.length < LIMITS.minBytes) return refuse(400, "too_small");
  if (input.body[0] !== LIMITS.version) return refuse(400, "version");
  const wait =
    deps.limiter.takeWithCeiling("create", input.client, LIMITS.create, LIMITS.createAll, now) ||
    deps.limiter.take("create-day", input.client, LIMITS.createDay, now);
  if (wait) return slow(wait);
  if (!deps.store) return unavailable();

  const day = new Date(now).toISOString().slice(0, 10);
  const spent = await deps.store.spend(day, 1, input.body.length);
  if (spent.links > LIMITS.dayLinks || spent.bytes > LIMITS.dayBytes) {
    const midnight = Date.UTC(+day.slice(0, 4), +day.slice(5, 7) - 1, +day.slice(8, 10) + 1);
    return refuse(503, "full", { "Retry-After": String(Math.ceil((midnight - now) / 1000)) });
  }

  const random = deps.random ?? ((n: number) => new Uint8Array(randomBytes(n)));
  const stop = b64url(random(32));
  const expires = Math.floor((now + LIMITS.lifeMs) / 1000) * 1000;
  for (let attempt = 0; attempt < 3; attempt++) {
    const id = b64url(random(16));
    if (await deps.store.put(id, { bytes: input.body, expires, stopHash: hashOf(stop) })) {
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

/** The scheduled clean-up: erase every copy past its time. */
export async function sweep(deps: Deps): Promise<Answer> {
  if (!deps.store) return unavailable();
  return { status: 200, json: { erased: await deps.store.sweep(deps.now()) } };
}
