// The service: create, read, stop, expiry (with a clock the test controls), limits, and each store.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { type Answer, type Deps, LIMITS, Limiter, create, positiveInt, read, status, stop, sweep } from "../lib/links/service.ts";
import { neon } from "@neondatabase/serverless";
import { bearerMatches, bodyOf } from "../app/api/b/http.ts";
import { FileStore, MemoryStore, PostgresStore, type Store, UpstashStore } from "../lib/links/store.ts";

const DAY = 86400000;
const START = Date.UTC(2026, 10, 16, 18, 3, 22, 500);
const locked = (n = 400, first = 1) => Uint8Array.from({ length: n }, (_, i) => (i === 0 ? first : (i * 31) & 255));
const OCTETS = "application/octet-stream";

function world(store: Store | null = new MemoryStore()) {
  const clock = { now: START };
  const deps: Deps = { store, limiter: new Limiter(), now: () => clock.now };
  const make = (body: Uint8Array | "too_big" = locked(), client = "a", contentType: string | null = OCTETS) => create(deps, { contentType, body, client });
  return { clock, deps, make };
}
const made = (a: Answer) => a.json as { id: string; expires: string; stop: string };
const error = (a: Answer) => (a.json as { error?: string } | undefined)?.error;

test("create gives an id, an expiry 30 days on, and a stop token; read returns the same bytes", async () => {
  const { deps, make } = world();
  const answer = await make();
  assert.equal(answer.status, 201);
  const { id, expires, stop: token } = made(answer);
  assert.match(id, /^[A-Za-z0-9_-]{22}$/);
  assert.match(token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(expires, "2026-12-16T18:03:22Z");
  const got = await read(deps, { id, client: "b" });
  assert.equal(got.status, 200);
  assert.deepEqual(got.bytes, locked());
  assert.equal(got.headers?.["Blessing-Expires"], expires);
  assert.equal(got.headers?.["Content-Type"], OCTETS);
});

test("only the locked bytes, the expiry and a hash of the stop token are kept", async () => {
  const store = new MemoryStore();
  const { make } = world(store);
  const { id, stop: token } = made(await make());
  const kept = await store.get(id);
  assert.deepEqual(Object.keys(kept!).sort(), ["bytes", "expires", "stopHash"]);
  assert.equal(kept!.stopHash, createHash("sha256").update(Buffer.from(token, "base64url")).digest("base64url"));
  assert.ok(!JSON.stringify(kept).includes(token), "the stop token itself is not kept");
});

test("stop needs the right token, erases at once, and the link is then gone", async () => {
  const store = new MemoryStore();
  const { deps, make } = world(store);
  const { id, stop: token } = made(await make());
  assert.equal(error(await stop(deps, { id, authorization: null, client: "a" })), "no_token");
  assert.equal(error(await stop(deps, { id, authorization: "Bearer nonsense", client: "a" })), "no_token");
  const other = made(await make()).stop;
  const wrong = await stop(deps, { id, authorization: `Bearer ${other}`, client: "a" });
  assert.deepEqual([wrong.status, error(wrong)], [403, "wrong_token"]);
  assert.equal((await read(deps, { id, client: "a" })).status, 200, "a wrong token stops nothing");
  assert.equal((await stop(deps, { id, authorization: `Bearer ${token}`, client: "a" })).status, 204);
  assert.equal(await store.get(id), null, "erased from the store");
  const after = await read(deps, { id, client: "a" });
  assert.deepEqual([after.status, error(after)], [410, "gone"]);
  assert.equal((await stop(deps, { id, authorization: `Bearer ${token}`, client: "a" })).status, 410, "stopping twice says gone");
});

test("expiry: readable until the last second, gone after, erased on that read", async () => {
  const store = new MemoryStore();
  const { clock, deps, make } = world(store);
  const { id, expires } = made(await make());
  clock.now = Date.parse(expires) - 1;
  assert.equal((await read(deps, { id, client: "a" })).status, 200);
  clock.now = Date.parse(expires);
  assert.equal((await read(deps, { id, client: "a" })).status, 410);
  assert.equal(store.size, 0, "the expired copy was erased when it was asked for");
});

test("the scheduled clean-up erases expired copies nobody asked for, and only those", async () => {
  const store = new MemoryStore();
  const { clock, deps, make } = world(store);
  const old = made(await make());
  clock.now += 10 * DAY;
  const young = made(await make());
  clock.now = Date.parse(old.expires) + 1000;
  assert.deepEqual((await sweep(deps)).json, { erased: 1 });
  assert.equal(await store.get(old.id), null);
  assert.equal((await read(deps, { id: young.id, client: "a" })).status, 200);
});

test("refusals on create: wrong type, too big, too small, wrong version", async () => {
  const { make } = world();
  assert.deepEqual([(await make(locked(), "a", "application/json")).status, error(await make(locked(), "a", null))], [415, "type"]);
  assert.equal((await make(locked(LIMITS.maxBytes))).status, 201, "exactly the cap is kept");
  const big = await make(locked(LIMITS.maxBytes + 1));
  assert.deepEqual([big.status, error(big)], [413, "too_big"]);
  assert.equal(error(await make("too_big")), "too_big");
  assert.equal(error(await make(locked(LIMITS.minBytes - 1))), "too_small");
  assert.equal(error(await make(locked(400, 2))), "version");
  assert.equal(error(await make(locked(400, 0))), "version");
});

test("an id of the wrong shape is not found; an unknown one is gone", async () => {
  const { deps } = world();
  assert.equal((await read(deps, { id: "../../etc/passwd", client: "a" })).status, 404);
  assert.equal((await read(deps, { id: "short", client: "a" })).status, 404);
  assert.equal((await read(deps, { id: "A".repeat(22), client: "a" })).status, 410);
});

test("rate limits: ten links in ten minutes for one client, others unaffected, then it clears", async () => {
  const { clock, make } = world();
  for (let i = 0; i < LIMITS.create[0]; i++) assert.equal((await make()).status, 201);
  const refused = await make();
  assert.deepEqual([refused.status, error(refused)], [429, "slow_down"]);
  assert.ok(Number(refused.headers?.["Retry-After"]) > 0);
  assert.equal((await make(locked(), "someone-else")).status, 201);
  clock.now += LIMITS.create[1];
  assert.equal((await make()).status, 201);
});

test("rate limits: forty links a day for one client", async () => {
  const { clock, make } = world();
  let ok = 0;
  for (let i = 0; i < 60; i++) {
    if ((await make()).status === 201) ok++;
    clock.now += 11 * 60 * 1000; // past the ten-minute window each time
  }
  assert.equal(ok, LIMITS.createDay[0]);
});

test("rate limits on read and stop", async () => {
  const { deps, make } = world();
  const { id } = made(await make());
  for (let i = 0; i < LIMITS.read[0]; i++) assert.equal((await read(deps, { id, client: "r" })).status, 200);
  assert.equal((await read(deps, { id, client: "r" })).status, 429);
  for (let i = 0; i < LIMITS.stop[0]; i++) await stop(deps, { id, authorization: `Bearer ${"A".repeat(43)}`, client: "s" });
  assert.equal((await stop(deps, { id, authorization: `Bearer ${"A".repeat(43)}`, client: "s" })).status, 429);
});

test("the day's budget for everyone together: links and bytes, reset at midnight UTC", async () => {
  const store = new MemoryStore();
  const { clock, make } = world(store);
  await store.spend("2026-11-16", LIMITS.dayLinks - 1, 0);
  assert.equal((await make(locked(), "x1")).status, 201);
  const full = await make(locked(), "x2");
  assert.deepEqual([full.status, error(full)], [503, "full"]);
  assert.equal(Number(full.headers?.["Retry-After"]), Math.ceil((Date.UTC(2026, 10, 17) - START) / 1000));
  clock.now = Date.UTC(2026, 10, 17, 0, 0, 1);
  await store.spend("2026-11-17", 0, LIMITS.dayBytes - 500);
  assert.equal((await make(locked(400), "x3")).status, 201);
  assert.equal(error(await make(locked(400), "x4")), "full");
});

test("with no storage set up, every call says unavailable rather than pretend", async () => {
  const { deps, make } = world(null);
  assert.deepEqual([(await make()).status, error(await make())], [503, "unavailable"]);
  assert.equal((await read(deps, { id: "A".repeat(22), client: "a" })).status, 503);
  assert.equal((await sweep(deps)).status, 503);
});

// ---------- the stores ----------

/** A stand-in for Upstash's REST interface that understands the commands UpstashStore sends. */
function fakeUpstash(clock: { now: number }) {
  const strings = new Map<string, { value: string; pxat?: number }>();
  const hashes = new Map<string, Record<string, number>>();
  const seen: string[][] = [];
  const live = (k: string) => {
    const e = strings.get(k);
    if (e?.pxat !== undefined && e.pxat <= clock.now) strings.delete(k);
    return strings.get(k);
  };
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    assert.equal(String(url), "https://fake.upstash.test");
    assert.equal((init?.headers as Record<string, string>).authorization, "Bearer secret");
    const c = JSON.parse(String(init?.body)) as string[];
    seen.push(c.map(String));
    let result: unknown;
    switch (c[0]) {
      case "SET":
        assert.deepEqual([c[3], c[4]], ["NX", "PXAT"]);
        result = live(c[1]) ? null : (strings.set(c[1], { value: c[2], pxat: Number(c[5]) }), "OK");
        break;
      case "GET":
        result = live(c[1])?.value ?? null;
        break;
      case "DEL":
        result = strings.delete(c[1]) ? 1 : 0;
        break;
      case "SCAN":
        result = ["0", [...strings.keys()].filter((k) => k.startsWith("b:"))];
        break;
      case "PTTL": {
        const e = live(c[1]);
        result = !e ? -2 : e.pxat === undefined ? -1 : e.pxat - clock.now;
        break;
      }
      case "HMGET": {
        const h = hashes.get(c[1]) ?? {};
        result = c.slice(2).map((field) => (h[field] === undefined ? null : String(h[field])));
        break;
      }
      case "HGETALL": {
        const h = hashes.get(c[1]) ?? {};
        result = Object.entries(h).flatMap(([k, v]) => [k, String(v)]);
        break;
      }
      case "EVAL": {
        const key = c[3];
        const [dl, db, maxLinks, maxBytes] = c.slice(4, 8).map(Number);
        const h = hashes.get(key) ?? {};
        const l = h.links ?? 0, b = h.bytes ?? 0;
        if (l + dl > maxLinks || b + db > maxBytes) {
          result = [0, l, b];
        } else {
          h.links = l + dl;
          h.bytes = b + db;
          hashes.set(key, h);
          result = [1, h.links, h.bytes];
        }
        break;
      }
      case "HINCRBY": {
        const h = hashes.get(c[1]) ?? {};
        h[c[2]] = (h[c[2]] ?? 0) + Number(c[3]);
        hashes.set(c[1], h);
        result = h[c[2]];
        break;
      }
      case "EXPIRE":
        result = 1;
        break;
      default:
        return new Response(JSON.stringify({ error: `ERR unknown command ${c[0]}` }), { status: 400 });
    }
    return new Response(JSON.stringify({ result }));
  }) as typeof fetch;
  return { fetcher, strings, seen };
}

