// The rate-limit table has a hard bound: a flood of new senders cannot grow it without limit.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Limiter } from "../lib/links/service.ts";

test("past its bound the table stops growing and new senders share one allowance", () => {
  const limiter = new Limiter();
  const rule = [5, 60_000] as const;
  for (let i = 0; i < Limiter.maxClients; i++) assert.equal(limiter.take("create", `c${i}`, rule, 0), 0);
  // 5 more new senders fit in the shared allowance; the next ones are told to wait
  for (let i = 0; i < 5; i++) assert.equal(limiter.take("create", `new${i}`, rule, 1), 0);
  assert.ok(limiter.take("create", "new5", rule, 1) > 0);
  assert.ok(limiter.take("create", "new6", rule, 1) > 0);
  // a sender already counted keeps their own allowance
  assert.equal(limiter.take("create", "c0", rule, 1), 0);
  // once the windows have run out there is room again
  assert.equal(limiter.take("create", "later", rule, 60_001), 0);
});
