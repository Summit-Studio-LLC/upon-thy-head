// The service: create, read, stop, expiry (with a clock the test controls), limits, and each store.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { type Answer, type Deps, LIMITS, Limiter, create, read, stop, sweep } from "../lib/links/service.ts";
import { FileStore, MemoryStore, type Store, UpstashStore } from "../lib/links/store.ts";

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
    const raw = async () => (await Promise.all((await readdir(dir)).map((f) => readFile(path.join(dir, f), "utf8")))).join("\n");
    return { store: new FileStore(dir), done: () => rm(dir, { recursive: true, force: true }), raw };
  },
  "upstash (against a stand-in)": async (clock) => {
    const fake = fakeUpstash(clock);
    return { store: new UpstashStore("https://fake.upstash.test", "secret", fake.fetcher), done: async () => {}, raw: async () => JSON.stringify([...fake.strings]) + JSON.stringify(fake.seen) };
  },
};

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