const stores: Record<string, (clock: { now: number }) => Promise<{ store: Store; done: () => Promise<void>; raw: () => Promise<string> }>> = {
  memory: async () => ({ store: new MemoryStore(), done: async () => {}, raw: async () => "" }),
  file: async () => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "uth-links-"));
    const store = new FileStore(dir);
    const raw = async () =>
      (await Promise.all((await readdir(dir)).filter((f) => !f.endsWith(".tmp")).map((f) => readFile(path.join(dir, f), "utf8")))).join("\n");
    return {
      store,
      done: async () => {
        await store.flush();
        await rm(dir, { recursive: true, force: true });
      },
      raw,
    };
  },
  "upstash (against a stand-in)": async (clock) => {
    const fake = fakeUpstash(clock);
    return { store: new UpstashStore("https://fake.upstash.test", "secret", fake.fetcher), done: async () => {}, raw: async () => JSON.stringify([...fake.strings]) + JSON.stringify(fake.seen) };
  },
};

// The real thing, when a database is given: TEST_DATABASE_URL=postgres://… pnpm test
// It uses its own tables (linktest_*) and drops them afterwards, so it can share a database.
if (process.env.TEST_DATABASE_URL) {
  stores["postgres (a real Neon database)"] = async () => {
    const sql = neon(process.env.TEST_DATABASE_URL!);
    const sent: string[] = [];
    const drop = async () => {
      await sql.query("DROP TABLE IF EXISTS linktest_copies", []);
      await sql.query("DROP TABLE IF EXISTS linktest_days", []);
      await sql.query("DROP TABLE IF EXISTS linktest_counts", []);
    };
    await drop();
    const store = new PostgresStore(async (text, values) => {
      sent.push(text + JSON.stringify(values));
      return (await sql.query(text, values)) as Record<string, unknown>[];
    }, "linktest");
    return { store, done: drop, raw: async () => sent.join("\n") };
  };
}

