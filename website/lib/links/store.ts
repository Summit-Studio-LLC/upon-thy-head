// Where locked copies are kept. One small interface, four places behind it:
//   MemoryStore    for tests
//   FileStore      a folder on this machine, for running locally with no account
//   PostgresStore  Neon Postgres, for Vercel (see README). This is the one the live site uses.
//   UpstashStore   Upstash Redis over its REST interface (kept; not used by the live site)
//
// A copy is exactly three things: the locked bytes, when it expires, and a hash of the stop token.
// Nothing about who made it is ever kept.

import { randomBytes } from "node:crypto";
import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { neon } from "@neondatabase/serverless";

export type Copy = {
  /** The locked bytes, exactly as the phone sent them. */
  bytes: Uint8Array;
  /** When it stops, in milliseconds since 1970 (UTC). */
  expires: number;
  /** SHA-256 of the stop token, base64url. */
  stopHash: string;
};

export type Spent = { links: number; bytes: number };

export interface Store {
  /** Keep a copy under a new id. False if the id is already taken. */
  put(id: string, copy: Copy): Promise<boolean>;
  /** The copy as kept, expired or not; null if there is none. */
  get(id: string): Promise<Copy | null>;
  /** Erase a copy. */
  remove(id: string): Promise<void>;
  /** Erase every copy that expired before `now`. Returns how many. */
  sweep(now: number): Promise<number>;
  /** Read a day's totals without changing anything. */
  spent(day: string): Promise<Spent>;
  /** Add to a day's totals (day is "2026-11-16", UTC) and return them. Totals carry no identity. */
  spend(day: string, links: number, bytes: number): Promise<Spent>;
  /** Add to a day's totals only if both stay within `maxLinks` and `maxBytes`. */
  trySpend(day: string, links: number, bytes: number, maxLinks: number, maxBytes: number): Promise<{ ok: boolean; spent: Spent }>;
  /**
   * Add `by` to one of a day's named counts ("links:proven", "proof:ios:ok", …) and return it.
   * Like the totals, a count says how many, never who. Dropped with the day's totals.
   */
  count(day: string, what: string, by?: number): Promise<number>;
  /** Every named count of a day. */
  counts(day: string): Promise<Record<string, number>>;
}

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64");
const unb64 = (text: string) => new Uint8Array(Buffer.from(text, "base64"));

type Kept = { c: string; e: number; s: string };
const pack = (copy: Copy): string => JSON.stringify({ c: b64(copy.bytes), e: copy.expires, s: copy.stopHash } satisfies Kept);
function unpack(text: string): Copy | null {
  try {
    const k = JSON.parse(text) as Kept;
    if (typeof k.c !== "string" || typeof k.e !== "number" || typeof k.s !== "string") return null;
    return { bytes: unb64(k.c), expires: k.e, stopHash: k.s };
  } catch {
    return null;
  }
}

export class MemoryStore implements Store {
  private copies = new Map<string, string>();
  private days = new Map<string, Spent>();

  async put(id: string, copy: Copy) {
    if (this.copies.has(id)) return false;
    this.copies.set(id, pack(copy));
    return true;
  }
  async get(id: string) {
    const kept = this.copies.get(id);
    return kept ? unpack(kept) : null;
  }
  async remove(id: string) {
    this.copies.delete(id);
  }
  async sweep(now: number) {
    let n = 0;
    for (const [id, kept] of this.copies) {
      const copy = unpack(kept);
      if (!copy || copy.expires <= now) {
        this.copies.delete(id);
        n++;
      }
    }
    return n;
  }
  async spent(day: string) {
    const s = this.days.get(day);
    return s ? { links: s.links, bytes: s.bytes } : { links: 0, bytes: 0 };
  }
  async spend(day: string, links: number, bytes: number) {
    const was = this.days.get(day) ?? { links: 0, bytes: 0 };
    const now = { links: Math.max(0, was.links + links), bytes: Math.max(0, was.bytes + bytes) };
    this.days.set(day, now);
    return { ...now };
  }
  async trySpend(day: string, links: number, bytes: number, maxLinks: number, maxBytes: number) {
    const was = this.days.get(day) ?? { links: 0, bytes: 0 };
    if (was.links + links > maxLinks || was.bytes + bytes > maxBytes) return { ok: false, spent: { ...was } };
    const now = { links: was.links + links, bytes: was.bytes + bytes };
    this.days.set(day, now);
    return { ok: true, spent: { ...now } };
  }
  private tallies = new Map<string, Record<string, number>>();
  async count(day: string, what: string, by = 1) {
    const t = this.tallies.get(day) ?? {};
    t[what] = (t[what] ?? 0) + by;
    this.tallies.set(day, t);
    return t[what];
  }
  async counts(day: string) {
    return { ...this.tallies.get(day) };
  }
  /** For tests: how many copies are held. */
  get size() {
    return this.copies.size;
  }
}

