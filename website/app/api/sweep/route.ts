import { sweep } from "../../../lib/links/service.ts";
import { bearerMatches, clientOf, deps, respond } from "../b/http.ts";

/**
 * The scheduled clean-up (vercel.json runs it once a day). Vercel sends
 * "Authorization: Bearer <CRON_SECRET>"; without that secret set, nobody can run it.
 */
export async function GET(request: Request) {
  const d = deps();
  const secret = process.env.CRON_SECRET ?? "";
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    const wait = d.limiter.take("admin-auth", clientOf(request), [10, 10 * 60 * 1000], d.now());
    if (wait) return respond({ status: 429, headers: { "Retry-After": String(wait) }, json: { error: "slow_down" } });
    return respond({ status: 401, json: { error: "no_token" } });
  }
  return respond(await sweep(d));
}