for (const [name, open] of Object.entries(stores)) {
  test(`${name} store: the whole life of a link`, async () => {
    const clock = { now: START };
    const { store, done, raw } = await open(clock);
    try {
      const deps: Deps = { store, limiter: new Limiter(), now: () => clock.now };
      const body = locked(5000);
      const a = made(await create(deps, { contentType: OCTETS, body, client: "a" }));
      const b = made(await create(deps, { contentType: OCTETS, body: locked(64), client: "a" }));
      assert.deepEqual((await read(deps, { id: a.id, client: "a" })).bytes, body);
      assert.ok(!(await raw()).includes(a.stop), "the stop token is nowhere in what is kept or sent to storage");
      assert.equal(await store.put(a.id, { bytes: locked(40), expires: clock.now + DAY, stopHash: "x" }), false, "an id is never reused");
      assert.equal((await stop(deps, { id: a.id, authorization: `Bearer ${a.stop}`, client: "a" })).status, 204);
      assert.equal((await read(deps, { id: a.id, client: "a" })).status, 410);
      assert.equal((await read(deps, { id: b.id, client: "a" })).status, 200);
      assert.deepEqual(await store.spend("2026-11-16", 0, 0), { links: 2, bytes: 5064 });
      clock.now = Date.parse(b.expires) + 1;
      await sweep(deps);
      assert.equal(await store.get(b.id), null, "erased after 30 days");
    } finally {
      await done();
    }
  });
}

