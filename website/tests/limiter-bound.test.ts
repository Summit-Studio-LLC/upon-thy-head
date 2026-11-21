// The rate limiter: bounded memory, fixed work per request, nobody locked out by a flood.
import assert from "node:assert/strict";
import { test } from "node:test";
import { networkOf } from "../app/api/b/http.ts";
import { Limiter } from "../lib/links/service.ts";

test("a table never grows past its bound, and a full table refuses nobody", () => {
  const limiter = new Limiter();
  const rule = [5, 60_000] as const;
  for (let i = 0; i < Limiter.maxClients; i++) assert.equal(limiter.take("create", `c${i}`, rule, 0), 0);
  assert.equal(limiter.size("create"), Limiter.maxClients);
  // new senders are still served; the table stays at its bound
  for (let i = 0; i < 1000; i++) assert.equal(limiter.take("create", `new${i}`, rule, 1), 0);
  assert.equal(limiter.size("create"), Limiter.maxClients);
});

test("the one dropped to make room is whoever has gone longest without a request", () => {
  const limiter = new Limiter();
  const rule = [2, 60_000] as const;
  for (let i = 0; i < Limiter.maxClients; i++) limiter.take("read", `c${i}`, rule, 0);
  limiter.take("read", "c0", rule, 1); // c0 has now used both of its two
  limiter.take("read", "fresh", rule, 2); // drops c1, the longest idle, not c0
  assert.ok(limiter.take("read", "c0", rule, 3) > 0, "c0 is still counted and still at its limit");
  assert.equal(limiter.take("read", "c1", rule, 3), 0, "c1 was dropped and starts again");
});

test("each kind of request has its own table", () => {
  const limiter = new Limiter();
  for (let i = 0; i < Limiter.maxClients; i++) limiter.take("create-day", `c${i}`, [40, 86_400_000], 0);
  assert.equal(limiter.size("read"), 0);
  assert.equal(limiter.take("read", "anyone", [120, 60_000], 1), 0);
  assert.equal(limiter.size("create-day"), Limiter.maxClients);
});

test("a sender over their limit waits, and is let in again when the window ends", () => {
  const limiter = new Limiter();
  const rule = [2, 60_000] as const;
  assert.equal(limiter.take("stop", "a", rule, 0), 0);
  assert.equal(limiter.take("stop", "a", rule, 1), 0);
  assert.equal(limiter.take("stop", "a", rule, 2), 60);
  assert.equal(limiter.take("stop", "a", rule, 60_000), 0);
});

test("IPv6 senders are counted by their /64, IPv4 singly", () => {
  assert.equal(networkOf("203.0.113.7"), "203.0.113.7");
  assert.equal(networkOf("2001:db8:12:3400:1:2:3:4"), "2001:db8:12:3400::/64");
  assert.equal(networkOf("2001:0db8:0012:3400:ffff:ffff:ffff:ffff"), "2001:db8:12:3400::/64");
  assert.equal(networkOf("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(networkOf("2001:db8::abcd:1"), networkOf("2001:db8::ffff:2"));
  assert.notEqual(networkOf("2001:db8:0:1::1"), networkOf("2001:db8:0:2::1"));
  assert.equal(networkOf("::1"), "0:0:0:0::/64");
  assert.equal(networkOf("::ffff:203.0.113.7"), "::ffff:203.0.113.7");
  assert.equal(networkOf(""), "");
});

test("the ceilings for everyone hold however many senders there are", async () => {
  const { read, LIMITS } = await import("../lib/links/service.ts");
  const limiter = new Limiter();
  const deps = { store: null, limiter, now: () => 0 };
  const id = "A".repeat(22);
  const [max] = LIMITS.readAll;
  let slowed = 0;
  // every request comes from a sender never seen before, so no per-client limit can catch it
  for (let i = 0; i < max + 50; i++) {
    const answer = await read(deps, { id, client: `sender${i}` });
    if (answer.status === 429) slowed++;
  }
  assert.equal(slowed, 50);
});

test("a sender already being counted is not refused when newcomers have used up the shared allowance", async () => {
  const { read, LIMITS } = await import("../lib/links/service.ts");
  const limiter = new Limiter();
  const deps = { store: null, limiter, now: () => 0 };
  const id = "A".repeat(22);
  assert.notEqual((await read(deps, { id, client: "honest" })).status, 429);
  for (let i = 0; i < LIMITS.readAll[0] + 10; i++) await read(deps, { id, client: `flood${i}` });
  assert.equal((await read(deps, { id, client: "one more newcomer" })).status, 429);
  assert.notEqual((await read(deps, { id, client: "honest" })).status, 429);
});

test("a stop request with no usable token is refused before anything is counted", async () => {
  const { stop, LIMITS } = await import("../lib/links/service.ts");
  const limiter = new Limiter();
  const deps = { store: null, limiter, now: () => 0 };
  const id = "A".repeat(22);
  for (let i = 0; i < LIMITS.stop[0] + 20; i++) assert.equal((await stop(deps, { id, authorization: null, client: "x" })).status, 401);
  assert.equal(limiter.size("stop"), 0);
});

test("a newcomer refused by the shared ceiling does not become known or bypass it on a second request", () => {
  const limiter = new Limiter();
  const own = [10, 60_000] as const;
  const shared = [3, 60_000] as const;
  for (let i = 0; i < 3; i++) assert.equal(limiter.takeWithCeiling("read", `ok${i}`, own, shared, 0), 0);
  assert.equal(limiter.size("read"), 3);
  // 4th newcomer hits the shared ceiling; must not enter the "read" table or slip past on a 2nd ask
  assert.ok(limiter.takeWithCeiling("read", "late", own, shared, 1) > 0);
  assert.equal(limiter.knows("read", "late", 1), false);
  assert.equal(limiter.size("read"), 3);
  assert.ok(limiter.takeWithCeiling("read", "late", own, shared, 2) > 0, "still held by the shared ceiling on the 2nd request");
});

test("takeAll takes from every bucket or from none when a later check refuses", () => {
  const limiter = new Limiter();
  const checks = [
    { what: "create", client: "a", limit: [10, 60_000] as const },
    { what: "create-day", client: "a", limit: [40, 86_400_000] as const },
    { what: "create-bytes-day", client: "a", limit: [1000, 86_400_000] as const, amount: 2000 },
  ];
  assert.ok(limiter.takeAll(checks, 0) > 0);
  assert.equal(limiter.size("create"), 0);
  assert.equal(limiter.size("create-day"), 0);
  assert.equal(limiter.size("create-bytes-day"), 0);
});

test("challenge and prove share the single proof-all newcomer ceiling", async () => {
  const { challenge, prove, LIMITS } = await import("../lib/links/service.ts");
  const limiter = new Limiter();
  const deps = { store: null, limiter, now: () => 0 };
  const half = LIMITS.proofAll[0] / 2;
  for (let i = 0; i < half; i++) assert.notEqual((await challenge(deps, { client: `c${i}` })).status, 429);
  for (let i = 0; i < half; i++) {
    assert.notEqual((await prove(deps, { contentType: "application/json", body: new Uint8Array(2), client: `p${i}` })).status, 429);
  }
  assert.equal((await challenge(deps, { client: "one-more-c" })).status, 429);
  assert.equal((await prove(deps, { contentType: "application/json", body: new Uint8Array(2), client: "one-more-p" })).status, 429);
});
