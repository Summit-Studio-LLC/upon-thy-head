import { timingSafeEqual } from "node:crypto";
import { status } from "../../../lib/links/service.ts";
import { deps, respond } from "../b/http.ts";

/**
 * For the owner: today's and yesterday's totals, allowance used, and counts (links made with and
 * without proof, proofs that verified and that failed). Needs "Authorization: Bearer <CRON_SECRET>".
 */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET ?? "";
  const given = Buffer.from(request.headers.get("authorization") ?? "");
  const wanted = Buffer.from(`Bearer ${secret}`);
  if (!secret || given.length !== wanted.length || !timingSafeEqual(given, wanted)) return respond({ status: 401, json: { error: "no_token" } });
  return respond(await status(deps()));
}