test("upstash store: a copy is set once, with the moment it expires, so Redis erases it by itself", async () => {
  const clock = { now: START };
  const fake = fakeUpstash(clock);
  const store = new UpstashStore("https://fake.upstash.test", "secret", fake.fetcher);
  await store.put("A".repeat(22), { bytes: locked(40), expires: START + LIMITS.lifeMs, stopHash: "h" });
  const set = fake.seen.find((c) => c[0] === "SET")!;
  assert.deepEqual([set[1], set[3], set[4], set[5]], [`b:${"A".repeat(22)}`, "NX", "PXAT", String(START + LIMITS.lifeMs)]);
  clock.now = START + LIMITS.lifeMs;
  assert.equal(await store.get("A".repeat(22)), null);
});

test("one client's bytes in a day are limited, so one network cannot spend the day's allowance alone", async () => {
  const { make } = world();
  const big = LIMITS.maxBytes;
  const fit = Math.floor(LIMITS.createBytesDay[0] / big);
  for (let i = 0; i < fit; i++) assert.equal((await make(locked(big))).status, 201, `ring ${i + 1}`);
  const refused = await make(locked(big));
  assert.deepEqual([refused.status, error(refused)], [429, "slow_down"]);
  // another network is not held by it
  assert.equal((await make(locked(big), "b")).status, 201);
});

