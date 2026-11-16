import { timingSafeEqual } from "node:crypto";
import { sweep } from "../../../lib/links/service.ts";
import { deps, respond } from "../b/http.ts";

/**
 * The scheduled clean-up (vercel.json runs it once a day). Vercel sends
 * "Authorization: Bearer <CRON_SECRET>"; without that secret set, nobody can run it.
 */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET ?? "";
  const given = Buffer.from(request.headers.get("authorization") ?? "");
  const wanted = Buffer.from(`Bearer ${secret}`);
  if (!secret || given.length !== wanted.length || !timingSafeEqual(given, wanted)) return respond({ status: 401, json: { error: "no_token" } });
  return respond(await sweep(deps()));
}
