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