test("a refused 503 full request does not burn the day's remaining bytes, and status never writes", async () => {
  for (const [name, open] of Object.entries(stores)) {
    const clock = { now: START };
    const { store, done } = await open(clock);
    try {
      const deps: Deps = { store, limiter: new Limiter(), now: () => clock.now };
      // status on an untouched day leaves nothing written
      assert.equal((await status(deps)).status, 200);
      assert.deepEqual(await store.spent("2026-11-16"), { links: 0, bytes: 0 }, `${name}: read-only status`);

      await store.spend("2026-11-16", 0, LIMITS.dayBytes - 500);
      // 1,000 bytes is over the remaining 500 -> 503 full, and the remaining 500 stays available
      const over = await create(deps, { contentType: OCTETS, body: locked(1000), client: "big" });
      assert.deepEqual([over.status, error(over)], [503, "full"], `${name}: oversize refused`);
      assert.deepEqual(await store.spent("2026-11-16"), { links: 0, bytes: LIMITS.dayBytes - 500 }, `${name}: nothing burned`);

      const fits = await create(deps, { contentType: OCTETS, body: locked(400), client: "small" });
      assert.equal(fits.status, 201, `${name}: smaller link still fits`);
      assert.deepEqual(await store.spent("2026-11-16"), { links: 1, bytes: LIMITS.dayBytes - 100 });
    } finally {
      await done();
    }
  }
});

test("when every id attempt collides, the day's budget is refunded", async () => {
  const store = new MemoryStore();
  const fixed = () => new Uint8Array(32).fill(7);
  const deps: Deps = { store, limiter: new Limiter(), now: () => START, random: fixed };
  assert.equal((await create(deps, { contentType: OCTETS, body: locked(400), client: "a" })).status, 201);
  // same random bytes -> all 3 attempts collide with the first id -> 503 and refunded back to 1 link
  const second = await create(deps, { contentType: OCTETS, body: locked(400), client: "b" });
  assert.deepEqual([second.status, error(second)], [503, "unavailable"]);
  assert.deepEqual(await store.spent("2026-11-16"), { links: 1, bytes: 400 });
});

test("positiveInt falls back cleanly on NaN, empty, zero, negative, or non-integer env values", () => {
  assert.equal(positiveInt(undefined, 1000), 1000);
  assert.equal(positiveInt("", 1000), 1000);
  assert.equal(positiveInt("   ", 1000), 1000);
  assert.equal(positiveInt("12MB", 1000), 1000);
  assert.equal(positiveInt("0", 1000), 1000);
  assert.equal(positiveInt("-50", 1000), 1000);
  assert.equal(positiveInt("3.5", 1000), 1000);
  assert.equal(positiveInt("Infinity", 1000), 1000);
  assert.equal(positiveInt("250", 1000), 250);
  assert.equal(positiveInt(" 250 ", 1000), 250);
});