/** A folder: one file per copy, one per day's totals. For this machine only. */
export class FileStore implements Store {
  private dir: string;
  private queue: Promise<unknown> = Promise.resolve();
  constructor(dir: string) {
    this.dir = dir;
  }

  private file = (id: string) => path.join(this.dir, `${id}.copy`);
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.queue.then(fn, fn);
    this.queue = next.then(() => {}, () => {});
    return next;
  }
  private async writeAtomic(file: string, text: string) {
    await mkdir(this.dir, { recursive: true });
    const tmp = `${file}.${randomBytes(6).toString("hex")}.tmp`;
    await writeFile(tmp, text);
    await rename(tmp, file);
  }

  async put(id: string, copy: Copy) {
    await mkdir(this.dir, { recursive: true });
    try {
      await writeFile(this.file(id), pack(copy), { flag: "wx" });
      return true;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EEXIST") return false;
      throw error;
    }
  }
  async get(id: string) {
    try {
      return unpack(await readFile(this.file(id), "utf8"));
    } catch {
      return null;
    }
  }
  async remove(id: string) {
    await rm(this.file(id), { force: true });
  }
  async sweep(now: number) {
    let n = 0;
    for (const name of await readdir(this.dir).catch(() => [] as string[])) {
      if (name.endsWith(".day") && name.slice(0, 10) < new Date(now - 2 * 86400000).toISOString().slice(0, 10)) await rm(path.join(this.dir, name), { force: true });
      if (!name.endsWith(".copy")) continue;
      const copy = await this.get(name.slice(0, -5));
      if (!copy || copy.expires <= now) {
        await rm(path.join(this.dir, name), { force: true });
        n++;
      }
    }
    return n;
  }
  async spent(day: string): Promise<Spent> {
    try {
      const s = JSON.parse(await readFile(path.join(this.dir, `${day}.day`), "utf8")) as Spent;
      return { links: Number(s.links) || 0, bytes: Number(s.bytes) || 0 };
    } catch {
      return { links: 0, bytes: 0 };
    }
  }
  spend(day: string, links: number, bytes: number) {
    return this.serial(async () => {
      const was = await this.spent(day);
      const now = { links: Math.max(0, was.links + links), bytes: Math.max(0, was.bytes + bytes) };
      await this.writeAtomic(path.join(this.dir, `${day}.day`), JSON.stringify(now));
      return now;
    });
  }
  trySpend(day: string, links: number, bytes: number, maxLinks: number, maxBytes: number) {
    return this.serial(async () => {
      const was = await this.spent(day);
      if (was.links + links > maxLinks || was.bytes + bytes > maxBytes) return { ok: false, spent: was };
      const now = { links: was.links + links, bytes: was.bytes + bytes };
      await this.writeAtomic(path.join(this.dir, `${day}.day`), JSON.stringify(now));
      return { ok: true, spent: now };
    });
  }
  count(day: string, what: string, by = 1) {
    return this.serial(async () => {
      const t = await this.counts(day);
      t[what] = (t[what] ?? 0) + by;
      await this.writeAtomic(path.join(this.dir, `${day}.counts.day`), JSON.stringify(t));
      return t[what];
    });
  }
  async counts(day: string) {
    try {
      return JSON.parse(await readFile(path.join(this.dir, `${day}.counts.day`), "utf8")) as Record<string, number>;
    } catch {
      return {};
    }
  }
  /** Wait for queued writes to finish (for tests cleaning up a temp folder). */
  flush(): Promise<void> {
    return this.queue.then(() => {});
  }
}

