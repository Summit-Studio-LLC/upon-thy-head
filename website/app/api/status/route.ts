import { status } from "../../../lib/links/service.ts";
import { bearerMatches, clientOf, deps, respond } from "../b/http.ts";

/**
 * For the owner: today's and yesterday's totals, allowance used, and counts (links made with and
 * without proof, proofs that verified and that failed). Needs "Authorization: Bearer <secret>", where
 * the secret is STATUS_SECRET if that is set, otherwise CRON_SECRET. (Vercel will not show a stored
 * secret again, and CRON_SECRET's value was not kept, so the status check has one of its own.)
 */
export async function GET(request: Request) {
  const d = deps();
  const secret = process.env.STATUS_SECRET || process.env.CRON_SECRET || "";
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    const wait = d.limiter.take("admin-auth", clientOf(request), [10, 10 * 60 * 1000], d.now());
    if (wait) return respond({ status: 429, headers: { "Retry-After": String(wait) }, json: { error: "slow_down" } });
    return respond({ status: 401, json: { error: "no_token" } });
  }
  return respond(await status(d));
}