test("unexpected storage failures answer 503 unavailable, and Postgres tolerates a 23505 DDL race", async () => {
  const boom = async (): Promise<never> => {
    throw new Error("db unreachable");
  };
  const broken: Store = { put: boom, get: boom, remove: boom, sweep: boom, spent: boom, spend: boom, trySpend: boom, count: boom, counts: boom };
  const deps: Deps = { store: broken, limiter: new Limiter(), now: () => START };
  assert.equal((await create(deps, { contentType: OCTETS, body: locked(400), client: "a" })).status, 503);
  assert.equal((await read(deps, { id: "A".repeat(22), client: "a" })).status, 503);
  assert.equal((await stop(deps, { id: "A".repeat(22), authorization: `Bearer ${"A".repeat(43)}`, client: "a" })).status, 503);
  assert.equal((await status(deps)).status, 503);
  assert.equal((await sweep(deps)).status, 503);

  let raced = false;
  const pg = new PostgresStore(async (sql) => {
    if (sql.startsWith("CREATE TABLE") && !raced) {
      raced = true;
      throw Object.assign(new Error("duplicate key value violates unique constraint pg_type_typname_nsp_index"), { code: "23505" });
    }
    if (sql.startsWith("INSERT INTO link_days") && sql.includes("SELECT")) return [];
    if (sql.startsWith("SELECT links, bytes")) return [{ links: 1000, bytes: 500 }];
    return [];
  });
  const res = await pg.trySpend("2026-11-16", 1, 400, 1000, 10000);
  assert.deepEqual(res, { ok: false, spent: { links: 1000, bytes: 500 } });
});

test("bodyOf catches a broken request stream without throwing, and bearerMatches checks secrets safely", async () => {
  const brokenStream = new ReadableStream<Uint8Array>({
    pull() {
      throw new Error("connection reset");
    },
  });
  const req = new Request("https://uponthyhead.app/api/b", { method: "POST", body: brokenStream, duplex: "half" } as RequestInit);
  const body = await bodyOf(req);
  assert.equal(body, "bad_stream");
  const { deps } = world();
  const ans = await create(deps, { contentType: OCTETS, body, client: "a" });
  assert.equal(ans.status, 400);

  assert.equal(bearerMatches("Bearer s3cr3t", "s3cr3t"), true);
  assert.equal(bearerMatches("Bearer s3cr3t-longer", "s3cr3t"), false);
  assert.equal(bearerMatches("Bearer ", ""), false);
  assert.equal(bearerMatches(null, "s3cr3t"), false);
});

test("status and sweep routes rate-limit failed bearer guesses while letting the owner through", async () => {
  const prevStatus = process.env.STATUS_SECRET;
  const prevCron = process.env.CRON_SECRET;
  const prevLocal = process.env.LINKS_LOCAL_DIR;
  const dir = await mkdtemp(path.join(os.tmpdir(), "uth-admin-"));
  process.env.STATUS_SECRET = "owner-status-secret";
  process.env.CRON_SECRET = "owner-cron-secret";
  process.env.LINKS_LOCAL_DIR = dir;
  try {
    const { GET: getStatus } = await import("../app/api/status/route.ts");
    const { GET: getSweep } = await import("../app/api/sweep/route.ts");
    for (let i = 0; i < 10; i++) {
      const r = await getStatus(new Request("https://uponthyhead.app/api/status", { headers: { authorization: `Bearer wrong-${i}` } }));
      assert.equal(r.status, 401);
    }
    const throttled = await getSweep(new Request("https://uponthyhead.app/api/sweep", { headers: { authorization: "Bearer wrong-10" } }));
    assert.equal(throttled.status, 429);
    // valid secret still works even while wrong guesses are throttled
    const okStatus = await getStatus(new Request("https://uponthyhead.app/api/status", { headers: { authorization: "Bearer owner-status-secret" } }));
    assert.equal(okStatus.status, 200);
    const okSweep = await getSweep(new Request("https://uponthyhead.app/api/sweep", { headers: { authorization: "Bearer owner-cron-secret" } }));
    assert.equal(okSweep.status, 200);
  } finally {
    if (prevStatus === undefined) delete process.env.STATUS_SECRET; else process.env.STATUS_SECRET = prevStatus;
    if (prevCron === undefined) delete process.env.CRON_SECRET; else process.env.CRON_SECRET = prevCron;
    if (prevLocal === undefined) delete process.env.LINKS_LOCAL_DIR; else process.env.LINKS_LOCAL_DIR = prevLocal;
    await rm(dir, { recursive: true, force: true });
  }
});