const UPSTASH_TRY_SPEND = `
local l = tonumber(redis.call('HGET', KEYS[1], 'links') or '0')
local b = tonumber(redis.call('HGET', KEYS[1], 'bytes') or '0')
local dl = tonumber(ARGV[1])
local db = tonumber(ARGV[2])
if l + dl > tonumber(ARGV[3]) or b + db > tonumber(ARGV[4]) then
  return {0, l, b}
end
l = redis.call('HINCRBY', KEYS[1], 'links', dl)
b = redis.call('HINCRBY', KEYS[1], 'bytes', db)
redis.call('EXPIRE', KEYS[1], tonumber(ARGV[5]))
return {1, l, b}`;

/**
 * Upstash Redis, spoken to over its REST interface with plain fetch (no client library).
 * Each copy is one key, "b:<id>", set with the moment it expires, so Redis erases it by itself
 * even if this site's own clean-up never runs.
 */
export class UpstashStore implements Store {
  private url: string;
  private token: string;
  private fetcher: typeof fetch;
  constructor(url: string, token: string, fetcher: typeof fetch = fetch) {
    this.url = url;
    this.token = token;
    this.fetcher = fetcher;
  }

  private async run<T>(...command: (string | number)[]): Promise<T> {
    const response = await this.fetcher(this.url, {
      method: "POST",
      headers: { authorization: `Bearer ${this.token}`, "content-type": "application/json" },
      body: JSON.stringify(command),
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
    const answer = (await response.json()) as { result?: T; error?: string };
    if (!response.ok || answer.error) throw new Error("storage refused a command");
    return answer.result as T;
  }

  async put(id: string, copy: Copy) {
    return (await this.run<string | null>("SET", `b:${id}`, pack(copy), "NX", "PXAT", copy.expires)) === "OK";
  }
  async get(id: string) {
    const kept = await this.run<string | null>("GET", `b:${id}`);
    return kept ? unpack(kept) : null;
  }
  async remove(id: string) {
    await this.run("DEL", `b:${id}`);
  }
  async sweep(now: number) {
    // Redis has already erased what expired. This checks for keys missing a TTL or past their time.
    let cursor = "0";
    let n = 0;
    do {
      const [next, keys] = await this.run<[string, string[]]>("SCAN", cursor, "MATCH", "b:*", "COUNT", 200);
      cursor = String(next);
      for (const key of keys) {
        const ttl = await this.run<number>("PTTL", key);
        if (ttl > 0 || ttl === -2) continue;
        const kept = await this.run<string | null>("GET", key);
        const copy = kept ? unpack(kept) : null;
        if (kept && (!copy || copy.expires <= now)) {
          await this.run("DEL", key);
          n++;
        }
      }
    } while (cursor !== "0");
    return n;
  }
  async spent(day: string): Promise<Spent> {
    const [links, bytes] = (await this.run<(string | number | null)[] | null>("HMGET", `day:${day}`, "links", "bytes")) ?? [];
    return { links: Number(links ?? 0), bytes: Number(bytes ?? 0) };
  }
  async spend(day: string, links: number, bytes: number) {
    const key = `day:${day}`;
    const total = { links: await this.run<number>("HINCRBY", key, "links", links), bytes: await this.run<number>("HINCRBY", key, "bytes", bytes) };
    await this.run("EXPIRE", key, 3 * 86400);
    return total;
  }
  async trySpend(day: string, links: number, bytes: number, maxLinks: number, maxBytes: number) {
    const [ok, totalLinks, totalBytes] = await this.run<[number, number, number]>(
      "EVAL",
      UPSTASH_TRY_SPEND,
      1,
      `day:${day}`,
      links,
      bytes,
      maxLinks,
      maxBytes,
      3 * 86400,
    );
    return { ok: ok === 1, spent: { links: Number(totalLinks), bytes: Number(totalBytes) } };
  }
  async count(day: string, what: string, by = 1) {
    const n = await this.run<number>("HINCRBY", `count:${day}`, what, by);
    await this.run("EXPIRE", `count:${day}`, 3 * 86400);
    return n;
  }
  async counts(day: string) {
    const flat = (await this.run<string[] | null>("HGETALL", `count:${day}`)) ?? [];
    const out: Record<string, number> = {};
    for (let i = 0; i + 1 < flat.length; i += 2) out[flat[i]] = Number(flat[i + 1]);
    return out;
  }
}

/** One SQL statement with its values; the rows that come back. */
export type Query = (text: string, values: unknown[]) => Promise<Record<string, unknown>[]>;

/**
 * Neon Postgres. Three small tables, made on first use: the locked copies, each day's totals, and
 * each day's named counts (added 2026-11-18 with CREATE TABLE IF NOT EXISTS, so a live database
 * gains it on the first request and nothing already there changes).
 * Postgres does not erase a row when its time comes, so an expired copy stays until the daily
 * sweep; the service never hands out an expired copy (it checks `expires` itself).
 */
export class PostgresStore implements Store {
  private query: Query;
  private copies: string;
  private days: string;
  private tallies: string;
  private ready: Promise<unknown> | null = null;

  /** `prefix` names the tables (letters and underscores only), so a test can use its own. */
  constructor(query: Query, prefix = "link") {
    if (!/^[a-z_]+$/.test(prefix)) throw new Error("a table prefix is letters and underscores");
    this.query = query;
    this.copies = `${prefix}_copies`;
    this.days = `${prefix}_days`;
    this.tallies = `${prefix}_counts`;
  }

  static at(url: string, prefix = "link") {
    const sql = neon(url);
    return new PostgresStore((text, values) => sql.query(text, values) as Promise<Record<string, unknown>[]>, prefix);
  }

  private tables() {
    this.ready ??= (async () => {
      for (const ddl of [
        `CREATE TABLE IF NOT EXISTS ${this.copies} (id text PRIMARY KEY, bytes bytea NOT NULL, expires bigint NOT NULL, stop_hash text NOT NULL)`,
        `CREATE INDEX IF NOT EXISTS ${this.copies}_expires ON ${this.copies} (expires)`,
        `CREATE TABLE IF NOT EXISTS ${this.days} (day text PRIMARY KEY, links bigint NOT NULL DEFAULT 0, bytes bigint NOT NULL DEFAULT 0)`,
        `CREATE TABLE IF NOT EXISTS ${this.tallies} (day text NOT NULL, what text NOT NULL, n bigint NOT NULL DEFAULT 0, PRIMARY KEY (day, what))`,
      ]) {
        try {
          await this.query(ddl, []);
        } catch (error) {
          if ((error as { code?: string })?.code !== "23505") throw error;
        }
      }
    })().catch((error) => {
      this.ready = null; // try again on the next request
      throw error;
    });
    return this.ready;
  }

  async put(id: string, copy: Copy) {
    await this.tables();
    const rows = await this.query(
      `INSERT INTO ${this.copies} (id, bytes, expires, stop_hash) VALUES ($1, decode($2, 'base64'), $3, $4) ON CONFLICT (id) DO NOTHING RETURNING id`,
      [id, b64(copy.bytes), copy.expires, copy.stopHash],
    );
    return rows.length === 1;
  }
  async get(id: string) {
    await this.tables();
    const rows = await this.query(`SELECT encode(bytes, 'base64') AS c, expires AS e, stop_hash AS s FROM ${this.copies} WHERE id = $1`, [id]);
    const row = rows[0];
    if (!row || typeof row.c !== "string" || typeof row.s !== "string") return null;
    const expires = Number(row.e);
    if (!Number.isFinite(expires)) return null;
    return { bytes: unb64(row.c.replace(/\s/g, "")), expires, stopHash: row.s };
  }
  async remove(id: string) {
    await this.tables();
    await this.query(`DELETE FROM ${this.copies} WHERE id = $1`, [id]);
  }
  async sweep(now: number) {
    await this.tables();
    const rows = await this.query(`WITH gone AS (DELETE FROM ${this.copies} WHERE expires <= $1 RETURNING 1) SELECT count(*)::int AS n FROM gone`, [now]);
    // a day's totals are only needed for that day; keep three, as the other stores do
    const old = new Date(now - 3 * 86400 * 1000).toISOString().slice(0, 10);
    await this.query(`DELETE FROM ${this.days} WHERE day < $1`, [old]);
    await this.query(`DELETE FROM ${this.tallies} WHERE day < $1`, [old]);
    return Number(rows[0]?.n ?? 0);
  }
  async spent(day: string): Promise<Spent> {
    await this.tables();
    const rows = await this.query(`SELECT links, bytes FROM ${this.days} WHERE day = $1`, [day]);
    return { links: Number(rows[0]?.links ?? 0), bytes: Number(rows[0]?.bytes ?? 0) };
  }
  async spend(day: string, links: number, bytes: number) {
    await this.tables();
    const rows = await this.query(
      `INSERT INTO ${this.days} (day, links, bytes) VALUES ($1, GREATEST(0, $2::bigint), GREATEST(0, $3::bigint)) ON CONFLICT (day) DO UPDATE SET links = GREATEST(0, ${this.days}.links + $2::bigint), bytes = GREATEST(0, ${this.days}.bytes + $3::bigint) RETURNING links, bytes`,
      [day, links, bytes],
    );
    return { links: Number(rows[0]?.links ?? 0), bytes: Number(rows[0]?.bytes ?? 0) };
  }
  async trySpend(day: string, links: number, bytes: number, maxLinks: number, maxBytes: number) {
    await this.tables();
    const rows = await this.query(
      `INSERT INTO ${this.days} (day, links, bytes) SELECT $1, $2::bigint, $3::bigint WHERE $2::bigint <= $4::bigint AND $3::bigint <= $5::bigint ON CONFLICT (day) DO UPDATE SET links = ${this.days}.links + EXCLUDED.links, bytes = ${this.days}.bytes + EXCLUDED.bytes WHERE ${this.days}.links + EXCLUDED.links <= $4::bigint AND ${this.days}.bytes + EXCLUDED.bytes <= $5::bigint RETURNING links, bytes`,
      [day, links, bytes, maxLinks, maxBytes],
    );
    if (rows.length === 1) return { ok: true, spent: { links: Number(rows[0].links), bytes: Number(rows[0].bytes) } };
    return { ok: false, spent: await this.spent(day) };
  }
  async count(day: string, what: string, by = 1) {
    await this.tables();
    const rows = await this.query(
      `INSERT INTO ${this.tallies} (day, what, n) VALUES ($1, $2, $3) ON CONFLICT (day, what) DO UPDATE SET n = ${this.tallies}.n + EXCLUDED.n RETURNING n`,
      [day, what, by],
    );
    return Number(rows[0]?.n ?? 0);
  }
  async counts(day: string) {
    await this.tables();
    const out: Record<string, number> = {};
    for (const row of await this.query(`SELECT what, n FROM ${this.tallies} WHERE day = $1`, [day])) out[String(row.what)] = Number(row.n);
    return out;
  }
}

let chosen: Store | null | undefined;

/**
 * The store this server uses, or null when none is set up (the service then answers "unavailable"
 * rather than pretend).
 *   DATABASE_URL (set by Vercel's Neon integration): Neon Postgres
 *   UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN (or the KV_REST_API_* names Vercel sets): Upstash
 *   LINKS_LOCAL_DIR: a folder on this machine
 *   neither, outside production: the folder .data/links
 */
export function theStore(): Store | null {
  if (chosen !== undefined) return chosen;
  const url = process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN ?? process.env.KV_REST_API_TOKEN;
  if (process.env.DATABASE_URL) chosen = PostgresStore.at(process.env.DATABASE_URL);
  else if (url && token) chosen = new UpstashStore(url, token);
  else if (process.env.LINKS_LOCAL_DIR) chosen = new FileStore(path.resolve(process.env.LINKS_LOCAL_DIR));
  else if (process.env.NODE_ENV !== "production") chosen = new FileStore(path.resolve(".data/links"));
  else chosen = null;
  return chosen;
}
